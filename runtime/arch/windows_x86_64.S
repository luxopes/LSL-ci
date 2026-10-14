# Vrstva architektury pro Windows x86_64 (Win64 ABI: argumenty rcx, rdx,
# r8, r9; zachovává rbx, rbp, rsi, rdi, r12-r15). Instrukce, které LuxIR
# nemá, a přístup k bloku vlákna runtime. Všechno ostatní je v LSL.
#
# Blok vlákna runtime (Linux: fs) je v TLS slotu z TlsAlloc: TEB+0x1480 +
# 8 * slot (TlsSlots, sloty 0..63), čte se přes gs. Slot uloží
# os_windows.process_arguments do lsl_tls_slot.
	.text

# Atomické operace nad 64bitovým slovem (sekvenčně konzistentní).
# lsl_arch_cas64(adresa, očekávaná, nová) -> původní hodnota
	.globl lsl_arch_cas64
	.p2align 4
lsl_arch_cas64:
	mov %rdx, %rax
	lock cmpxchg %r8, (%rcx)
	ret

# lsl_arch_xchg64(adresa, hodnota) -> původní hodnota
	.globl lsl_arch_xchg64
	.p2align 4
lsl_arch_xchg64:
	mov %rdx, %rax
	xchg %rax, (%rcx)
	ret

# lsl_arch_add64(adresa, přírůstek) -> původní hodnota
	.globl lsl_arch_add64
	.p2align 4
lsl_arch_add64:
	mov %rdx, %rax
	lock xadd %rax, (%rcx)
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

# lsl_arch_sqrt(bity) -> bity: odmocnina binary64 podle IEEE 754.
	.globl lsl_arch_sqrt
	.p2align 4
lsl_arch_sqrt:
	movq %rcx, %xmm0
	sqrtsd %xmm0, %xmm0
	movq %xmm0, %rax
	ret

# lsl_arch_spill(buffer) -> ukazatel zásobníku volajícího. Uloží registry,
# které Win64 zachovává (rbx, rbp, r12-r15, rsi, rdi), aby je GC viděl.
	.globl lsl_arch_spill
	.p2align 4
lsl_arch_spill:
	mov %rbx, 0(%rcx)
	mov %rbp, 8(%rcx)
	mov %r12, 16(%rcx)
	mov %r13, 24(%rcx)
	mov %r14, 32(%rcx)
	mov %r15, 40(%rcx)
	mov %rsi, 48(%rcx)
	mov %rdi, 56(%rcx)
	lea 8(%rsp), %rax
	ret

# Blok vlákna runtime do rax (mění jen rax).
.macro THREAD_BLOCK
	mov lsl_tls_slot(%rip), %rax
	mov %gs:0x1480(,%rax,8), %rax
.endm

# lsl_arch_tls_load(posun) -> slovo bloku vlákna runtime.
	.globl lsl_arch_tls_load
	.p2align 4
lsl_arch_tls_load:
	THREAD_BLOCK
	mov (%rax,%rcx), %rax
	ret

# Zápis slova bloku vlákna: lsl_arch_tls_store(posun, hodnota).
	.globl lsl_arch_tls_store
	.p2align 4
lsl_arch_tls_store:
	THREAD_BLOCK
	mov %rdx, (%rax,%rcx)
	xor %eax, %eax
	ret

# Blok vlákna runtime pro volající vlákno (jako TlsSetValue); 0.
	.globl lsl_arch_set_thread_pointer
	.p2align 4
lsl_arch_set_thread_pointer:
	mov lsl_tls_slot(%rip), %rax
	mov %rcx, %gs:0x1480(,%rax,8)
	xor %eax, %eax
	ret

# Chybový stav vlákna (blok vlákna +0 chyba, +8 příznak).
	.globl qbe_error_flag
	.p2align 4
qbe_error_flag:
	THREAD_BLOCK
	mov 8(%rax), %rax
	ret

	.globl qbe_error_set
	.p2align 4
qbe_error_set:
	THREAD_BLOCK
	mov %rcx, (%rax)
	movq $1, 8(%rax)
	xor %eax, %eax
	ret

	.globl qbe_error_catch
	.p2align 4
