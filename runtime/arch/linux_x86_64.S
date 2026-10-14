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

# lsl_arch_sync_code(adresa, délka): x86_64 má koherentní instrukční cache.
	.globl lsl_arch_sync_code
	.p2align 4
lsl_arch_sync_code:
	xorl %eax, %eax
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

# lsl_arch_clone_thread(flags, zásobník, ctid, tls) -> tid potomka nebo -errno.
# Potomek začne na novém zásobníku, kde leží [rsp] = položka tabulky vláken
# a [rsp+8] = funkce, a zavolá lsl_thread_main(položka, funkce); nevrací se.
	.globl lsl_arch_clone_thread
	.p2align 4
lsl_arch_clone_thread:
	mov %rcx, %r8
	mov %rdx, %r10
	xor %edx, %edx
	mov $56, %eax
	syscall
	test %rax, %rax
	jz 1f
	ret
1:
	xor %ebp, %ebp
	mov (%rsp), %rdi
	mov 8(%rsp), %rsi
	call lsl_thread_main
	ud2

# Návrat z obsluhy signálu (sa_restorer).
	.globl lsl_arch_signal_restorer
	.p2align 4
lsl_arch_signal_restorer:
	mov $15, %eax
	syscall

# Vstup programu: jádro předá na zásobníku argc, argv, envp a auxv.
# lsl_runtime_start(vrchol zásobníku) se nevrací.
	.globl _start
	.p2align 4
_start:
	mov %rsp, %rdi
	xor %ebp, %ebp
	and $-16, %rsp
	call lsl_runtime_start
	ud2

# Thread pointer (fs) = blok vlákna runtime; 0 nebo -errno.
	.globl lsl_arch_set_thread_pointer
	.p2align 4
lsl_arch_set_thread_pointer:
	mov %rdi, %rsi
	mov $4098, %edi
	mov $158, %eax
	syscall
	ret

# Zápis slova bloku vlákna: lsl_arch_tls_store(posun, hodnota).
	.globl lsl_arch_tls_store
	.p2align 4
lsl_arch_tls_store:
	mov %rsi, %fs:(%rdi)
	xor %eax, %eax
	ret

# Chybový stav vlákna (blok vlákna +0 chyba, +8 příznak). qbe_error_flag se
# volá po každém volání, které může selhat: dvě instrukce bez rámce.
	.globl qbe_error_flag
	.p2align 4
qbe_error_flag:
	mov %fs:8, %rax
	ret

	.globl qbe_error_set
	.p2align 4
qbe_error_set:
	mov %rdi, %fs:0
	movq $1, %fs:8
	xor %eax, %eax
	ret

	.globl qbe_error_catch
	.p2align 4
qbe_error_catch:
	movq $0, %fs:8
	xor %eax, %eax
	ret

	.globl qbe_error_clear
	.p2align 4
qbe_error_clear:
	movq $0, %fs:0
	movq $0, %fs:8
	xor %eax, %eax
	ret

# Adresa stavu runtime (blok na začátku haldy).
	.bss
	.p2align 3
	.globl lsl_state
lsl_state:
	.zero 8
	.text

	.section .note.GNU-stack,"",@progbits
