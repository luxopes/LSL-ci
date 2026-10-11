#!/usr/bin/env python3
"""Compare QBE option placement, stdin/stdout and large buffered output."""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import tempfile

from verify_backend import ROOT, DEFAULT_TARGETS


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--backend', type=Path, required=True)
    parser.add_argument('--reference', type=Path, default=ROOT/'build/qbe/qbe')
    parser.add_argument('--report', type=Path, required=True)
    args = parser.parse_args()
    binaries = [args.reference.resolve(), args.backend.resolve()]
    report = {'binaries': [{'path': str(p), 'sha256': hashlib.sha256(p.read_bytes()).hexdigest()}
                           for p in binaries], 'cases': [], 'complete': False}
    source = ROOT/'vendor/qbe-1.3/test/_bfmandel.ssa'
    with tempfile.TemporaryDirectory(prefix='qbe cli ') as temporary:
        output = Path(temporary)/'output with spaces.s'
        for target in DEFAULT_TARGETS:
            variants = [
                ['-t', target, '-o', str(output), str(source)],
                [str(source), '-t', target, '-o', str(output)],
                ['-o', str(output), str(source), '-t', target],
                ['-t'+target, '-o'+str(output), str(source)],
                ['-o'+str(output), '-t'+target, '--', str(source)],
                ['-o'+str(output), str(source), '-t'+target, '--'],
                ['-t', target, '-o', str(output), '-'],
                ['-t', target, '-o', '-', str(source)],
            ]
            for index, options in enumerate(variants):
                results = []
                for binary in binaries:
                    output.unlink(missing_ok=True)
                    result = subprocess.run([str(binary), *options], cwd=ROOT,
                                            input=source.read_bytes(), capture_output=True, timeout=30)
                    assembly = output.read_bytes() if output.exists() else result.stdout
                    results.append((result.returncode, assembly, result.stderr))
                passed = results[0][0] == results[1][0] == 0 and results[0][1] == results[1][1]
                report['cases'].append({'target': target, 'variant': index, 'pass': passed,
                                        'reference_exit': results[0][0], 'backend_exit': results[1][0],
                                        'output_bytes': len(results[1][1])})
    report['complete'] = all(r['pass'] for r in report['cases'])
    args.report.parent.mkdir(parents=True, exist_ok=True)
    args.report.write_text(json.dumps(report, indent=2)+'\n')
    print(f"{sum(r['pass'] for r in report['cases'])}/{len(report['cases'])} CLI cases pass")
    return 0 if report['complete'] else 1


if __name__ == '__main__':
    raise SystemExit(main())