qbe_error_catch:
	THREAD_BLOCK
	movq $0, 8(%rax)
	xor %eax, %eax
	ret

	.globl qbe_error_clear
	.p2align 4
qbe_error_clear:
	THREAD_BLOCK
	movq $0, (%rax)
	movq $0, 8(%rax)
	xor %eax, %eax
	ret

# lsl_arch_call_native(kód, argumenty) -> výsledek: nativní funkce (ELF,
# konvence System V) se šesti slovy z argumenty v rdi, rsi, rdx, rcx, r8,
# r9. Uloží registry, které Win64 zachovává a System V ne (rsi, rdi,
# xmm6-xmm15).
	.globl lsl_arch_call_native
	.p2align 4
lsl_arch_call_native:
	push %rbp
	mov %rsp, %rbp
	push %rsi
	push %rdi
	sub $160, %rsp
	movdqu %xmm6, 0(%rsp)
	movdqu %xmm7, 16(%rsp)
	movdqu %xmm8, 32(%rsp)
	movdqu %xmm9, 48(%rsp)
	movdqu %xmm10, 64(%rsp)
	movdqu %xmm11, 80(%rsp)
	movdqu %xmm12, 96(%rsp)
	movdqu %xmm13, 112(%rsp)
	movdqu %xmm14, 128(%rsp)
	movdqu %xmm15, 144(%rsp)
	mov %rcx, %rax
	mov %rdx, %r11
	mov 0(%r11), %rdi
	mov 8(%r11), %rsi
	mov 16(%r11), %rdx
	mov 24(%r11), %rcx
	mov 32(%r11), %r8
	mov 40(%r11), %r9
	call *%rax
	movdqu 0(%rsp), %xmm6
	movdqu 16(%rsp), %xmm7
	movdqu 32(%rsp), %xmm8
	movdqu 48(%rsp), %xmm9
	movdqu 64(%rsp), %xmm10
	movdqu 80(%rsp), %xmm11
	movdqu 96(%rsp), %xmm12
	movdqu 112(%rsp), %xmm13
	movdqu 128(%rsp), %xmm14
	movdqu 144(%rsp), %xmm15
	add $160, %rsp
	pop %rdi
	pop %rsi
	pop %rbp
	ret

# Vstup programu (PE AddressOfEntryPoint): Windows nepředává argc ani argv,
# os_windows je sestaví z GetCommandLineW. lsl_runtime_start dostane vrchol
# zásobníku hlavního vlákna (TEB+8, StackBase) a nevrací se.
	.globl _start
	.p2align 4
_start:
	mov %gs:8, %rcx
	xor %ebp, %ebp
	and $-16, %rsp
	sub $32, %rsp
	call lsl_runtime_start
	ud2

# Vstup vlákna z CreateThread (rcx = položka tabulky vláken):
# lsl_thread_begin(položka, vrchol zásobníku); vlákno končí ExitThread.
	.globl lsl_arch_thread_start
	.p2align 4
lsl_arch_thread_start:
	mov %gs:8, %rdx
	sub $40, %rsp
	call lsl_thread_begin
	ud2

	.bss
# Adresa stavu runtime (blok na začátku haldy).
	.p2align 3
	.globl lsl_state
lsl_state:
	.zero 8
# TLS slot bloku vlákna runtime.
	.globl lsl_tls_slot
lsl_tls_slot:
	.zero 8
# Vlákna pro GC: na položku tabulky vláken 144 B (+0 HANDLE vlákna,
# +8 16 registrů zastaveného vlákna z CONTEXT).
	.globl lsl_win_threads
lsl_win_threads:
	.zero 18432
# Vstup z konzole převedený na UTF-8, který se ještě nepřečetl (+0 počet).
	.globl lsl_win_console
lsl_win_console:
	.zero 4104
# CONTEXT pro GetThreadContext (1232 B, zarovnaný na 16).
	.p2align 4
	.globl lsl_win_context
lsl_win_context:
	.zero 1280
