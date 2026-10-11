#!/usr/bin/env python3
"""Check generated bsiter against Python's independent set-bit enumeration."""
import argparse
import hashlib
import json
from pathlib import Path
import random
import re
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--compiler', type=Path, required=True)
    parser.add_argument('--qbe', type=Path, default=ROOT/'build/qbe/qbe')
    parser.add_argument('--source', type=Path, required=True)
    parser.add_argument('--report', type=Path, required=True)
    args = parser.parse_args()
    generated = args.source.read_text()
    function = re.search(r'(?ms)^function q_f_bsiter\(.*?^end\n', generated)[0]
    literals = sorted(set(re.findall(r'\bq_string_\d+\b', function)))
    definitions = [re.search(r'^'+name+r' = mem.literal\(.*\)$', generated, re.M)[0]
                   for name in literals]
    rng = random.Random(0x130064)
    cases = []
    for bit in range(64):
        for start in [0, bit, bit+1, 63, 64, -1]:
            cases.append(([1 << bit], start))
    for size in [0, 1, 2, 3, 16, 65]:
        for _ in range(40):
            words = [rng.getrandbits(64) if rng.randrange(3) else 0 for _ in range(size)]
            start = rng.randrange(size*64+2)
            cases.append((words, start))
    cases += [([0]*n+[1 << 63], start) for n in [1, 4, 64]
              for start in [0, 63, 64, 255]]
    lines = ['# lsl: internal-abi', 'load qbe_port.qbe_memory as mem', function] + definitions
    lines += ['set = mem.malloc(16)', 'data = mem.malloc(65 * 8)',
              'element = mem.malloc(4)', 'call mem.store(set + 8, 8, data)']
    # Test the actual generated function, including its immutable byte table.
    # Expected indexes come from enumerating mathematical set positions.
    def signed(n):
        return n if n < (1 << 63) else n-(1 << 64)
    for case, (words, start) in enumerate(cases):
        bits = [64*i+b for i, word in enumerate(words) for b in range(64) if word & (1 << b)]
        following = [b for b in bits if b >= (start & 0xffffffff)]
        success = int(bool(following))
        end = following[0] if following else start
        lines += [f'call mem.store(set, 4, {len(words)})', f'call mem.store(element, 4, {start})']
        for i, word in enumerate(words):
            lines.append(f'call mem.store(data + {i*8}, 8, {signed(word)})')
        lines += [f'check(q_f_bsiter(set, element) == {success}, "bsiter status {case}")',
                  f'check(mem.load(element, 4, True) == {end}, "bsiter position {case}")']
    lines += ['call gc()', 'print "PASS bitset iteration"']
    with tempfile.TemporaryDirectory(prefix='qbe-bsiter-') as directory:
        with tempfile.NamedTemporaryFile(mode='w', suffix='.lsl', prefix='.bsiter-',
                                         dir=ROOT/'tests/qbe_port', delete=False) as file:
            source = Path(file.name)
            file.write('\n'.join(lines)+'\n')
        try:
            executable = Path(directory)/'bsiter'
            subprocess.run([str(args.compiler.resolve()), "--unsafe", str(source), str(executable),
                            str(args.qbe.resolve())], cwd=ROOT, check=True, timeout=60)
            result = subprocess.run([str(executable)], capture_output=True, timeout=30)
        finally:
            source.unlink(missing_ok=True)
    report = {'cases': len(cases), 'complete': result.returncode == 0,
              'returncode': result.returncode, 'stdout': result.stdout.decode(errors='replace'),
              'stderr': result.stderr.decode(errors='replace'),
              'generated_source_sha256': hashlib.sha256(generated.encode()).hexdigest()}
    args.report.parent.mkdir(parents=True, exist_ok=True)
    args.report.write_text(json.dumps(report, indent=2)+'\n')
    print(f"bsiter: {len(cases)} cases, complete={report['complete']}")
    return 0 if report['complete'] else 1


if __name__ == '__main__':
    raise SystemExit(main())
