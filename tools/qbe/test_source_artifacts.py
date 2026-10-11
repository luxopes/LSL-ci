#!/usr/bin/env python3
"""Regression: failed explicit artifacts cannot masquerade as legacy output."""
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

import source_artifacts


class ArtifactProvenanceTest(unittest.TestCase):
    def test_clear_allows_fresh_legacy_compiler_output(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            compiler, backend, output = [root / name for name in ('cc', 'qbe', 'program')]
            for path in (compiler, backend, output):
                path.write_bytes(b'executable')
            suffixes = ('.ssa', '.s', '.ssa.phase', '.artifacts.json',
                        '.diagnostic.o', '.diagnostic-elf')
            for suffix in suffixes:
                Path(str(output) + suffix).write_text('stale diagnostic output')
            source_artifacts.clear(output)
            self.assertTrue(output.is_file())
            self.assertTrue(all(not Path(str(output) + suffix).exists() for suffix in suffixes))
            # A real legacy compiler now produces fresh files at the reused
            # output path. No obsolete explicit marker may poison this run.
            Path(str(output) + '.ssa').write_text('new compiler SSA')
            Path(str(output) + '.s').write_text('new compiler assembly')
            with patch.object(source_artifacts, 'run') as subprocess_run:
                _, _, provenance = source_artifacts.obtain(compiler, backend, 'source.lsl', output, root)
                subprocess_run.assert_not_called()
            self.assertEqual(provenance['origin'], 'compiler-emitted alongside the production ELF')
            self.assertTrue(provenance['complete'])

    def test_failed_reproduction_is_rejected_on_every_attempt(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source_dir = root / 'compiler/pure'
            source_dir.mkdir(parents=True)
            (source_dir / 'qbe_emit_diagnostic.lsl').write_text('diagnostic source')
            (root / 'build/qbe').mkdir(parents=True)
            (root / 'build/qbe/runtime.o').write_bytes(b'runtime')
            compiler, backend, output = [root / name for name in ('compiler-tool', 'backend-tool', 'program')]
            compiler.write_bytes(b'compiler')
            backend.write_bytes(b'backend')
            output.write_bytes(b'actual production executable')
            calls = []

            def fake_run(command, cwd):
                calls.append(command)
                tool = str(command[0])
                if Path(tool) == compiler:
                    Path(command[2]).write_bytes(b'diagnostic emitter')
                elif tool.startswith(str(root / 'diagnostic-emitter-')):
                    Path(command[2]).write_text('explicit SSA')
                elif Path(tool) == backend:
                    Path(command[4]).write_text('explicit assembly')
                elif tool.endswith('/as'):
                    Path(command[3]).write_bytes(b'diagnostic object')
                elif tool.endswith('/ld'):
                    Path(command[command.index('-o') + 1]).write_bytes(b'WRONG reconstruction')
                else:
                    self.fail('unexpected command: ' + repr(command))

            record = Path(str(output) + '.artifacts.json')
            with patch.object(source_artifacts, 'run', fake_run):
                for _ in range(2):
                    with self.assertRaisesRegex(RuntimeError, 'do not reproduce the production ELF'):
                        source_artifacts.obtain(compiler, backend, 'source.lsl', output, root)
                    provenance = json.loads(record.read_text())
                    self.assertEqual(provenance['origin'], 'explicit diagnostic re-emission')
                    self.assertFalse(provenance['complete'])
                # Also reject stale output produced by the old helper, whose
                # second call could incorrectly overwrite the provenance.
                record.write_text(json.dumps({'origin': 'compiler-emitted alongside the production ELF'}))
                with self.assertRaisesRegex(RuntimeError, 'do not reproduce the production ELF'):
                    source_artifacts.obtain(compiler, backend, 'source.lsl', output, root)
            self.assertEqual(sum(Path(call[0]) == backend for call in calls), 3)
            self.assertEqual(output.read_bytes(), b'actual production executable')


if __name__ == '__main__':
    unittest.main()
