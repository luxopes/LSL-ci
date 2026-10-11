
Native startup registry and subprocess completion controls (Linux x86_64):

- `native-startup-tables-linux-x86_64.json`: unchanged table-growth and automatic GC plus arbitrary-name startup test with a preceding function declaration, all3 candidate/installed0.8.9 PASS. Entry IR contains exactly one bootstrap call before literal initialization. Production `c2cad48` changes only startup ordering in `emit_function`.
- `native-process-capture-linux-x86_64.json`: all7 independent candidate/installed0.8.9 controls PASS, including100000-character input, callback exceptions, process status/stderr, clean/input-stream variants, existing sequence/slice controls, and Unicode contiguous String slicing. Every provider builds its own executable helpers.
- `native-process-capture-before-slice-linux-x86_64.json`: retained25s large-input timeout after the callback/input register order was corrected. The client first slices100000 characters through the general strided helper, rescanning UTF-8 for each index. The same client without that slice finishes in0.006s with131072-character input. Production `0884111` uses the existing native contiguous String slice for known String/no-explicit-step and preserves the general helper for strided slices. An earlier diagnostic had reversed callback/input operands; its overwritten raw report is not retained, and it is not used as evidence for the final result.

Reproduce with the native seed frontend/backend and matching tracked runtime:

```sh
FRONTEND compiler/pure/lslc_qbe.lsl BUILD/compiler BACKEND
python3 tools/qbe/verify_startup_tables.py --compiler BUILD/compiler --backend BACKEND --build-directory BUILD/startup
python3 tools/qbe/verify_process_capture.py --frontend FRONTEND --backend BACKEND --build-directory BUILD/process
```

The process runner starts each command in a new session and kills the entire process group on timeout. The source is frozen after `0884111`; later aggregate/self-host and performance validation belongs to the integration coordinator.
