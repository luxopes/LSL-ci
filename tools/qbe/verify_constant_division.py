#!/usr/bin/env python3
"""Check constant floor division/remainder against Python unbounded integers."""
import argparse
import hashlib
import json
from pathlib import Path
import random
import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'qbe_port'))
from compare_v089 import execute, digest


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--compiler', type=Path, required=True)
    parser.add_argument('--backend', type=Path, required=True)
    parser.add_argument('--build-directory', type=Path, required=True)
    args = parser.parse_args()
    build = args.build_directory.resolve()
    build.mkdir(parents=True, exist_ok=True)
    rng = random.Random(173)
    divisors = sorted(set([1, 2, 3, 5, 7, 9, 10, 17, 31, 33, 63, 65, 97,
                           127, 255, 257, 65535, 65537, 2147483647, 2147483649,
                           9223372036854775807]
                          + [1 << k for k in range(1, 63)]
                          + [rng.randrange(3, 1 << 31) for _ in range(50)]))
    numbers = sorted(set([-(1 << 63), -(1 << 63)+1, -4294967297, -4294967296,
                          -2147483649, -2147483648, -2147483647, -98, -97, -96, -3, -1, 0, 1, 3, 96, 97,
                          98, 2147483647, 2147483648, 2147483649, 4294967295, 4294967296, (1 << 63)-1]
                         + [rng.randrange(-(1 << 63), 1 << 63) for _ in range(80)]))
    lines = []
    expected = []
    for index, divisor in enumerate(divisors):
        lines += [f'function check{index}(value):', '    n = Int(value)',
                  f'    print n // {divisor}, n % {divisor}', 'end']
    lines += ['values = IntArray()']
    for number in numbers:
        lines.append(f'values.append({number})')
    for index, divisor in enumerate(divisors):
        values = numbers + [divisor-1, divisor, min(divisor+1, (1 << 63)-1), -divisor]
        lines += ['for n in values:', f'    call check{index}(n)', 'end']
        for number in values[len(numbers):]:
            lines.append(f'call check{index}({number})')
        expected += [f'{n // divisor} {n % divisor}\n' for n in values]
    source = build / 'constant_division.lsl'
    source.write_text('\n'.join(lines)+'\n')
    oracle = ''.join(expected).encode()
    (build / 'expected.txt').write_bytes(oracle)
    output = build / 'constant_division'
    command = [args.compiler.resolve(), "--unsafe", source, output, args.backend.resolve()]
    compiled, _ = execute(command, timeout=60)
    result, stdout = execute([output], timeout=60)
    (build / 'actual.txt').write_bytes(stdout)
    report = {'compiler_sha256': digest(args.compiler), 'backend_sha256': digest(args.backend),
              'source_sha256': digest(source), 'binary_sha256': digest(output),
              'command': [str(x) for x in command], 'build': compiled, 'run': result,
              'divisors': divisors, 'numerators': numbers, 'pairs': len(expected),
              'oracle': 'Python signed unbounded floor division and remainder',
              'oracle_sha256': hashlib.sha256(oracle).hexdigest(),
              'actual_sha256': hashlib.sha256(stdout).hexdigest(), 'passed': stdout == oracle}
    (build / 'verification.json').write_text(json.dumps(report, indent=2)+'\n')
    if stdout != oracle:
        for index, (actual, wanted) in enumerate(zip(stdout.splitlines(), oracle.splitlines())):
            if actual != wanted:
                raise AssertionError(f'case {index}: {actual!r} != {wanted!r}')
        raise AssertionError('division output length mismatch')
    print(f'PASS {len(expected)} constant division/remainder pairs')


if __name__ == '__main__':
    main()
