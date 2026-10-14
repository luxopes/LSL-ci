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

# lsl_arch_syscall3(číslo, a1, a2, a3) -> výsledek jádra; bez sedmého
# argumentu na zásobníku je volání kratší než přes lsl_arch_syscall6.
	.globl lsl_arch_syscall3
	.p2align 4
lsl_arch_syscall3:
	mov %rdi, %rax
	mov %rsi, %rdi
	mov %rdx, %rsi
	mov %rcx, %rdx
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

# lsl_arch_sqrt(bity) -> bity: odmocnina binary64 zaokrouhlená podle IEEE 754
# (LuxIR nemá instrukci odmocniny). arm64: fmov d0, x0; fsqrt d0, d0;
# fmov x0, d0. rv64: fmv.d.x fa0, a0; fsqrt.d fa0, fa0; fmv.x.d a0, fa0.
	.globl lsl_arch_sqrt
	.p2align 4
lsl_arch_sqrt:
	movq %rdi, %xmm0
	sqrtsd %xmm0, %xmm0
	movq %xmm0, %rax
	ret

# lsl_arch_spill(buffer) -> ukazatel zásobníku volajícího. Uloží callee-saved
# registry (rbx, rbp, r12-r15) do bufferu, aby je konzervativní GC viděl.
	.globl lsl_arch_spill
	.p2align 4
lsl_arch_spill:
	mov %rbx, 0(%rdi)
	mov %rbp, 8(%rdi)
	mov %r12, 16(%rdi)
	mov %r13, 24(%rdi)
	mov %r14, 32(%rdi)
	mov %r15, 40(%rdi)
	lea 8(%rsp), %rax
	ret

# lsl_arch_tls_load(posun) -> slovo TLS bloku runtime (fs:posun). Dočasné:
# po přechodu na thread-local proměnné LuxIR zmizí.
	.globl lsl_arch_tls_load
	.p2align 4
lsl_arch_tls_load:
	mov %fs:(%rdi), %rax
	ret

	.section .note.GNU-stack,"",@progbits
