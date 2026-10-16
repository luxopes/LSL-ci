// Vrstva architektury pro Linux x86 (i686, SSE2), 32 bitů: jediné místo
// runtime s instrukcemi a systémovými voláními tohoto CPU. Stejné funkce
// jako linux_x86_64.S. Parametry a výsledky jsou 64bitová slova LuxIR
// (cdecl: na zásobníku po 8 bajtech, výsledek v edx:eax), ukazatele v nich
// zabírají dolních 32 bitů.
//
// Blok vlákna runtime je báze segmentu %gs: položka TLS v GDT ze
// set_thread_area; nová vlákna dostanou vlastní položku se stejným číslem
// přes CLONE_SETTLS (user_desc).

	.data
	.balign 8
	.globl lsl_state
lsl_state:
	.quad 0
// Číslo položky TLS v GDT (set_thread_area hlavního vlákna).
	.globl lsl_tls_entry
lsl_tls_entry:
	.long 0xffffffff

	.text

// Systémové volání přes int 0x80: číslo v eax, argumenty ebx, ecx, edx,
// esi, edi, ebp. -4095..-1 je chyba (rozšíří se znaménkem), vše ostatní je
// nezáporná hodnota (i adresa nad 2 GiB). Argumenty: číslo na 4(%esp),
// a..f po 8 bajtech od 12(%esp); po uložení čtyř registrů o 16 dál.
	.globl lsl_arch_syscall6
	.type lsl_arch_syscall6, @function
	.p2align 4
lsl_arch_syscall6:
	push %ebp
	push %edi
	push %esi
	push %ebx
	mov 20(%esp), %eax
	mov 28(%esp), %ebx
	mov 36(%esp), %ecx
	mov 44(%esp), %edx
	mov 52(%esp), %esi
	mov 60(%esp), %edi
	mov 68(%esp), %ebp
	int $0x80
	xor %edx, %edx
	cmp $-4095, %eax
	jb 1f
	mov $-1, %edx
1:	pop %ebx
	pop %esi
	pop %edi
	pop %ebp
	ret

	.globl lsl_arch_syscall3
	.type lsl_arch_syscall3, @function
	.p2align 4
lsl_arch_syscall3:
	push %ebx
	mov 8(%esp), %eax
	mov 16(%esp), %ebx
	mov 24(%esp), %ecx
	mov 32(%esp), %edx
	int $0x80
	xor %edx, %edx
	cmp $-4095, %eax
	jb 1f
	mov $-1, %edx
1:	pop %ebx
	ret

// lsl_arch_spill(buffer 96 B) -> ukazatel zásobníku; uloží callee-saved
// ebx, esi, edi, ebp pro konzervativní GC.
	.globl lsl_arch_spill
	.type lsl_arch_spill, @function
	.p2align 4
lsl_arch_spill:
	mov 4(%esp), %eax
	mov %ebx, (%eax)
	mov %esi, 4(%eax)
	mov %edi, 8(%eax)
	mov %ebp, 12(%eax)
	mov %esp, %eax
	xor %edx, %edx
	ret

// Atomické operace nad 64bitovým slovem (lock cmpxchg8b): adresa na
// 4(%esp), další argumenty od 12(%esp); po uložení ebx a esi o 8 dál.
// lsl_arch_cas64(adresa, očekávaná, nová) -> původní hodnota
	.globl lsl_arch_cas64
	.type lsl_arch_cas64, @function
	.p2align 4
lsl_arch_cas64:
	push %ebx
	push %esi
	mov 12(%esp), %esi
	mov 20(%esp), %eax
	mov 24(%esp), %edx
	mov 28(%esp), %ebx
	mov 32(%esp), %ecx
	lock cmpxchg8b (%esi)
	pop %esi
	pop %ebx
	ret

// lsl_arch_xchg64(adresa, hodnota) -> původní hodnota
	.globl lsl_arch_xchg64
	.type lsl_arch_xchg64, @function
	.p2align 4
lsl_arch_xchg64:
	push %ebx
	push %esi
	mov 12(%esp), %esi
	mov 20(%esp), %ebx
	mov 24(%esp), %ecx
	mov (%esi), %eax
	mov 4(%esi), %edx
1:	lock cmpxchg8b (%esi)
	jnz 1b
	pop %esi
	pop %ebx
	ret

// lsl_arch_add64(adresa, přírůstek) -> původní hodnota
	.globl lsl_arch_add64
	.type lsl_arch_add64, @function
	.p2align 4
lsl_arch_add64:
	push %ebx
	push %esi
	mov 12(%esp), %esi
	mov (%esi), %eax
	mov 4(%esi), %edx
1:	mov %eax, %ebx
	mov %edx, %ecx
	add 20(%esp), %ebx
	adc 24(%esp), %ecx
	lock cmpxchg8b (%esi)
	jnz 1b
	pop %esi
	pop %ebx
	ret

	.globl lsl_arch_pause
	.type lsl_arch_pause, @function
	.p2align 4
lsl_arch_pause:
	pause
	xor %eax, %eax
	xor %edx, %edx
	ret

// x86 má koherentní instrukční cache.
	.globl lsl_arch_sync_code
	.type lsl_arch_sync_code, @function
	.p2align 4
lsl_arch_sync_code:
	xor %eax, %eax
	xor %edx, %edx
	ret

// lsl_arch_sqrt(bity) -> bity: odmocnina binary64 podle IEEE 754 (sqrtsd).
	.globl lsl_arch_sqrt
	.type lsl_arch_sqrt, @function
	.p2align 4
lsl_arch_sqrt:
	sqrtsd 4(%esp), %xmm0
	movd %xmm0, %eax
	psrlq $32, %xmm0
	movd %xmm0, %edx
	ret

