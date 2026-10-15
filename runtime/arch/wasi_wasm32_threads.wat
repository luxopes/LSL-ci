;; Vrstva architektury pro WebAssembly s vlákny (wasm32, WASI preview1
;; a wasi-threads, cíl wasm32-wasi-threads): obsah modulu, ke kterému
;; toolchain přidá funkce a data z LuxIR (luxir -t wasm32 -g). Každé vlákno
;; je vlastní instance modulu nad stejnou importovanou sdílenou pamětí:
;; globály ($sp, $__stack_limit, $tls) má každá instance svoje.
;; Funkce mají jednotné ABI LuxIR pro wasm: parametry i výsledek i64.
;; Adresy jsou 64bitová slova, do lineární paměti se zkracují na 32 bitů.
;; Blok vlákna runtime je v globálu $tls. Kořeny pro GC jsou na stínovém
;; zásobníku ($sp, $__stack_top z LuxIR); zastavení pro GC je kooperativní
;; v bezpečných bodech LuxIR ($__safepoint, slovo brány GC).

;; Sdílená paměť (nejvýš 4 GiB) a spuštění vlákna (wasi-threads).
(import "env" "memory" (memory 1 65536 shared))
(import "wasi" "thread-spawn" (func $wasi_thread_spawn (param i32) (result i32)))
;; WASI čte argumenty a buffery z exportované paměti.
(export "memory" (memory 0))
;; Importy WASI (preview1).
(import "wasi_snapshot_preview1" "args_sizes_get" (func $wasi_args_sizes_get (param i32 i32) (result i32)))
(import "wasi_snapshot_preview1" "args_get" (func $wasi_args_get (param i32 i32) (result i32)))
(import "wasi_snapshot_preview1" "environ_sizes_get" (func $wasi_environ_sizes_get (param i32 i32) (result i32)))
(import "wasi_snapshot_preview1" "environ_get" (func $wasi_environ_get (param i32 i32) (result i32)))
(import "wasi_snapshot_preview1" "fd_write" (func $wasi_fd_write (param i32 i32 i32 i32) (result i32)))
(import "wasi_snapshot_preview1" "fd_read" (func $wasi_fd_read (param i32 i32 i32 i32) (result i32)))
(import "wasi_snapshot_preview1" "fd_pread" (func $wasi_fd_pread (param i32 i32 i32 i64 i32) (result i32)))
(import "wasi_snapshot_preview1" "fd_seek" (func $wasi_fd_seek (param i32 i64 i32 i32) (result i32)))
(import "wasi_snapshot_preview1" "fd_close" (func $wasi_fd_close (param i32) (result i32)))
(import "wasi_snapshot_preview1" "fd_fdstat_get" (func $wasi_fd_fdstat_get (param i32 i32) (result i32)))
(import "wasi_snapshot_preview1" "fd_prestat_get" (func $wasi_fd_prestat_get (param i32 i32) (result i32)))
(import "wasi_snapshot_preview1" "fd_prestat_dir_name" (func $wasi_fd_prestat_dir_name (param i32 i32 i32) (result i32)))
(import "wasi_snapshot_preview1" "path_open" (func $wasi_path_open (param i32 i32 i32 i32 i32 i64 i64 i32 i32) (result i32)))
(import "wasi_snapshot_preview1" "path_create_directory" (func $wasi_path_create_directory (param i32 i32 i32) (result i32)))
(import "wasi_snapshot_preview1" "path_unlink_file" (func $wasi_path_unlink_file (param i32 i32 i32) (result i32)))
(import "wasi_snapshot_preview1" "path_remove_directory" (func $wasi_path_remove_directory (param i32 i32 i32) (result i32)))
(import "wasi_snapshot_preview1" "path_filestat_get" (func $wasi_path_filestat_get (param i32 i32 i32 i32 i32) (result i32)))
(import "wasi_snapshot_preview1" "clock_time_get" (func $wasi_clock_time_get (param i32 i64 i32) (result i32)))
(import "wasi_snapshot_preview1" "poll_oneoff" (func $wasi_poll_oneoff (param i32 i32 i32 i32) (result i32)))
(import "wasi_snapshot_preview1" "random_get" (func $wasi_random_get (param i32 i32) (result i32)))
(import "wasi_snapshot_preview1" "sched_yield" (func $wasi_sched_yield (result i32)))
(import "wasi_snapshot_preview1" "proc_exit" (func $wasi_proc_exit (param i32)))

;; Data vrstvy architektury (pod DataBase 4096 v LuxIR).
(global $a.lsl_state i64 (i64.const 1024))
(global $tls (mut i64) (i64.const 0))

