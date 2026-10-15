// Spustí program LSL přeložený pro WebAssembly v Node (WASI preview1):
// node tools/wasi_run.mjs PROGRAM.wasm [ARGUMENTY...]
// Program vidí celý souborový systém ("/") a pracovní adresář (".").
//
// Modul s vlákny (wasm32-wasi-threads: importuje sdílenou paměť a
// wasi.thread-spawn) Node WASI sám nespustí. Každé vlákno wasm pak běží ve
// vlastním Workeru nad stejnou sdílenou pamětí a volání WASI obsluhuje
// jediná instance WASI v hlavním vlákně Node přes sdílené schránky, takže
// deskriptory souborů jsou společné všem vláknům. Spánek (poll_oneoff
// s hodinami) a sched_yield řeší Worker sám.
import { readFile } from 'node:fs/promises';
import { WASI } from 'node:wasi';
import { Worker, isMainThread, parentPort, workerData } from 'node:worker_threads';
import { argv, env, cwd } from 'node:process';

const SLOT = 16;          // slova BigInt64 na schránku vlákna
const SLOTS = 1024;
const STATE = 0, CALL = 1, ARGS = 2, RESULT = 12;
// Funkce WASI ve schránce (pořadí = číslo volání) a pozice parametrů i64.
const CALLS = {
  args_sizes_get: [], args_get: [], environ_sizes_get: [], environ_get: [],
  fd_write: [], fd_read: [], fd_pread: [3], fd_pwrite: [3], fd_seek: [1], fd_close: [],
  fd_fdstat_get: [], fd_filestat_get: [], fd_prestat_get: [], fd_prestat_dir_name: [],
  fd_readdir: [3], path_open: [5, 6], path_create_directory: [], path_unlink_file: [],
  path_remove_directory: [], path_filestat_get: [], path_rename: [], clock_time_get: [1],
  clock_res_get: [], poll_oneoff: [], random_get: [], proc_exit: [], fd_sync: [],
  fd_tell: [], fd_advise: [1, 2], fd_allocate: [1, 2], fd_datasync: [], fd_fdstat_set_flags: [],
  fd_filestat_set_size: [1], path_readlink: [], path_symlink: [], path_link: [],
};
const NAMES = Object.keys(CALLS);
const SPAWN = NAMES.length;

function wasiOptions(args) {
  return { version: 'preview1', args, env, preopens: { '/': '/', '.': cwd() }, returnOnExit: true };
}

// Minimální modul, přes který WASI v hlavním vlákně vidí sdílenou paměť:
// import env.memory (sdílená, 1 až 65536 stránek), export memory
// a prázdné _initialize.
const MEMORY_MODULE = new Uint8Array([
  0x00, 0x61, 0x73, 0x6d, 0x01, 0x00, 0x00, 0x00,
  0x01, 0x04, 0x01, 0x60, 0x00, 0x00,
  0x02, 0x12, 0x01, 0x03, 0x65, 0x6e, 0x76, 0x06, 0x6d, 0x65, 0x6d, 0x6f, 0x72, 0x79,
  0x02, 0x03, 0x01, 0x80, 0x80, 0x04,
  0x03, 0x02, 0x01, 0x00,
  0x07, 0x18, 0x02, 0x06, 0x6d, 0x65, 0x6d, 0x6f, 0x72, 0x79, 0x02, 0x00,
  0x0b, 0x5f, 0x69, 0x6e, 0x69, 0x74, 0x69, 0x61, 0x6c, 0x69, 0x7a, 0x65, 0x00, 0x00,
  0x0a, 0x04, 0x01, 0x02, 0x00, 0x0b,
]);

function threaded(module) {
  return WebAssembly.Module.imports(module).some((i) => i.module === 'wasi' && i.name === 'thread-spawn');
}

// Bez vláken: WASI přímo, ve Workeru s velkým nativním zásobníkem (hluboká
// rekurze jako v nativním programu s 8 MiB zásobníku).
async function runSingle(module, args) {
  const worker = new Worker(new URL(import.meta.url), {
    workerData: { single: true, module, args },
    resourceLimits: { stackSizeMb: 256 },
  });
  worker.on('message', (code) => { process.exitCode = code; });
  worker.on('error', (error) => {
    process.stderr.write(`wasm: ${error && error.message ? error.message : error}\n`);
    process.exitCode = 134;
  });
}

async function singleMain() {
  const { module, args } = workerData;
  const wasi = new WASI(wasiOptions(args));
  const instance = await WebAssembly.instantiate(module, wasi.getImportObject());
  parentPort.postMessage(wasi.start(instance));
}

