The public `lsl` command compiles through `pipeline.compile_mode`, which emits
LuxIR and runs the separate LuxIR backend (https://git.lux-ai.cz/LuxAI/LuxIR). The same path serves source execution, `lsl compile`, the
trusted generated config evaluator, and sandbox compilation. Linux x86_64 is the
implemented runtime target.

The native `lslc` driver accepts:

```
lslc [--safe | --unsafe | --sandbox] [--target NAME] SOURCE OUTPUT [BACKEND]
```

Ordinary source defaults to safe mode. Private intrinsics require a lexical
`unsafe:` block or explicit `--unsafe`. Sandbox mode rejects unsafe blocks and
private operations. Compiler sources with the existing first-line
`# lsl: internal-abi` marker retain the trusted self-host interface; explicitly
requesting safe or sandbox mode rejects that internal ABI. The public `lsl`
command does not grant trust to a source marker.

The optional positional backend path supports bootstrap and isolated tests.
Without it, the toolchain selects the backend in this order:

1. `LSL_BACKEND`: an absolute path to a LuxIR-compatible executable;
2. `luxir` beside the installed compiler;
3. the development build `build/luxir/luxir` in this repository.

The backend receives `-t TARGET -o OUTPUT.s INPUT.lir`. The installation also
supplies `luxir` and the native runtime object. System assembler and linker
tools remain required.

`tools/qbe/verify_cli_pipeline.py` checks the real compiler and public CLI:

```
python3 tools/qbe/verify_cli_pipeline.py \
  --compiler /absolute/path/to/new-lslc \
  --cli /absolute/path/to/new-lsl \
  --build-directory build/qbe-cli-contract
```

The checks include default backend resolution, safe/unsafe/sandbox boundaries,
compiler-source trust compatibility, public compile and run, script arguments,
entry-source identity, and config evaluation. Maintained compiler-internal test
fixtures that intentionally call private intrinsics use `lslc --unsafe`.

To start from a clean checkout, the initial bootstrap uses the LuxIR C
reference build once, then rebuilds LuxIR in LSL and the frontend through it:

```
python3 tools/qbe/bootstrap.py --bootstrap /absolute/path/to/existing/lslc \
  --luxir /absolute/path/to/luxir-checkout
```

It produces `build/qbe/stage4` and `build/luxir/luxir`. Building LuxIR from
`lsl/luxir.lsl` requires the module trust rule in `compiler/pure/linker.lsl`:
inside a trusted graph, modules whose first line is `# lsl: internal-abi`
keep the internal ABI even outside `compiler/pure/`.

The full runner checks the LuxIR backend fixed point when `LUXIR_SOURCE`
points to `lsl/luxir.lsl` of the LuxIR checkout:

```
LUXIR_SOURCE=/absolute/path/to/luxir/lsl/luxir.lsl tests/lsl-test qbe
```