;; Obaly WASI s ABI LuxIR: argumenty i64 zkrácené na i32, chyba WASI jako
;; nezáporné číslo (0 = úspěch).
(func $lsl_wasi_args_sizes_get (param i64 i64) (result i64)
	(i64.extend_i32_u (call $wasi_args_sizes_get (i32.wrap_i64 (local.get 0)) (i32.wrap_i64 (local.get 1)))))
(func $lsl_wasi_args_get (param i64 i64) (result i64)
	(i64.extend_i32_u (call $wasi_args_get (i32.wrap_i64 (local.get 0)) (i32.wrap_i64 (local.get 1)))))
(func $lsl_wasi_environ_sizes_get (param i64 i64) (result i64)
	(i64.extend_i32_u (call $wasi_environ_sizes_get (i32.wrap_i64 (local.get 0)) (i32.wrap_i64 (local.get 1)))))
(func $lsl_wasi_environ_get (param i64 i64) (result i64)
	(i64.extend_i32_u (call $wasi_environ_get (i32.wrap_i64 (local.get 0)) (i32.wrap_i64 (local.get 1)))))
(func $lsl_wasi_fd_write (param i64 i64 i64 i64) (result i64)
	(i64.extend_i32_u (call $wasi_fd_write (i32.wrap_i64 (local.get 0)) (i32.wrap_i64 (local.get 1)) (i32.wrap_i64 (local.get 2)) (i32.wrap_i64 (local.get 3)))))
(func $lsl_wasi_fd_read (param i64 i64 i64 i64) (result i64)
	(i64.extend_i32_u (call $wasi_fd_read (i32.wrap_i64 (local.get 0)) (i32.wrap_i64 (local.get 1)) (i32.wrap_i64 (local.get 2)) (i32.wrap_i64 (local.get 3)))))
(func $lsl_wasi_fd_pread (param i64 i64 i64 i64 i64) (result i64)
	(i64.extend_i32_u (call $wasi_fd_pread (i32.wrap_i64 (local.get 0)) (i32.wrap_i64 (local.get 1)) (i32.wrap_i64 (local.get 2)) (local.get 3) (i32.wrap_i64 (local.get 4)))))
(func $lsl_wasi_fd_seek (param i64 i64 i64 i64) (result i64)
	(i64.extend_i32_u (call $wasi_fd_seek (i32.wrap_i64 (local.get 0)) (local.get 1) (i32.wrap_i64 (local.get 2)) (i32.wrap_i64 (local.get 3)))))
(func $lsl_wasi_fd_close (param i64) (result i64)
	(i64.extend_i32_u (call $wasi_fd_close (i32.wrap_i64 (local.get 0)))))
(func $lsl_wasi_fd_fdstat_get (param i64 i64) (result i64)
	(i64.extend_i32_u (call $wasi_fd_fdstat_get (i32.wrap_i64 (local.get 0)) (i32.wrap_i64 (local.get 1)))))
(func $lsl_wasi_fd_prestat_get (param i64 i64) (result i64)
	(i64.extend_i32_u (call $wasi_fd_prestat_get (i32.wrap_i64 (local.get 0)) (i32.wrap_i64 (local.get 1)))))
(func $lsl_wasi_fd_prestat_dir_name (param i64 i64 i64) (result i64)
	(i64.extend_i32_u (call $wasi_fd_prestat_dir_name (i32.wrap_i64 (local.get 0)) (i32.wrap_i64 (local.get 1)) (i32.wrap_i64 (local.get 2)))))
;; path_open(adresář, dirflags, cesta, délka, oflags, rights, fdflags, výsledek)
(func $lsl_wasi_path_open (param i64 i64 i64 i64 i64 i64 i64 i64) (result i64)
	(i64.extend_i32_u (call $wasi_path_open (i32.wrap_i64 (local.get 0)) (i32.wrap_i64 (local.get 1)) (i32.wrap_i64 (local.get 2)) (i32.wrap_i64 (local.get 3)) (i32.wrap_i64 (local.get 4)) (local.get 5) (local.get 5) (i32.wrap_i64 (local.get 6)) (i32.wrap_i64 (local.get 7)))))
(func $lsl_wasi_path_create_directory (param i64 i64 i64) (result i64)
	(i64.extend_i32_u (call $wasi_path_create_directory (i32.wrap_i64 (local.get 0)) (i32.wrap_i64 (local.get 1)) (i32.wrap_i64 (local.get 2)))))
(func $lsl_wasi_path_unlink_file (param i64 i64 i64) (result i64)
	(i64.extend_i32_u (call $wasi_path_unlink_file (i32.wrap_i64 (local.get 0)) (i32.wrap_i64 (local.get 1)) (i32.wrap_i64 (local.get 2)))))
(func $lsl_wasi_path_remove_directory (param i64 i64 i64) (result i64)
	(i64.extend_i32_u (call $wasi_path_remove_directory (i32.wrap_i64 (local.get 0)) (i32.wrap_i64 (local.get 1)) (i32.wrap_i64 (local.get 2)))))
