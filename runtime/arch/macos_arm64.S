// Vrstva architektury pro macOS arm64 (Apple AAPCS64: x18 je vyhrazený,
// argumenty s proměnným počtem jdou přes zásobník). Systémová volání nejdou
// přímo: runtime volá libSystem (os_macos.lsl). Funkce s proměnným počtem
// argumentů (open, openat, fcntl, ioctl) volá přes zdejší můstky.
//
// Blok vlákna runtime je v TSD slotu z pthread_key_create: TPIDRRO_EL0
// ukazuje na pole TSD vlákna (spodní 3 bity se maskují), slot uloží
// os_macos do lsl_tls_slot.
	.text

	.globl _lsl_arch_cas64
	.p2align 4
_lsl_arch_cas64:
1:	ldaxr x3, [x0]
	cmp x3, x1
	b.ne 2f
	stlxr w4, x2, [x0]
	cbnz w4, 1b
	dmb ish
	mov x0, x3
	ret
2:	clrex
	dmb ish
	mov x0, x3
	ret

	.globl _lsl_arch_xchg64
	.p2align 4
_lsl_arch_xchg64:
1:	ldaxr x2, [x0]
	stlxr w3, x1, [x0]
	cbnz w3, 1b
	dmb ish
	mov x0, x2
	ret

	.globl _lsl_arch_add64
	.p2align 4
_lsl_arch_add64:
1:	ldaxr x2, [x0]
	add x3, x2, x1
	stlxr w4, x3, [x0]
	cbnz w4, 1b
	dmb ish
	mov x0, x2
	ret

	.globl _lsl_arch_pause
	.p2align 4
_lsl_arch_pause:
	yield
	ret

// Nativní kód se na macOS nenačítá (ffi_macos), synchronizace není potřeba.
	.globl _lsl_arch_sync_code
	.p2align 4
_lsl_arch_sync_code:
	mov x0, #0
	ret

	.globl _lsl_arch_sqrt
	.p2align 4
_lsl_arch_sqrt:
	fmov d0, x0
	fsqrt d0, d0
	fmov x0, d0
	ret

// lsl_arch_spill(buffer 96 B) -> ukazatel zásobníku volajícího; uloží
// callee-saved registry x19-x29 pro konzervativní GC.
	.globl _lsl_arch_spill
	.p2align 4
