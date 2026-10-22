# Vrstva architektury pro Linux riscv64 (LP64D): jediné místo runtime
# s instrukcemi tohoto CPU. Stejné funkce jako linux_x86_64.S.
	.option norelax
	.text

	.globl lsl_arch_syscall6
	.p2align 4
lsl_arch_syscall6:
	mv a7, a0
	mv a0, a1
	mv a1, a2
	mv a2, a3
	mv a3, a4
	mv a4, a5
	mv a5, a6
	ecall
	ret

	.globl lsl_arch_syscall3
	.p2align 4
lsl_arch_syscall3:
	mv a7, a0
	mv a0, a1
	mv a1, a2
	mv a2, a3
	ecall
	ret

# Atomické operace (aq+rl = sekvenčně konzistentní).
	.globl lsl_arch_cas64
	.p2align 4
lsl_arch_cas64:
1:	lr.d.aqrl a3, (a0)
	bne a3, a1, 2f
	sc.d.aqrl a4, a2, (a0)
	bnez a4, 1b
2:	fence rw, rw
	mv a0, a3
	ret

	.globl lsl_arch_xchg64
	.p2align 4
lsl_arch_xchg64:
	amoswap.d.aqrl a2, a1, (a0)
	mv a0, a2
	ret

	.globl lsl_arch_add64
	.p2align 4
lsl_arch_add64:
	amoadd.d.aqrl a2, a1, (a0)
	mv a0, a2
	ret

	.globl lsl_arch_pause
	.p2align 4
lsl_arch_pause:
	nop
	ret

# lsl_arch_sync_code(adresa, délka): riscv_flush_icache(začátek, konec, 0)
# pro všechna jádra procesu (fence.i platí jen pro aktuální hart).
	.globl lsl_arch_sync_code
	.p2align 4
lsl_arch_sync_code:
	add a1, a0, a1
	li a2, 0
	li a7, 259
	ecall
	fence.i
	li a0, 0
	ret

# lsl_arch_sqrt(bity) -> bity: odmocnina binary64 podle IEEE 754.
	.globl lsl_arch_sqrt
	.p2align 4
lsl_arch_sqrt:
	fmv.d.x fa0, a0
	fsqrt.d fa0, fa0
	fmv.x.d a0, fa0
	ret

# lsl_arch_spill(buffer 96 B) -> ukazatel zásobníku volajícího; uloží s0-s11.
	.globl lsl_arch_spill
	.p2align 4
lsl_arch_spill:
	sd s0, 0(a0)
	sd s1, 8(a0)
	sd s2, 16(a0)
	sd s3, 24(a0)
	sd s4, 32(a0)
	sd s5, 40(a0)
	sd s6, 48(a0)
	sd s7, 56(a0)
	sd s8, 64(a0)
	sd s9, 72(a0)
	sd s10, 80(a0)
	sd s11, 88(a0)
	mv a0, sp
	ret

# Blok vlákna runtime je tam, kam ukazuje tp.
	.globl lsl_arch_tls_load
	.p2align 4
lsl_arch_tls_load:
	add a1, tp, a0
	ld a0, 0(a1)
	ret

	.globl lsl_arch_tls_store
	.p2align 4
lsl_arch_tls_store:
	add a2, tp, a0
	sd a1, 0(a2)
	li a0, 0
	ret

	.globl lsl_arch_set_thread_pointer
	.p2align 4
lsl_arch_set_thread_pointer:
	mv tp, a0
	li a0, 0
	ret

	.globl qbe_error_flag
	.p2align 4
qbe_error_flag:
	ld a0, 8(tp)
	ret

	.globl qbe_error_set
	.p2align 4
qbe_error_set:
	sd a0, 0(tp)
	li a1, 1
	sd a1, 8(tp)
	li a0, 0
	ret

	.globl qbe_error_catch
	.p2align 4
qbe_error_catch:
	sd zero, 8(tp)
	li a0, 0
	ret

	.globl qbe_error_clear
	.p2align 4
qbe_error_clear:
	sd zero, 0(tp)
	sd zero, 8(tp)
	li a0, 0
	ret

# lsl_arch_clone_thread(flags, zásobník, ctid, tls); riscv64 clone má pořadí
# (flags, stack, ptid, tls, ctid).
	.globl lsl_arch_clone_thread
	.p2align 4
lsl_arch_clone_thread:
	mv a4, a2
	li a2, 0
	li a7, 220
	ecall
	beqz a0, 1f
	ret
1:	li ra, 0
	li s0, 0
	ld a0, 0(sp)
	ld a1, 8(sp)
	call lsl_thread_main
	ebreak

# riscv64 nemá SA_RESTORER (návrat přes vDSO); symbol jen pro jednotné jméno.
	.globl lsl_arch_signal_restorer
	.p2align 4
lsl_arch_signal_restorer:
	li a7, 139
	ecall

	.globl _start
	.p2align 4
_start:
	mv a0, sp
	li ra, 0
	li s0, 0
	call lsl_runtime_start
	ebreak

	.bss
	.p2align 3
	.globl lsl_state
lsl_state:
	.zero 8

		.text
# Cesta vláken přes pthread (jen vrstva x86_64 s glibc); zde nevolaná.
	.globl lsl_arch_thread_create
	.p2align 2
lsl_arch_thread_create:
	li a0, -1
	ret

	.globl lsl_arch_thread_exit
	.p2align 2
lsl_arch_thread_exit:
	ebreak

	.data
	.p2align 3
	.globl lsl_arch_threads
lsl_arch_threads:
	.dword 0
	.text

.section .note.GNU-stack,"",@progbits
