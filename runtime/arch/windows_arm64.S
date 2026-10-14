// Vrstva architektury pro Windows arm64 (AAPCS64, x18 = TEB vlákna).
// Instrukce, které LuxIR nemá, a přístup k bloku vlákna runtime. Všechno
// ostatní je v LSL (os_windows.lsl).
//
// Blok vlákna runtime je v TLS slotu z TlsAlloc: TEB+0x1480 + 8 * slot
// (TlsSlots, sloty 0..63). Slot uloží os_windows.process_arguments do
// lsl_tls_slot.
	.text

	.globl lsl_arch_cas64
	.p2align 4
lsl_arch_cas64:
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

	.globl lsl_arch_xchg64
	.p2align 4
lsl_arch_xchg64:
1:	ldaxr x2, [x0]
	stlxr w3, x1, [x0]
	cbnz w3, 1b
	dmb ish
	mov x0, x2
	ret

	.globl lsl_arch_add64
	.p2align 4
lsl_arch_add64:
1:	ldaxr x2, [x0]
	add x3, x2, x1
	stlxr w4, x3, [x0]
	cbnz w4, 1b
	dmb ish
	mov x0, x2
	ret

	.globl lsl_arch_pause
	.p2align 4
lsl_arch_pause:
	yield
	ret

// Nativní kód se na Windows nenačítá (ffi_windows).
	.globl lsl_arch_sync_code
	.p2align 4
lsl_arch_sync_code:
	mov x0, #0
	ret

	.globl lsl_arch_sqrt
	.p2align 4
lsl_arch_sqrt:
	fmov d0, x0
	fsqrt d0, d0
	fmov x0, d0
	ret

// lsl_arch_spill(buffer 96 B) -> ukazatel zásobníku volajícího; uloží
// callee-saved registry x19-x29 pro konzervativní GC.
	.globl lsl_arch_spill
	.p2align 4
lsl_arch_spill:
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
	adrp x9, lsl_tls_slot
	ldr x9, [x9, :lo12:lsl_tls_slot]
	add x10, x18, #0x1, lsl #12
	add x10, x10, #0x480
	ldr x10, [x10, x9, lsl #3]
.endm

	.globl lsl_arch_tls_load
	.p2align 4
lsl_arch_tls_load:
	THREAD_BLOCK
	ldr x0, [x10, x0]
	ret

	.globl lsl_arch_tls_store
	.p2align 4
lsl_arch_tls_store:
	THREAD_BLOCK
	str x1, [x10, x0]
	mov x0, #0
	ret

// Blok vlákna runtime pro volající vlákno (jako TlsSetValue); 0.
	.globl lsl_arch_set_thread_pointer
	.p2align 4
lsl_arch_set_thread_pointer:
	adrp x9, lsl_tls_slot
	ldr x9, [x9, :lo12:lsl_tls_slot]
	add x10, x18, #0x1, lsl #12
	add x10, x10, #0x480
	str x0, [x10, x9, lsl #3]
	mov x0, #0
	ret

	.globl qbe_error_flag
	.p2align 4
qbe_error_flag:
	THREAD_BLOCK
	ldr x0, [x10, #8]
	ret

	.globl qbe_error_set
	.p2align 4
qbe_error_set:
	THREAD_BLOCK
	mov x9, #1
	stp x0, x9, [x10]
	mov x0, #0
	ret

	.globl qbe_error_catch
	.p2align 4
qbe_error_catch:
	THREAD_BLOCK
	str xzr, [x10, #8]
	mov x0, #0
	ret

	.globl qbe_error_clear
	.p2align 4
qbe_error_clear:
	THREAD_BLOCK
	stp xzr, xzr, [x10]
	mov x0, #0
	ret

// lsl_arch_call_native(kód, argumenty) -> výsledek: nativní funkce (ELF,
// AAPCS64) se šesti slovy z argumenty v x0-x5. Kód z Linuxu smí měnit x18,
// na Windows ukazatel na TEB: uloží se a obnoví.
	.globl lsl_arch_call_native
	.p2align 4
lsl_arch_call_native:
	stp x29, x30, [sp, #-32]!
	mov x29, sp
	str x18, [sp, #16]
	mov x16, x0
	mov x17, x1
	ldp x0, x1, [x17]
	ldp x2, x3, [x17, #16]
	ldp x4, x5, [x17, #32]
	blr x16
	ldr x18, [sp, #16]
	ldp x29, x30, [sp], #32
	ret

// Vstup programu (PE AddressOfEntryPoint): Windows nepředává argc ani argv,
// os_windows je sestaví z GetCommandLineW. lsl_runtime_start dostane vrchol
// zásobníku hlavního vlákna (TEB+8, StackBase) a nevrací se.
	.globl _start
	.p2align 4
_start:
	stp x29, x30, [sp, #-16]!
	mov x29, sp
	ldr x0, [x18, #8]
	bl lsl_runtime_start
	brk #1

// Vstup vlákna z CreateThread (x0 = položka tabulky vláken):
// lsl_thread_begin(položka, vrchol zásobníku); vlákno končí ExitThread.
	.globl lsl_arch_thread_start
	.p2align 4
lsl_arch_thread_start:
	stp x29, x30, [sp, #-16]!
	mov x29, sp
	ldr x1, [x18, #8]
	bl lsl_thread_begin
	brk #1

	.bss
// Adresa stavu runtime (blok na začátku haldy).
	.p2align 3
	.globl lsl_state
lsl_state:
	.zero 8
// TLS slot bloku vlákna runtime.
	.globl lsl_tls_slot
lsl_tls_slot:
	.zero 8
// Vlákna pro GC: na položku tabulky vláken 256 B (+0 HANDLE vlákna,
// +8 31 registrů x0-x30 zastaveného vlákna z CONTEXT).
	.globl lsl_win_threads
lsl_win_threads:
	.zero 32768
// CONTEXT pro GetThreadContext (912 B, zarovnaný na 16).
	.p2align 4
	.globl lsl_win_context
lsl_win_context:
	.zero 1024
// Vstup z konzole převedený na UTF-8, který se ještě nepřečetl (+0 počet).
	.globl lsl_win_console
lsl_win_console:
	.zero 4104
