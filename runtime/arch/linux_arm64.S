// Vrstva architektury pro Linux arm64 (AAPCS64): jediné místo runtime
// s instrukcemi tohoto CPU. Stejné funkce jako linux_x86_64.S.
	.text

// lsl_arch_syscall6(číslo, a1..a6) -> výsledek jádra
	.globl lsl_arch_syscall6
	.p2align 4
lsl_arch_syscall6:
	mov x8, x0
	mov x0, x1
	mov x1, x2
	mov x2, x3
	mov x3, x4
	mov x4, x5
	mov x5, x6
	svc #0
	ret

	.globl lsl_arch_syscall3
	.p2align 4
lsl_arch_syscall3:
	mov x8, x0
	mov x0, x1
	mov x1, x2
	mov x2, x3
	svc #0
	ret

// Atomické operace (sekvenčně konzistentní: ldaxr/stlxr + dmb).
// lsl_arch_cas64(adresa, očekávaná, nová) -> původní hodnota
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

// lsl_arch_sync_code(adresa, délka): zapsaný kód do bodu sjednocení
// (dc cvau), zneplatnit instrukční cache (ic ivau), velikosti řádků z CTR_EL0.
	.globl lsl_arch_sync_code
	.p2align 4
lsl_arch_sync_code:
	add x1, x0, x1
	mrs x2, ctr_el0
	ubfx x3, x2, #16, #4
	mov x4, #4
	lsl x3, x4, x3
	sub x5, x3, #1
	bic x6, x0, x5
1:	dc cvau, x6
	add x6, x6, x3
	cmp x6, x1
	b.lo 1b
	dsb ish
	and x3, x2, #15
	lsl x3, x4, x3
	sub x5, x3, #1
	bic x6, x0, x5
2:	ic ivau, x6
	add x6, x6, x3
	cmp x6, x1
	b.lo 2b
	dsb ish
	isb
	mov x0, #0
	ret

// lsl_arch_sqrt(bity) -> bity: odmocnina binary64 podle IEEE 754.
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

// Blok vlákna runtime je tam, kam ukazuje tpidr_el0.
	.globl lsl_arch_tls_load
	.p2align 4
lsl_arch_tls_load:
	mrs x1, tpidr_el0
	ldr x0, [x1, x0]
	ret

	.globl lsl_arch_tls_store
	.p2align 4
lsl_arch_tls_store:
	mrs x2, tpidr_el0
	str x1, [x2, x0]
	mov x0, #0
	ret

	.globl lsl_arch_set_thread_pointer
	.p2align 4
lsl_arch_set_thread_pointer:
	msr tpidr_el0, x0
	mov x0, #0
	ret

	.globl qbe_error_flag
	.p2align 4
qbe_error_flag:
	mrs x0, tpidr_el0
	ldr x0, [x0, #8]
	ret

	.globl qbe_error_set
	.p2align 4
qbe_error_set:
	mrs x1, tpidr_el0
	str x0, [x1]
	mov x2, #1
	str x2, [x1, #8]
	mov x0, #0
	ret

	.globl qbe_error_catch
	.p2align 4
qbe_error_catch:
	mrs x1, tpidr_el0
	str xzr, [x1, #8]
	mov x0, #0
	ret

	.globl qbe_error_clear
	.p2align 4
qbe_error_clear:
	mrs x1, tpidr_el0
	str xzr, [x1]
	str xzr, [x1, #8]
	mov x0, #0
	ret

// lsl_arch_clone_thread(flags, zásobník, ctid, tls) -> tid nebo -errno.
// arm64 clone má pořadí (flags, stack, ptid, tls, ctid).
	.globl lsl_arch_clone_thread
	.p2align 4
lsl_arch_clone_thread:
	mov x4, x2
	mov x2, #0
	mov x8, #220
	svc #0
	cbz x0, 1f
	ret
1:	mov x29, #0
	mov x30, #0
	ldr x0, [sp]
	ldr x1, [sp, #8]
	bl lsl_thread_main
	brk #0

	.globl lsl_arch_signal_restorer
	.p2align 4
lsl_arch_signal_restorer:
	mov x8, #139
	svc #0

	.globl _start
	.p2align 4
_start:
	mov x0, sp
	mov x29, #0
	mov x30, #0
	bl lsl_runtime_start
	brk #0

	.bss
	.p2align 3
	.globl lsl_state
lsl_state:
	.zero 8

	.section .note.GNU-stack,"",@progbits
