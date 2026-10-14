# Vrstva architektury pro macOS x86_64 (System V ABI jako Linux, symboly
# Mach-O s podtržítkem). Systémová volání nejdou přímo: runtime volá
# libSystem (os_macos.lsl). Funkce s proměnným počtem argumentů (open,
# openat, fcntl, ioctl) a fstat s 64bitovým inode volá přes zdejší můstky.
#
# Blok vlákna runtime je v TSD slotu z pthread_key_create: gs ukazuje na
# pole TSD vlákna (jako pthread_getspecific), slot uloží os_macos do
# lsl_tls_slot.
	.text

# lsl_arch_cas64(adresa, očekávaná, nová) -> původní hodnota
	.globl _lsl_arch_cas64
	.p2align 4
_lsl_arch_cas64:
	mov %rsi, %rax
	lock cmpxchg %rdx, (%rdi)
	ret

	.globl _lsl_arch_xchg64
	.p2align 4
_lsl_arch_xchg64:
	mov %rsi, %rax
	xchg %rax, (%rdi)
	ret

	.globl _lsl_arch_add64
	.p2align 4
_lsl_arch_add64:
	mov %rsi, %rax
	lock xadd %rax, (%rdi)
	ret

	.globl _lsl_arch_pause
	.p2align 4
_lsl_arch_pause:
	pause
	ret

	.globl _lsl_arch_sync_code
	.p2align 4
_lsl_arch_sync_code:
	xorl %eax, %eax
	ret

	.globl _lsl_arch_sqrt
	.p2align 4
_lsl_arch_sqrt:
	movq %rdi, %xmm0
	sqrtsd %xmm0, %xmm0
	movq %xmm0, %rax
	ret

# lsl_arch_spill(buffer) -> ukazatel zásobníku volajícího; callee-saved
# registry (rbx, rbp, r12-r15) do bufferu pro konzervativní GC.
	.globl _lsl_arch_spill
	.p2align 4
_lsl_arch_spill:
	mov %rbx, 0(%rdi)
	mov %rbp, 8(%rdi)
	mov %r12, 16(%rdi)
	mov %r13, 24(%rdi)
	mov %r14, 32(%rdi)
	mov %r15, 40(%rdi)
	lea 8(%rsp), %rax
	ret

# Blok vlákna runtime do rax (mění jen rax).
.macro THREAD_BLOCK
	mov _lsl_tls_slot(%rip), %rax
	mov %gs:(,%rax,8), %rax
.endm

	.globl _lsl_arch_tls_load
	.p2align 4
_lsl_arch_tls_load:
	THREAD_BLOCK
	mov (%rax,%rdi), %rax
	ret

	.globl _lsl_arch_tls_store
	.p2align 4
_lsl_arch_tls_store:
	THREAD_BLOCK
	mov %rsi, (%rax,%rdi)
	xor %eax, %eax
	ret

# Blok vlákna runtime pro volající vlákno (jako pthread_setspecific); 0.
	.globl _lsl_arch_set_thread_pointer
	.p2align 4
_lsl_arch_set_thread_pointer:
	mov _lsl_tls_slot(%rip), %rax
	mov %rdi, %gs:(,%rax,8)
	xor %eax, %eax
	ret

	.globl _qbe_error_flag
	.p2align 4
_qbe_error_flag:
	THREAD_BLOCK
	mov 8(%rax), %rax
	ret

	.globl _qbe_error_set
	.p2align 4
_qbe_error_set:
	THREAD_BLOCK
	mov %rdi, (%rax)
	movq $1, 8(%rax)
	xor %eax, %eax
	ret

	.globl _qbe_error_catch
	.p2align 4
_qbe_error_catch:
	THREAD_BLOCK
	movq $0, 8(%rax)
	xor %eax, %eax
	ret

	.globl _qbe_error_clear
	.p2align 4
_qbe_error_clear:
	THREAD_BLOCK
	movq $0, (%rax)
	movq $0, 8(%rax)
	xor %eax, %eax
	ret

# lsl_arch_call_native(kód, argumenty) -> výsledek: nativní funkce (ELF,
# System V jako macOS) se šesti slovy z argumenty v rdi, rsi, rdx, rcx,
# r8, r9.
	.globl _lsl_arch_call_native
	.p2align 4
_lsl_arch_call_native:
	push %rbp
	mov %rsp, %rbp
	mov %rdi, %rax
	mov %rsi, %r11
	mov 0(%r11), %rdi
	mov 8(%r11), %rsi
	mov 16(%r11), %rdx
	mov 24(%r11), %rcx
	mov 32(%r11), %r8
	mov 40(%r11), %r9
	call *%rax
	pop %rbp
	ret

# Vstup programu (LC_MAIN): dyld volá main(argc, argv, envp). Argumenty
# si uloží os_macos.process_arguments z lsl_mac_args; lsl_runtime_start
# dostane vrchol zásobníku hlavního vlákna a nevrací se.
	.globl _main
	.p2align 4
_main:
	push %rbp
	mov %rsp, %rbp
	mov %rdi, _lsl_mac_args(%rip)
	mov %rsi, _lsl_mac_args+8(%rip)
	mov %rdx, _lsl_mac_args+16(%rip)
	lea 16(%rsp), %rdi
	call _lsl_runtime_start
	ud2

# Vstup vlákna z pthread_create (rdi = položka tabulky vláken):
# lsl_thread_begin(položka, vrchol zásobníku); vlákno končí pthread_exit.
	.globl _lsl_arch_thread_start
	.p2align 4
_lsl_arch_thread_start:
	push %rbp
	mov %rsp, %rbp
	push %rbx
	push %rbx
	mov %rdi, %rbx
	call _pthread_self
	mov %rax, %rdi
	call _pthread_get_stackaddr_np
	mov %rax, %rsi
	mov %rbx, %rdi
	call _lsl_thread_begin
	ud2

# Můstky k funkcím s proměnným počtem argumentů (System V: al = počet
# vektorových registrů) a k fstat s 64bitovým inode.
	.globl _lsl_arch_open
	.p2align 4
_lsl_arch_open:
	xor %eax, %eax
	jmp _open

	.globl _lsl_arch_openat
	.p2align 4
_lsl_arch_openat:
	xor %eax, %eax
	jmp _openat

	.globl _lsl_arch_fcntl
	.p2align 4
_lsl_arch_fcntl:
	xor %eax, %eax
	jmp _fcntl

	.globl _lsl_arch_ioctl
	.p2align 4
_lsl_arch_ioctl:
	xor %eax, %eax
	jmp _ioctl

	.globl _lsl_arch_fstat
	.p2align 4
_lsl_arch_fstat:
	jmp _fstat$INODE64

# Adresa stavu runtime, TSD slot bloku vlákna a argumenty z main.
	.zerofill __DATA,__bss,_lsl_state,8,3
	.globl _lsl_state
	.zerofill __DATA,__bss,_lsl_tls_slot,8,3
	.globl _lsl_tls_slot
	.zerofill __DATA,__bss,_lsl_mac_args,24,3
	.globl _lsl_mac_args
# Rezervace haldy (+0 začátek, +8 konec) a pthread_t vláken tabulky.
	.zerofill __DATA,__bss,_lsl_mac_heap,16,3
	.globl _lsl_mac_heap
	.zerofill __DATA,__bss,_lsl_mac_threads,1024,3
	.globl _lsl_mac_threads
