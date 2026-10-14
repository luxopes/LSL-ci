// Spustí program LSL přeložený pro wasm32-wasi v Node (WASI preview1):
// node tools/wasi_run.mjs PROGRAM.wasm [ARGUMENTY...]
// Program vidí celý souborový systém ("/") a pracovní adresář (".").
import { readFile } from 'node:fs/promises';
import { WASI } from 'node:wasi';
import { argv, env, cwd } from 'node:process';

const wasi = new WASI({
  version: 'preview1',
  args: argv.slice(2),
  env,
  preopens: { '/': '/', '.': cwd() },
  returnOnExit: true,
});
const module = await WebAssembly.compile(await readFile(argv[2]));
const instance = await WebAssembly.instantiate(module, wasi.getImportObject());
process.exitCode = wasi.start(instance);
