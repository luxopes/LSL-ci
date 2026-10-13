# Vrstva architektury pro Linux x86_64: jediné místo runtime, kde jsou
# instrukce konkrétního CPU. Všechno ostatní je v LSL (runtime/*.lsl).
	.text

# lsl_arch_syscall6(číslo, a1, a2, a3, a4, a5, a6) -> výsledek jádra
	.globl lsl_arch_syscall6
	.p2align 4
lsl_arch_syscall6:
	mov %rdi, %rax
	mov %rsi, %rdi
	mov %rdx, %rsi
	mov %rcx, %rdx
	mov %r8, %r10
	mov %r9, %r8
	mov 8(%rsp), %r9
	syscall
	ret

# Atomické operace nad 64bitovým slovem (sekvenčně konzistentní).
# lsl_arch_cas64(adresa, očekávaná, nová) -> původní hodnota
	.globl lsl_arch_cas64
	.p2align 4
lsl_arch_cas64:
	mov %rsi, %rax
	lock cmpxchg %rdx, (%rdi)
	ret

# lsl_arch_xchg64(adresa, hodnota) -> původní hodnota
	.globl lsl_arch_xchg64
	.p2align 4
lsl_arch_xchg64:
	mov %rsi, %rax
	xchg %rax, (%rdi)
	ret

# lsl_arch_add64(adresa, přírůstek) -> původní hodnota
	.globl lsl_arch_add64
	.p2align 4
lsl_arch_add64:
	mov %rsi, %rax
	lock xadd %rax, (%rdi)
	ret

# Nápověda CPU při aktivním čekání.
	.globl lsl_arch_pause
	.p2align 4
lsl_arch_pause:
	pause
	ret

	.section .note.GNU-stack,"",@progbits