(func $lsl_wasi_path_filestat_get (param i64 i64 i64 i64 i64) (result i64)
	(i64.extend_i32_u (call $wasi_path_filestat_get (i32.wrap_i64 (local.get 0)) (i32.wrap_i64 (local.get 1)) (i32.wrap_i64 (local.get 2)) (i32.wrap_i64 (local.get 3)) (i32.wrap_i64 (local.get 4)))))
(func $lsl_wasi_clock_time_get (param i64 i64) (result i64)
	(i64.extend_i32_u (call $wasi_clock_time_get (i32.wrap_i64 (local.get 0)) (i64.const 1) (i32.wrap_i64 (local.get 1)))))
(func $lsl_wasi_poll_oneoff (param i64 i64 i64 i64) (result i64)
	(i64.extend_i32_u (call $wasi_poll_oneoff (i32.wrap_i64 (local.get 0)) (i32.wrap_i64 (local.get 1)) (i32.wrap_i64 (local.get 2)) (i32.wrap_i64 (local.get 3)))))
(func $lsl_wasi_random_get (param i64 i64) (result i64)
	(i64.extend_i32_u (call $wasi_random_get (i32.wrap_i64 (local.get 0)) (i32.wrap_i64 (local.get 1)))))
(func $lsl_wasi_sched_yield (result i64)
	(i64.extend_i32_u (call $wasi_sched_yield)))
(func $lsl_wasi_proc_exit (param i64) (result i64)
	(call $wasi_proc_exit (i32.wrap_i64 (local.get 0)))
	(unreachable))

;; Přetečení stínového zásobníku (LuxIR, prolog funkce): zpráva jako
;; u nativního runtime a stav 70. Text se skládá v oblasti vrstvy (3072..)
;; bez zásobníku.
(func $__stack_overflow
	(i64.store (i32.const 3088) (i64.const 0x746e7572204c534c))
	(i64.store (i32.const 3096) (i64.const 0x7361726320656d69))
	(i64.store (i32.const 3104) (i64.const 0x6b63617473203a68))
	(i64.store (i32.const 3112) (i64.const 0x6f6c667265766f20))
	(i64.store (i32.const 3120) (i64.const 0x0000000000000a77))
	(i32.store (i32.const 3072) (i32.const 3088))
	(i32.store (i32.const 3076) (i32.const 34))
	(drop (call $wasi_fd_write (i32.const 2) (i32.const 3072) (i32.const 1) (i32.const 3080)))
	(call $wasi_proc_exit (i32.const 70))
	(unreachable))

;; Paměť: velikost lineární paměti v bajtech a její zvětšení na aspoň
;; limit bajtů; 1, nebo 0 (paměť nejde zvětšit).
(func $lsl_wasm_memory_size (result i64)
	(i64.shl (i64.extend_i32_u (memory.size)) (i64.const 16)))
;; Konec dat a stínového zásobníku hlavního vlákna (od LuxIR).
(func $lsl_wasm_data_end (result i64)
	(i64.extend_i32_u (global.get $__stack_top)))
(func $lsl_wasm_memory_reserve (param i64) (result i64)
	(local $pages i32)
	(local.set $pages (i32.wrap_i64 (i64.shr_u (i64.add (local.get 0) (i64.const 65535)) (i64.const 16))))
	(if (i32.le_u (local.get $pages) (memory.size)) (then (return (i64.const 1))))
	(if (i32.eq (memory.grow (i32.sub (local.get $pages) (memory.size))) (i32.const -1))
		(then (return (i64.const 0))))
	(i64.const 1))

;; Atomické operace (sekvenčně konzistentní).
(func $lsl_arch_cas64 (param i64 i64 i64) (result i64)
	(i64.atomic.rmw.cmpxchg (i32.wrap_i64 (local.get 0)) (local.get 1) (local.get 2)))
(func $lsl_arch_xchg64 (param i64 i64) (result i64)
	(i64.atomic.rmw.xchg (i32.wrap_i64 (local.get 0)) (local.get 1)))
(func $lsl_arch_add64 (param i64 i64) (result i64)
	(i64.atomic.rmw.add (i32.wrap_i64 (local.get 0)) (local.get 1)))
(func $lsl_arch_pause (result i64) (i64.const 0))
(func $lsl_arch_sync_code (param i64 i64) (result i64) (i64.const 0))
(func $lsl_arch_sqrt (param i64) (result i64)
	(i64.reinterpret_f64 (f64.sqrt (f64.reinterpret_i64 (local.get 0)))))

;; Vlákna (os_wasi): thread-spawn s blokem vlákna jako argumentem -> tid,
;; nebo záporné číslo; čekání na 32bitové slovo (timeout v ns, -1 bez
;; omezení: 0 probuzeno, 1 jiná hodnota, 2 vypršelo) a probuzení.
(func $lsl_wasm_threads (result i64) (i64.const 1))
(func $lsl_wasm_thread_spawn (param i64) (result i64)
	(i64.extend_i32_s (call $wasi_thread_spawn (i32.wrap_i64 (local.get 0)))))
