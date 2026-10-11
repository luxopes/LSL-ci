#!/usr/bin/env python3
"""Check LSL conversion bits/end pointers against the host C strtod/strtof.

The C library is used by this test driver only. The tested executable is native
LSL and does not call libc. Include midpoints, subnormals and binary32 double
rounding traps, rather than comparing only decimal text printed with tolerance.
"""
import argparse
import ctypes
import hashlib
import json
from pathlib import Path
import random
import struct
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--compiler', type=Path, required=True)
    parser.add_argument('--qbe', type=Path, default=ROOT/'build/qbe/qbe')
    parser.add_argument('--report', type=Path, required=True)
    parser.add_argument('--random-cases', type=int, default=1200)
    args = parser.parse_args()
    rng = random.Random(0x13B1)
    cases = ['1e300', '1e-6', '1e-12', '5e-324', '2.2250738585072014e-308',
             '2.2250738585072011e-308', '1.7976931348623157e308',
             '1.7976931348623159e308', '1.0000000596046448',
             '1.000000059604644775390625', '1.000000178813934326171875',
             '0x1.0000010000001p0', '0x1.fffffep127', '0x1.ffffffp127',
             '0x1p-150', '0x1.0000001p-150', '0x1p-1075',
             '0x1.0000000000001p-1075', '0x1.fffffffffffffp1023',
             '0', '-0', '+.0', '  -12.5e2 tail', '0x1.8p+1!',
             '1e+', '0x', '0x.', '0xg', '0x:1', 'no digits', '.',
             'INF!', '-infinity!', 'NaN(payload)', '-nan', 'nan(bad!payload)',
             '0e1000000', '-0e-1000000', '1e1000000', '1e-1000000']
    for _ in range(args.random_cases):
        mode = rng.randrange(3)
        sign = '-' if rng.randrange(2) else ''
        if mode == 0:
            coefficient = str(rng.randrange(1, 10**rng.randrange(1, 60)))
            point = rng.randrange(len(coefficient)+1)
            cases.append(f'{sign}{coefficient[:point]}.{coefficient[point:]}e{rng.randrange(-360, 361)}!')
        elif mode == 1:
            coefficient = f'{rng.randrange(1, 1 << rng.randrange(1, 160)):x}'
            point = rng.randrange(len(coefficient)+1)
            cases.append(f'{sign}0x{coefficient[:point]}.{coefficient[point:]}p{rng.randrange(-1200, 1201)}!')
        else:
            bits = rng.getrandbits(64)
            value = struct.unpack('<d', struct.pack('<Q', bits))[0]
            cases.append(format(value, '.17g'))
    library = ctypes.CDLL(None)
    functions = [library.strtod, library.strtof]
    for function, result_type in zip(functions, [ctypes.c_double, ctypes.c_float]):
        function.argtypes = [ctypes.c_char_p, ctypes.POINTER(ctypes.c_char_p)]
        function.restype = result_type
    expected = []
    for text in cases:
        data = text.encode('ascii')
        for function in functions:
            end = ctypes.c_char_p()
            value = function(data, ctypes.byref(end))
            bits = struct.unpack('<q', struct.pack('<d', value))[0]
            expected.append((bits, len(data)-len(end.value or b'')))
    with tempfile.TemporaryDirectory(prefix='qbe-float-oracle-') as temp:
        temp = Path(temp)
        inputs = temp/'input.txt'
        inputs.write_text('\n'.join(cases))
        with tempfile.NamedTemporaryFile(mode='w', suffix='.lsl', prefix='.float-oracle-',
                                         dir=ROOT/'tests/qbe_port', delete=False) as source:
            source_path = Path(source.name)
            source.write('# lsl: internal-abi\nload qbe_port.qbe_float as fp\n')
            source.write(f'for text in readfile({json.dumps(str(inputs))}).split(chr(10)):\n')
            source.write('    for single in [False, True]:\n'
                         '        parsed = fp.parse(text, single)\n'
                         '        print __lsl_float_bits(parsed[0]), parsed[1]\n'
                         '    end\nend\n')
        try:
            executable = temp/'float-oracle'
            subprocess.run([str(args.compiler.resolve()), "--unsafe", str(source_path), str(executable),
                            str(args.qbe.resolve())], cwd=ROOT, check=True, timeout=60)
            result = subprocess.run([str(executable)], capture_output=True, check=True, timeout=60)
            actual = [tuple(map(int, line.split())) for line in result.stdout.splitlines()]
        finally:
            source_path.unlink(missing_ok=True)
    failures = [{'text': cases[index//2], 'single': bool(index % 2),
                 'expected': want, 'actual': got}
                for index, (want, got) in enumerate(zip(expected, actual)) if want != got]
    report = {'seed': '0x13b1', 'conversions': len(expected), 'actual_count': len(actual),
              'input_sha256': hashlib.sha256('\n'.join(cases).encode()).hexdigest(),
              'failures': failures, 'complete': len(actual) == len(expected) and not failures}
    args.report.parent.mkdir(parents=True, exist_ok=True)
    args.report.write_text(json.dumps(report, indent=2)+'\n')
    print(f'{len(expected)-len(failures)}/{len(expected)} exact float conversions; {args.report}')
    return 0 if report['complete'] else 1


if __name__ == '__main__':
    raise SystemExit(main())