_lsl_arch_spill:
	stp x19, x20, [x0]
	stp x21, x22, [x0, #16]
	stp x23, x24, [x0, #32]
	stp x25, x26, [x0, #48]
	stp x27, x28, [x0, #64]
	str x29, [x0, #80]
	mov x0, sp
	ret

// Blok vlákna runtime do x10 (mění x9, x10).
.macro THREAD_BLOCK
	adrp x9, _lsl_tls_slot@PAGE
	ldr x9, [x9, _lsl_tls_slot@PAGEOFF]
	mrs x10, TPIDRRO_EL0
	and x10, x10, #0xfffffffffffffff8
	ldr x10, [x10, x9, lsl #3]
.endm

	.globl _lsl_arch_tls_load
	.p2align 4
_lsl_arch_tls_load:
	THREAD_BLOCK
	ldr x0, [x10, x0]
	ret

	.globl _lsl_arch_tls_store
	.p2align 4
_lsl_arch_tls_store:
	THREAD_BLOCK
	str x1, [x10, x0]
	mov x0, #0
	ret

// Blok vlákna runtime pro volající vlákno (jako pthread_setspecific); 0.
	.globl _lsl_arch_set_thread_pointer
	.p2align 4
_lsl_arch_set_thread_pointer:
	adrp x9, _lsl_tls_slot@PAGE
	ldr x9, [x9, _lsl_tls_slot@PAGEOFF]
	mrs x10, TPIDRRO_EL0
	and x10, x10, #0xfffffffffffffff8
	str x0, [x10, x9, lsl #3]
	mov x0, #0
	ret

	.globl _qbe_error_flag
	.p2align 4
_qbe_error_flag:
	THREAD_BLOCK
	ldr x0, [x10, #8]
	ret

	.globl _qbe_error_set
	.p2align 4
_qbe_error_set:
	THREAD_BLOCK
	mov x9, #1
	stp x0, x9, [x10]
	mov x0, #0
	ret

	.globl _qbe_error_catch
	.p2align 4
_qbe_error_catch:
	THREAD_BLOCK
	str xzr, [x10, #8]
	mov x0, #0
	ret

	.globl _qbe_error_clear
	.p2align 4
_qbe_error_clear:
	THREAD_BLOCK
	stp xzr, xzr, [x10]
	mov x0, #0
	ret

// Vstup programu (LC_MAIN): dyld volá main(argc, argv, envp). Argumenty si
// uloží os_macos.process_arguments z lsl_mac_args; lsl_runtime_start
// dostane vrchol zásobníku hlavního vlákna a nevrací se.
	.globl _main
	.p2align 4
_main:
	stp x29, x30, [sp, #-16]!
	mov x29, sp
	adrp x9, _lsl_mac_args@PAGE
	add x9, x9, _lsl_mac_args@PAGEOFF
	stp x0, x1, [x9]
	str x2, [x9, #16]
	add x0, sp, #16
	bl _lsl_runtime_start
	brk #1

// Vstup vlákna z pthread_create (x0 = položka tabulky vláken):
// lsl_thread_begin(položka, vrchol zásobníku); vlákno končí pthread_exit.
	.globl _lsl_arch_thread_start
	.p2align 4
_lsl_arch_thread_start:
	stp x29, x30, [sp, #-32]!
	mov x29, sp
	str x0, [sp, #16]
	bl _pthread_self
	bl _pthread_get_stackaddr_np
	mov x1, x0
	ldr x0, [sp, #16]
	bl _lsl_thread_begin
	brk #1

// Můstky k funkcím s proměnným počtem argumentů: na Apple arm64 leží
// variabilní argument na zásobníku.
// lsl_arch_open(cesta, příznaky, mód)
	.globl _lsl_arch_open
	.p2align 4
_lsl_arch_open:
	stp x29, x30, [sp, #-16]!
	mov x29, sp
	sub sp, sp, #16
	str x2, [sp]
	bl _open
	add sp, sp, #16
	ldp x29, x30, [sp], #16
	ret

// lsl_arch_openat(adresář, cesta, příznaky, mód)
	.globl _lsl_arch_openat
	.p2align 4
_lsl_arch_openat:
	stp x29, x30, [sp, #-16]!
	mov x29, sp
	sub sp, sp, #16
	str x3, [sp]
	bl _openat
	add sp, sp, #16
	ldp x29, x30, [sp], #16
	ret

// lsl_arch_fcntl(fd, příkaz, argument)
	.globl _lsl_arch_fcntl
	.p2align 4
_lsl_arch_fcntl:
	stp x29, x30, [sp, #-16]!
	mov x29, sp
	sub sp, sp, #16
	str x2, [sp]
	bl _fcntl
	add sp, sp, #16
	ldp x29, x30, [sp], #16
	ret

// lsl_arch_ioctl(fd, požadavek, argument)
	.globl _lsl_arch_ioctl
	.p2align 4
_lsl_arch_ioctl:
	stp x29, x30, [sp, #-16]!
	mov x29, sp
	sub sp, sp, #16
	str x2, [sp]
	bl _ioctl
	add sp, sp, #16
	ldp x29, x30, [sp], #16
	ret

	.globl _lsl_arch_fstat
	.p2align 4
_lsl_arch_fstat:
	b _fstat

// Adresa stavu runtime, TSD slot bloku vlákna a argumenty z main.
	.zerofill __DATA,__bss,_lsl_state,8,3
	.globl _lsl_state
	.zerofill __DATA,__bss,_lsl_tls_slot,8,3
	.globl _lsl_tls_slot
	.zerofill __DATA,__bss,_lsl_mac_args,24,3
	.globl _lsl_mac_args
// Rezervace haldy (+0 začátek, +8 konec) a pthread_t vláken tabulky.
	.zerofill __DATA,__bss,_lsl_mac_heap,16,3
	.globl _lsl_mac_heap
	.zerofill __DATA,__bss,_lsl_mac_threads,1024,3
	.globl _lsl_mac_threads