(func $lsl_wasm_wait32 (param i64 i64 i64) (result i64)
	(i64.extend_i32_u (memory.atomic.wait32 (i32.wrap_i64 (local.get 0)) (i32.wrap_i64 (local.get 1)) (local.get 2))))
(func $lsl_wasm_notify (param i64 i64) (result i64)
	(i64.extend_i32_u (memory.atomic.notify (i32.wrap_i64 (local.get 0)) (i32.wrap_i64 (local.get 1)))))
(func $lsl_wasm_sp (result i64) (i64.extend_i32_u (global.get $sp)))

;; Bezpečný bod LuxIR: slovo brány GC (stav runtime +128; halda a stav
;; začínají na 1 GiB, os_wasi HEAP_START).
(global $__safepoint_flag i64 (i64.const 1073741952))
;; Kód volaný z bezpečného bodu má své bezpečné body: ty se neopakují.
(global $in_safepoint (mut i32) (i32.const 0))
(func $__safepoint
	(if (global.get $in_safepoint) (then (return)))
	(global.set $in_safepoint (i32.const 1))
	(drop (call $lsl_wasm_safepoint))
	(global.set $in_safepoint (i32.const 0)))

;; Vstup nového vlákna (wasi-threads): blok vlákna runtime je argument.
;; Stínový zásobník (+8 vrchol, os_wasi THREAD_SHADOW_BYTES) a blok vlákna
;; se nastaví dřív, než poběží kód s rámcem.
(func (export "wasi_thread_start") (param $tid i32) (param $entry i32)
	(global.set $sp (i32.wrap_i64 (i64.load offset=8 (local.get $entry))))
	(global.set $__stack_limit (i32.sub (global.get $sp) (i32.const 4194304)))
	(global.set $tls (i64.add (i64.extend_i32_u (local.get $entry)) (i64.const 32)))
	(drop (call $lsl_thread_main (i64.extend_i32_u (local.get $entry)) (i64.load offset=24 (local.get $entry)))))

;; Ukazatel stínového zásobníku: GC prohledá [sp, vrchol). Registry nejsou,
;; hodnoty Kl ukládá LuxIR do rámců.
(func $lsl_arch_spill (param i64) (result i64)
	(i64.extend_i32_u (global.get $sp)))

;; Blok vlákna runtime této instance (vlákna).
(func $lsl_arch_thread_pointer (result i64)
	(global.get $tls))
(func $lsl_arch_set_thread_pointer (param i64) (result i64)
	(global.set $tls (local.get 0))
	(i64.const 0))
(func $lsl_arch_tls_load (param i64) (result i64)
	(i64.load (i32.wrap_i64 (i64.add (global.get $tls) (local.get 0)))))
(func $lsl_arch_tls_store (param i64 i64) (result i64)
	(i64.store (i32.wrap_i64 (i64.add (global.get $tls) (local.get 0))) (local.get 1))
	(i64.const 0))

;; Chybový stav vlákna (blok vlákna +0 chyba, +8 příznak).
(func $qbe_error_flag (result i64)
	(i64.load offset=8 (i32.wrap_i64 (global.get $tls))))
(func $qbe_error_set (param i64) (result i64)
	(i64.store (i32.wrap_i64 (global.get $tls)) (local.get 0))
	(i64.store offset=8 (i32.wrap_i64 (global.get $tls)) (i64.const 1))
	(i64.const 0))
(func $qbe_error_catch (result i64)
	(i64.store offset=8 (i32.wrap_i64 (global.get $tls)) (i64.const 0))
	(i64.const 0))
(func $qbe_error_clear (result i64)
	(i64.store (i32.wrap_i64 (global.get $tls)) (i64.const 0))
	(i64.store offset=8 (i32.wrap_i64 (global.get $tls)) (i64.const 0))
	(i64.const 0))

;; Vstup programu (jen hlavní instance): paměť do začátku haldy, data
;; LuxIR, pak lsl_runtime_start s vrcholem stínového zásobníku; nevrací se
;; (proc_exit).
(func (export "_start")
	;; Až po první stránku haldy (1 GiB): bezpečné body čtou bránu GC
	;; (stav runtime) od prvního volání.
	(if (i32.gt_u (i32.const 16385) (memory.size))
		(then (if (i32.eq (memory.grow (i32.sub (i32.const 16385) (memory.size))) (i32.const -1))
			(then (unreachable)))))
	(call $__wasm_init_memory)
	(drop (call $lsl_runtime_start (i64.extend_i32_u (global.get $__stack_top))))
	(unreachable))
