"""Explicit diagnostic artifacts, checked against the production executable.

The production image API intentionally deletes its private intermediate files.
For diagnostics only, re-emit using the matching checkout and reject artifacts
unless rebuilding them yields the exact production ELF bytes.
"""
import hashlib
import json
import os
from pathlib import Path
import signal
import subprocess

from verify_public_int import digest, memory_limit

ROOT = Path(__file__).resolve().parents[2]


def clear(output):
    """Prevent a previous compiler's intermediate files from being reused."""
    for suffix in ('.ssa', '.s', '.ssa.phase', '.artifacts.json',
                   '.diagnostic.o', '.diagnostic-elf'):
        Path(str(output) + suffix).unlink(missing_ok=True)


def run(command, cwd):
    process = subprocess.Popen([str(x) for x in command], cwd=cwd,
                               stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                               start_new_session=True, preexec_fn=memory_limit)
    try:
        stdout, stderr = process.communicate(timeout=60)
    except subprocess.TimeoutExpired:
        os.killpg(process.pid, signal.SIGKILL)
        process.communicate()
        raise
    if process.returncode:
        raise RuntimeError(f'{command}: exit {process.returncode}\n'
                           + stdout.decode(errors='replace') + stderr.decode(errors='replace'))


def obtain(compiler, backend, source, output, cwd=ROOT):
    compiler, backend, output, cwd = (Path(p).resolve() for p in (compiler, backend, output, cwd))
    source = Path(source)
    ssa, assembly = Path(str(output) + '.ssa'), Path(str(output) + '.s')
    provenance = {'compiler_sha256': digest(compiler), 'backend_sha256': digest(backend),
                  'production_elf_sha256': digest(output)}
    record = Path(str(output) + '.artifacts.json')
    # A failed explicit reproduction may already have written .ssa/.s. Those
    # files were not emitted by the production compiler and must never become
    # legacy artifacts merely because obtain() is called again. Keep an intent
    # marker before invoking any diagnostic subprocess; existing reconstruction
    # objects also identify outputs made by older versions of this helper.
    previous = {}
    if record.is_file():
        try:
            previous = json.loads(record.read_text())
        except (OSError, ValueError):
            pass
    explicit = ((record.exists() and previous.get('origin') !=
                 'compiler-emitted alongside the production ELF') or
                Path(str(output) + '.diagnostic.o').exists() or
                Path(str(output) + '.diagnostic-elf').exists())
    if ssa.is_file() and assembly.is_file() and not explicit:
        # Older native compilers emitted both files during the actual compile.
        provenance['origin'] = 'compiler-emitted alongside the production ELF'
    else:
        provenance.update(origin='explicit diagnostic re-emission', complete=False)
        record.write_text(json.dumps(provenance, indent=2) + '\n')
        diagnostic_source = cwd / 'compiler/pure/qbe_emit_diagnostic.lsl'
        if not diagnostic_source.is_file():
            raise RuntimeError('matching diagnostic emitter source is required: ' + str(diagnostic_source))
        sources = {str(p.relative_to(cwd)): digest(p)
                   for p in sorted((cwd / 'compiler/pure').glob('*.lsl'))}
        key = hashlib.sha256((digest(compiler) + digest(backend)
                              + json.dumps(sources, sort_keys=True)).encode()).hexdigest()
        emitter = output.parent / ('diagnostic-emitter-' + key[:16])
        if not emitter.is_file():
            # The internal-ABI marker authorizes this compiler tool explicitly;
            # it also permits older bootstrap compilers without option parsing.
            run([compiler, diagnostic_source, emitter, backend], cwd)
        provenance.update(origin='explicit diagnostic re-emission', source_sha256=sources,
                          diagnostic_emitter_sha256=digest(emitter))
        run([emitter, source, ssa], cwd)
        run([backend, '-t', 'amd64_sysv', '-o', assembly, ssa], cwd)
        with assembly.open('a') as file:
            file.write('\n.file "lsl-qbe"\n')
        obj, reconstructed = Path(str(output) + '.diagnostic.o'), Path(str(output) + '.diagnostic-elf')
        runtime = cwd / 'compiler/qbe/runtime.o'
        if not runtime.is_file():
            runtime = cwd / 'build/qbe/runtime.o'
        assembler = '/usr/bin/as' if Path('/usr/bin/as').is_file() else '/bin/as'
        linker = '/usr/bin/ld' if Path('/usr/bin/ld').is_file() else '/bin/ld'
        run([assembler, '--64', '-o', obj, assembly], cwd)
        run([linker, '-nostdlib', '-static', '-pie', '--no-dynamic-linker', '-z', 'text',
             '-z', 'noexecstack', '--build-id=none', '-s', '-o', reconstructed, obj, runtime], cwd)
        provenance['runtime_sha256'] = digest(runtime)
        provenance['reconstructed_elf_sha256'] = digest(reconstructed)
        provenance['matches_production_elf'] = reconstructed.read_bytes() == output.read_bytes()
        if not provenance['matches_production_elf']:
            raise RuntimeError('diagnostic artifacts do not reproduce the production ELF; '
                               'use the compiler matching this source checkout')
    provenance.update(ssa_sha256=digest(ssa), assembly_sha256=digest(assembly))
    provenance['complete'] = True
    record.write_text(json.dumps(provenance, indent=2) + '\n')
    return ssa, assembly, provenance