// lsl_arch_tls_load(posun) -> slovo bloku vlákna
	.globl lsl_arch_tls_load
	.type lsl_arch_tls_load, @function
	.p2align 4
lsl_arch_tls_load:
	mov 4(%esp), %ecx
	mov %gs:(%ecx), %eax
	mov %gs:4(%ecx), %edx
	ret

// lsl_arch_tls_store(posun, hodnota)
	.globl lsl_arch_tls_store
	.type lsl_arch_tls_store, @function
	.p2align 4
lsl_arch_tls_store:
	mov 4(%esp), %ecx
	mov 12(%esp), %eax
	mov %eax, %gs:(%ecx)
	mov 16(%esp), %eax
	mov %eax, %gs:4(%ecx)
	xor %eax, %eax
	xor %edx, %edx
	ret

// lsl_arch_set_thread_pointer(blok) -> 0 nebo -errno: set_thread_area
// (243) s user_desc (položka, báze, limit 4 GiB po stránkách, příznaky
// 0x51), pak %gs na položku (selektor: číslo * 8 + RPL 3).
	.globl lsl_arch_set_thread_pointer
	.type lsl_arch_set_thread_pointer, @function
	.p2align 4
lsl_arch_set_thread_pointer:
	push %ebx
	sub $16, %esp
	mov lsl_tls_entry, %eax
	mov %eax, (%esp)
	mov 24(%esp), %eax
	mov %eax, 4(%esp)
	movl $0xfffff, 8(%esp)
	movl $0x51, 12(%esp)
	mov %esp, %ebx
	mov $243, %eax
	int $0x80
	test %eax, %eax
	jz 1f
	cdq
	add $16, %esp
	pop %ebx
	ret
1:	mov (%esp), %eax
	mov %eax, lsl_tls_entry
	lea 3(,%eax,8), %eax
	mov %ax, %gs
	xor %eax, %eax
	xor %edx, %edx
	add $16, %esp
	pop %ebx
	ret

// Chybový stav vlákna: [0] hodnota chyby, [8] příznak.
	.globl qbe_error_flag
	.type qbe_error_flag, @function
	.p2align 4
qbe_error_flag:
	mov %gs:8, %eax
	mov %gs:12, %edx
	ret

	.globl qbe_error_set
	.type qbe_error_set, @function
	.p2align 4
qbe_error_set:
	mov 4(%esp), %eax
	mov %eax, %gs:0
	mov 8(%esp), %eax
	mov %eax, %gs:4
	movl $1, %gs:8
	movl $0, %gs:12
	xor %eax, %eax
	xor %edx, %edx
	ret

	.globl qbe_error_catch
	.type qbe_error_catch, @function
	.p2align 4
qbe_error_catch:
	movl $0, %gs:8
	movl $0, %gs:12
	xor %eax, %eax
	xor %edx, %edx
	ret

	.globl qbe_error_clear
	.type qbe_error_clear, @function
	.p2align 4
qbe_error_clear:
	xor %eax, %eax
	mov %eax, %gs:0
	mov %eax, %gs:4
	mov %eax, %gs:8
	mov %eax, %gs:12
	xor %edx, %edx
	ret

// lsl_arch_clone_thread(flags, zásobník, ctid, tls) -> tid nebo -errno.
// i386 clone: (flags, stack, ptid, user_desc, ctid). user_desc (16 B na
// zásobníku, jádro ho zkopíruje): stejná položka GDT, báze tls, limit
// 4 GiB po stránkách, 32bitový segment (příznaky 0x51). Potomek najde
// na novém zásobníku položku a funkci (dvě 64bitová slova) a zavolá
// lsl_thread_main(položka, funkce).
	.globl lsl_arch_clone_thread
	.type lsl_arch_clone_thread, @function
	.p2align 4
lsl_arch_clone_thread:
	push %ebp
	push %edi
	push %esi
	push %ebx
	sub $16, %esp
	mov lsl_tls_entry, %eax
	mov %eax, (%esp)
	mov 60(%esp), %eax
	mov %eax, 4(%esp)
	movl $0xfffff, 8(%esp)
	movl $0x51, 12(%esp)
	mov 36(%esp), %ebx
	mov 44(%esp), %ecx
	xor %edx, %edx
	mov %esp, %esi
	mov 52(%esp), %edi
	mov $120, %eax
	int $0x80
	test %eax, %eax
	jz 2f
	add $16, %esp
	mov %eax, %edx
	sar $31, %edx
	pop %ebx
	pop %esi
	pop %edi
	pop %ebp
	ret
2:	xor %ebp, %ebp
	mov (%esp), %eax
	mov 4(%esp), %ebx
	mov 8(%esp), %ecx
	mov 12(%esp), %edx
	push %edx
	push %ecx
	push %ebx
	push %eax
	call lsl_thread_main
	ud2

// Návrat ze signálu: bez SA_SIGINFO staví jádro starý rámec, proto
// sigreturn (119) po odebrání čísla signálu.
	.globl lsl_arch_signal_restorer
	.type lsl_arch_signal_restorer, @function
	.p2align 4
lsl_arch_signal_restorer:
	pop %eax
	mov $119, %eax
	int $0x80

// Start procesu: vrchol zásobníku (argc) jako 64bitové slovo.
	.globl _start
	.type _start, @function
	.p2align 4
_start:
	xor %ebp, %ebp
	mov %esp, %eax
	and $-16, %esp
	sub $8, %esp
	push $0
	push %eax
	call lsl_runtime_start
	ud2

	.section .note.GNU-stack,"",@progbits
