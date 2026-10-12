#!/usr/bin/env python3
"""Verify native QBE image API, static PIE protection, ASLR and private cleanup."""
import argparse
import json
import os
import signal
import subprocess
import time
from pathlib import Path
import struct

from verify_public_int import digest, memory_limit, run

ROOT = Path(__file__).resolve().parents[2]


def elf_contract(path):
    data = path.read_bytes()
    header = struct.unpack_from('<16sHHIQQQIHHHHHH', data)
    assert header[0][:7] == b'\x7fELF\x02\x01\x01'
    assert header[1] == 3 and header[2] == 62, 'expected x86_64 ET_DYN'
    segments = []
    dynamic = []
    for index in range(header[10]):
        p = struct.unpack_from('<IIQQQQQQ', data, header[5] + index * header[9])
        segments.append({'type': p[0], 'flags': p[1], 'offset': p[2], 'vaddr': p[3],
                         'file_bytes': p[5], 'memory_bytes': p[6], 'alignment': p[7]})
        assert p[0] != 3, 'dynamic interpreter dependency'
        if p[0] == 1:
            assert p[1] & 3 != 3, 'writable executable LOAD segment'
        if p[0] == 2:
            for offset in range(p[2], p[2] + p[5], 16):
                tag, value = struct.unpack_from('<QQ', data, offset)
                if tag == 0:
                    break
                dynamic.append({'tag': tag, 'value': value})
                assert tag not in (1, 22), 'NEEDED dependency or TEXTREL'
                if tag in (8, 18):
                    assert value == 0, 'startup relocation requires an unprovided loader'
                if tag == 30:
                    assert not value & 4, 'DF_TEXTREL'
    stacks = [p for p in segments if p['type'] == 0x6474e551]
    assert len(stacks) == 1 and stacks[0]['flags'] & 1 == 0, 'executable/missing GNU_STACK'
    assert any(p['type'] == 1 and p['flags'] & 1 for p in segments)
    # A stripped production image must not retain a full symbol table.
    for index in range(header[12]):
        sh_type = struct.unpack_from('<I', data, header[6] + index * header[11] + 4)[0]
        assert sh_type != 2, 'unstripped symbol table'
    return {'bytes': len(data), 'type': 'ET_DYN', 'machine': 'x86_64',
            'segments': segments, 'dynamic': dynamic, 'all_pass': True}


def default_runtime():
    # Vývojový checkout má build/qbe/runtime.o, čistý release jen compiler/qbe/runtime.o.
    development = ROOT / 'build/qbe/runtime.o'
    return development if development.exists() else ROOT / 'compiler/qbe/runtime.o'


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--compiler', type=Path, required=True)
    parser.add_argument('--backend', type=Path, required=True)
    parser.add_argument('--build-directory', type=Path, required=True)
    parser.add_argument('--report', type=Path, required=True)
    parser.add_argument('--runtime', type=Path, default=None,
                        help='runtime object; default build/qbe/runtime.o, else the release compiler/qbe/runtime.o')
    args = parser.parse_args()
    runtime_path = args.runtime or default_runtime()
    build = args.build_directory.resolve()
    build.mkdir(parents=True, exist_ok=True)
    compiler, backend = args.compiler.resolve(), args.backend.resolve()
    report = {'compiler_sha256': digest(compiler), 'backend_sha256': digest(backend),
              'runtime_sha256': digest(runtime_path),
              'scope': 'real frontend -> native LSL QBE -> system as/ld; no C codegen; serialized scratch cleanup check',
              'source_sha256': {str(p.relative_to(ROOT)): digest(p) for p in [
                  ROOT / 'compiler/pure/qbe_toolchain.lsl', ROOT / 'compiler/pure/qbe_emit.lsl',
                  ROOT / 'tests/qbe_port/native_image_toolchain.lsl']},
              'checks': [], 'complete': False, 'all_pass': False}

    def save():
        args.report.parent.mkdir(parents=True, exist_ok=True)
        args.report.write_text(json.dumps(report, indent=2) + '\n')

    def checked(command, expected_code=0):
        row = run(command)
        report['checks'].append(row)
        save()
        assert row['returncode'] == expected_code and not row['timed_out'], row
        return row

    save()
    probe = build / 'image-api-probe'
    checked([compiler, 'tests/qbe_port/native_image_toolchain.lsl', probe, backend])
    source = build / 'entry.lsl'
    source.write_text('load env\nprint env._default_path()\nprint 4+7\nprint input("")\n')
    images = [build / 'first', build / 'second']
    for output in images:
        checked([probe, source, output, backend, '/source/entry/program.lsl'])
        output.chmod(0o700)
    assert digest(images[0]) == digest(images[1]), 'scratch paths leaked into output'
    report['image_sha256'] = digest(images[0])
    report['elf'] = elf_contract(images[0])
    bases = []
    for _ in range(5):
        # Hold the program in its input read while the independent host reads
        # its mappings. LSL readfile intentionally uses a regular-file size and
        # therefore cannot supply a reliable /proc/self/maps oracle.
        start = time.monotonic()
        process = subprocess.Popen([str(images[0])], cwd=ROOT, stdin=subprocess.PIPE,
                                   stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                                   start_new_session=True, preexec_fn=memory_limit)
        try:
            maps = [line for line in Path(f'/proc/{process.pid}/maps').read_text().splitlines()
                    if line.endswith(str(images[0]))]
            assert maps, 'executable mapping missing'
            bases.append(int(maps[0].split('-')[0], 16))
            stdout, stderr = process.communicate(input=b'ready\n', timeout=10)
        except BaseException:
            os.killpg(process.pid, signal.SIGKILL)
            process.communicate()
            raise
        row = {'command': [str(images[0])], 'seconds': time.monotonic() - start,
               'returncode': process.returncode, 'timed_out': False,
               'stdout': stdout.decode(), 'stderr': stderr.decode()}
        report['checks'].append(row)
        save()
        assert row['returncode'] == 0 and row['stdout'] == '/source/entry/.env\n11\nready\n', row
    assert len(set(bases)) > 1, 'ASLR did not change executable base'
    report['aslr_bases'] = bases
    source.write_text('load env\nprint env._default_path()\nprint 4+7\n')
    blank = build / 'blank-entry'
    checked([probe, source, blank, backend, ''])
    blank.chmod(0o700)
    row = run([blank])
    report['checks'].append(row)
    save()
    assert row['returncode'] == 0 and not row['timed_out'], row
    assert row['stdout'].startswith(str(build / '.env') + '\n11\n'), row
    before = set(Path('/tmp').glob('lsl-program-*'))
    row = checked([probe, source, build / 'failure', '/bin/false', ''], expected_code=1)
    assert 'CompileError' in row['stdout'] + row['stderr']
    assert 'LuxIR backend failed' in row['stdout'] + row['stderr']
    assert not (set(Path('/tmp').glob('lsl-program-*')) - before), 'private scratch directory leaked'
    assert not (build / 'failure').exists()
    report['complete'] = report['all_pass'] = True
    report['binaries_unchanged'] = (digest(compiler) == report['compiler_sha256']
                                    and digest(backend) == report['backend_sha256']
                                    and digest(runtime_path) == report['runtime_sha256'])
    assert report['binaries_unchanged']
    save()
    print('PASS deterministic stripped static PIE, source-entry, ASLR, tool failure and cleanup')


if __name__ == '__main__':
    main()