async function runThreaded(module, args) {
  const memory = new WebAssembly.Memory({ initial: 1, maximum: 65536, shared: true });
  const control = new SharedArrayBuffer(SLOTS * SLOT * 8 + 8);
  const slots = new BigInt64Array(control, 0, SLOTS * SLOT);
  const door = new Int32Array(control, SLOTS * SLOT * 8, 2);
  const wasi = new WASI(wasiOptions(args));
  const shim = await WebAssembly.instantiate(new WebAssembly.Module(MEMORY_MODULE), { env: { memory } });
  wasi.initialize(shim);
  let nextTid = 1;
  let exiting = false;

  function finish(code) {
    if (exiting) return;
    exiting = true;
    process.exit(code);
  }

  function start(tid, arg) {
    if (tid >= SLOTS) return -1;
    const worker = new Worker(new URL(import.meta.url), {
      workerData: { module, memory, control, tid, arg },
      resourceLimits: { stackSizeMb: 256 },
    });
    worker.on('error', (error) => {
      process.stderr.write(`wasm thread ${tid}: ${error && error.message ? error.message : error}\n`);
      finish(134);
    });
    if (tid === 0) worker.on('exit', () => finish(0));
    return tid;
  }

  function serve(index) {
    const base = index * SLOT;
    const call = Number(slots[base + CALL]);
    const name = NAMES[call];
    if (name === 'proc_exit') {
      finish(Number(BigInt.asIntN(32, slots[base + ARGS])));
      return;
    }
    let result;
    if (call === SPAWN) {
      // thread-spawn: argument je blok vlákna; tid hned, Worker se rozběhne.
      result = start(nextTid++, Number(slots[base + ARGS]));
    } else {
      const wide = CALLS[name];
      const values = [];
      for (let k = 0; k < wasi.wasiImport[name].length; k++) {
        const raw = slots[base + ARGS + k];
        values.push(wide.includes(k) ? raw : Number(BigInt.asIntN(32, raw)));
      }
      result = wasi.wasiImport[name](...values);
    }
    slots[base + RESULT] = BigInt(result);
    Atomics.store(slots, base + STATE, 2n);
    Atomics.notify(slots, base + STATE);
  }

  start(0, 0);
  while (!exiting) {
    const seen = Atomics.load(door, 0);
    for (let index = 0; index < nextTid && !exiting; index++)
      if (Atomics.load(slots, index * SLOT + STATE) === 1n) serve(index);
    if (exiting) break;
    await Atomics.waitAsync(door, 0, seen).value;
  }
}

// Worker: jedno vlákno wasm. Volání WASI jdou přes schránku vlákna.
async function threadMain() {
  const { module, memory, control, tid, arg } = workerData;
  const slots = new BigInt64Array(control, 0, SLOTS * SLOT);
  const door = new Int32Array(control, SLOTS * SLOT * 8, 2);
  const base = tid * SLOT;
  const pause = new Int32Array(new SharedArrayBuffer(4));
  function request(call, values) {
    for (let k = 0; k < values.length; k++)
      slots[base + ARGS + k] = BigInt(values[k]);
    slots[base + CALL] = BigInt(call);
    Atomics.store(slots, base + STATE, 1n);
    Atomics.add(door, 0, 1);
    Atomics.notify(door, 0);
    while (Atomics.load(slots, base + STATE) === 1n)
      Atomics.wait(slots, base + STATE, 1n);
    const result = Number(BigInt.asIntN(32, slots[base + RESULT]));
    Atomics.store(slots, base + STATE, 0n);
    return result;
  }
  const preview = {};
  NAMES.forEach((name, call) => {
    preview[name] = (...values) => request(call, values);
  });
  preview.sched_yield = () => 0;
  // Spánek: jediný odběr hodin (os_wasi) vyřídí čekání ve Workeru.
  preview.poll_oneoff = (input, output, count, done) => {
    const data = new DataView(memory.buffer);
    if (count === 1 && data.getUint8(input + 8) === 0) {
      let timeout = data.getBigUint64(input + 24, true);
      if (data.getUint16(input + 40, true) & 1) {
        const now = process.hrtime.bigint();
        timeout = timeout > now ? timeout - now : 0n;
      }
      const milliseconds = Number(timeout / 1000000n);
      if (milliseconds > 0) Atomics.wait(pause, 0, 0, milliseconds);
      data.setBigUint64(output, data.getBigUint64(input, true), true);
      data.setUint16(output + 8, 0, true);
      data.setUint8(output + 10, 0);
      data.setUint32(done, 1, true);
      return 0;
    }
    return request(NAMES.indexOf('poll_oneoff'), [input, output, count, done]);
  };
  const imports = {
    env: { memory },
    wasi: { 'thread-spawn': (value) => request(SPAWN, [value]) },
    wasi_snapshot_preview1: preview,
  };
  const instance = await WebAssembly.instantiate(module, imports);
  if (tid === 0) {
    instance.exports._start();
    request(NAMES.indexOf('proc_exit'), [0]);
  } else {
    instance.exports.wasi_thread_start(tid, arg);
  }
}

if (isMainThread) {
  const module = await WebAssembly.compile(await readFile(argv[2]));
  const args = argv.slice(2);
  if (threaded(module)) await runThreaded(module, args);
  else await runSingle(module, args);
} else if (workerData.single) {
  await singleMain();
} else {
  await threadMain();
}
