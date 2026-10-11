#!/usr/bin/env python3
"""Compare native word printf with host libc, including cache and buffer misses.

Libc is a test oracle only; the native LSL executable uses its own formatter.
The corpus exceeds the immutable plan cache, revisits plans after GC, and
mixes buffered output across two files.
"""
import argparse
import ctypes
import hashlib
import json
from pathlib import Path
import re
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--compiler', type=Path, required=True)
    parser.add_argument('--qbe', type=Path, default=ROOT/'build/qbe/qbe')
    parser.add_argument('--report', type=Path, required=True)
    args = parser.parse_args()
    libc = ctypes.CDLL(None)
    libc.snprintf.argtypes = [ctypes.c_void_p, ctypes.c_size_t, ctypes.c_char_p]
    libc.snprintf.restype = ctypes.c_int
    cases=[]
    values=[0,1,-1,42,-123456789,2147483647,-2147483648,9223372036854775807,-9223372036854775808]
    for fmt in ['%lld','%+025lld','% 25.20lld','%-25.0lld','%llu','%025llu','%llx','%020llX','%.0llx']:
        for value in values:
            cases.append((f'[{fmt}]\n',[value]))
    # Pass unsigned words as their signed 64-bit bit patterns, matching the
    # native word ABI. Exercise quotient/remainder near digit boundaries and
    # above INT64_MAX without relying on out-of-range LSL integer literals.
    unsigned_edges = sorted({
        9, 10, 11, 15, 16, 17, 99, 100, 101, 255, 256, 257,
        2**32-1, 2**32, 2**32+1, 2**63-1, 2**63, 2**63+1,
        10**19-1, 10**19, 10**19+1, 2**64-2, 2**64-1,
    })
    for fmt in ['%llu', '%025llu', '%-25.22llu', '%llx', '%020llX', '%.0llx']:
        for unsigned in unsigned_edges:
            word = unsigned if unsigned < 2**63 else unsigned - 2**64
            cases.append((f'edge[{fmt}]\n', [word]))
    for fmt in ['[%*.*s]\n','é:%*.*s:é\n']:
        for width,precision in [(9,3),(-9,3),(0,0),(3,-1),(0,30)]:
            cases.append((fmt,[width,precision,'éhello']))
    for fmt in ['%u|%x|%X\n','%.0d|%+.0d|%.0x\n','%#x|%o|%c\n']:
        cases.append((fmt,[-1,42,65] if '%.0' not in fmt else [0,0,0]))
    cases += [('pre%*d%s\n',[9000,8,'tail']),('prefix%lld!\n',[-9223372036854775808])]
    for n in range(600):
        cases.append((f'{n}:é%03d\n',[n]))
    rows=[]
    expected=[]
    for fmt,values in cases:
        c_arguments = []
        index = 0
        for directive in re.finditer(r'%[-+ #0]*(\*|[0-9]*)(?:\.(\*|[0-9]*))?(ll|[hljztL]*)([a-zA-Z])', fmt):
            width, precision, length, conversion = directive.groups()
            for field in [width, precision]:
                if field == '*':
                    c_arguments.append(ctypes.c_int(values[index]))
                    index += 1
            value = values[index]
            index += 1
            if conversion == 's':
                c_arguments.append(ctypes.c_char_p(value.encode()))
            else:
                signed = conversion not in 'uoxX'
                kind = ((ctypes.c_longlong if signed else ctypes.c_ulonglong)
                        if length == 'll' else (ctypes.c_int if signed else ctypes.c_uint))
                c_arguments.append(kind(value))
        assert index == len(values)
        buf=ctypes.create_string_buffer(20000)
        n=libc.snprintf(buf, len(buf), fmt.encode(), *c_arguments)
        assert 0<=n<len(buf)
        expected.append(buf.raw[:n])
        words=[f'mem.literal({json.dumps(v,ensure_ascii=False)})' if isinstance(v,str) else str(v) for v in values]
        rows.append('    [mem.literal('+json.dumps(fmt,ensure_ascii=False)+'), ['+', '.join(words)+'], '+str(n)+']')
    source='''# lsl: internal-abi
    load qbe_port.qbe_memory as mem
    load qbe_port.qbe_stdio as stdio

    function require(value, message):
        if not value:
            Error(TestFailure: message)
        end
    end

    cases = []
    '''+''.join('cases.append('+row.strip()+')\n' for row in rows)+'''

    words = mem.malloc(64)
    for repeat in rang(3):
        for item in cases:
            values = item[1]
            for index in rang(len(values)):
                call mem.store(words + index * 8, 8, values[index])
            end
            written = stdio.fprintf_words(2, item[0], words, len(values))
            call require(written == item[2], "word fprintf byte count")
        end
        call gc()
    end
    call require(stdio.fflush(2) == 0, "flush stdout")
    # Switch output streams with unflushed cached bytes, then mix all write APIs.
    p1 = arg(1)
    p2 = arg(2)
    a = stdio.fopen(mem.cstr(p1), mem.cstr("w"))
    b = stdio.fopen(mem.cstr(p2), mem.cstr("w"))
    fmt = mem.literal("%03d")
    for value in rang(30):
        call mem.store(words, 8, value)
        call require(stdio.fprintf_words(a, fmt, words, 1) == 3, "stream a count")
        call require(stdio.fprintf_words(b, fmt, words, 1) == 3, "stream b count")
        call stdio.fputs(mem.literal("/"), a)
        call stdio.fputc(47, b)
    end
    call require(stdio.fclose(a) == 0 and stdio.fclose(b) == 0, "close switched streams")
    call require(readfile(p1) == readfile(p2), "stream cache keeps independent counts")
    call require(stdio.fprintf_words(a, fmt, words, 1) == -1, "closed output rejected")
    '''

    source = source.replace('\n    ', '\n')
    expected_bytes = b''.join(expected) * 3
    with tempfile.TemporaryDirectory(prefix='qbe-word-stdio-') as directory:
        directory = Path(directory)
        with tempfile.NamedTemporaryFile(mode='w', suffix='.lsl', prefix='.word-stdio-',
                                         dir=ROOT/'tests/qbe_port', delete=False) as file:
            source_path = Path(file.name)
            file.write(source)
        try:
            executable = directory/'word-stdio'
            subprocess.run([str(args.compiler.resolve()), "--unsafe", str(source_path), str(executable),
                            str(args.qbe.resolve())], cwd=ROOT, check=True, timeout=60)
            result = subprocess.run([str(executable), str(directory/'a'), str(directory/'b')],
                                    capture_output=True, timeout=60)
        finally:
            source_path.unlink(missing_ok=True)
    complete = result.returncode == 0 and result.stdout == expected_bytes
    report = {'formats': len(cases), 'calls': len(cases)*3,
              'expected_bytes': len(expected_bytes), 'actual_bytes': len(result.stdout),
              'expected_sha256': hashlib.sha256(expected_bytes).hexdigest(),
              'actual_sha256': hashlib.sha256(result.stdout).hexdigest(),
              'returncode': result.returncode, 'stderr': result.stderr.decode(errors='replace'),
              'complete': complete}
    args.report.parent.mkdir(parents=True, exist_ok=True)
    args.report.write_text(json.dumps(report, indent=2)+'\n')
    print(f"{len(cases)*3} word printf calls, {len(expected_bytes)} bytes: exact={complete}")
    return 0 if complete else 1


if __name__ == '__main__':
    raise SystemExit(main())
