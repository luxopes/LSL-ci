# Vrstva architektury pro Linux x86_64 s glibc (cíl linux-x86_64-gnu):
# program je dynamicky linkovaný (ld.so, libc.so.6), aby mohl volat
# systémové knihovny (GTK, GLib). Od statické vrstvy (linux_x86_64.S) se
# liší jen soužitím s glibc: blok vlákna runtime je v gs (fs patří TCB
# glibc) a vlákna vznikají přes pthread_create, aby glibc znala jejich
# TLS a zásobník; všechno ostatní (syscally, GC, signály) zůstává stejné.
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

# lsl_arch_tls_load(posun) -> slovo TLS bloku runtime (gs:posun). Dočasné:
# po přechodu na thread-local proměnné LuxIR zmizí.
	.globl lsl_arch_tls_load
	.p2align 4
lsl_arch_tls_load:
	mov %gs:(%rdi), %rax
	ret

# Vlákna přes pthread (os_linux.lsl se rozhoduje podle lsl_arch_threads = 1):
# lsl_arch_thread_create(položka) -> tid vlákna nebo -1. Odpojené vlákno
# s 8 MiB zásobníkem od glibc; potomek zapíše svůj tid do položky (+0)
# a probudí rodiče, který na něj čeká futexem.
	.globl lsl_arch_thread_create
	.p2align 4
lsl_arch_thread_create:
	push %rbp
	mov %rsp, %rbp
	push %rbx
	push %r12
	sub $80, %rsp
	mov %rdi, %rbx
	movq $0, (%rbx)
	lea 8(%rsp), %rdi
	call pthread_attr_init
	test %eax, %eax
	jnz 9f
	lea 8(%rsp), %rdi
	mov $8388608, %esi
	call pthread_attr_setstacksize
	lea 8(%rsp), %rdi
	mov $1, %esi
	call pthread_attr_setdetachstate
	mov %rsp, %rdi
	lea 8(%rsp), %rsi
	lea lsl_arch_thread_entry(%rip), %rdx
	mov %rbx, %rcx
	call pthread_create
	mov %eax, %r12d
	lea 8(%rsp), %rdi
	call pthread_attr_destroy
	test %r12d, %r12d
	jnz 9f
1:
	mov (%rbx), %rax
	test %rax, %rax
	jnz 2f
	mov %rbx, %rdi
	xor %esi, %esi
	xor %edx, %edx
	xor %r10d, %r10d
	mov $202, %eax
	syscall
	jmp 1b
2:
	add $80, %rsp
	pop %r12
	pop %rbx
	pop %rbp
	ret
9:
	mov $-1, %rax
	add $80, %rsp
	pop %r12
	pop %rbx
	pop %rbp
	ret

# Vstup vlákna z pthread_create (rdi = položka): zveřejní tid, zjistí vrchol
# zásobníku (pthread_getattr_np + pthread_attr_getstack) a předá řízení
# lsl_thread_begin(položka, vrchol); vlákno končí pthread_exit.
	.globl lsl_arch_thread_entry
	.p2align 4
lsl_arch_thread_entry:
	push %rbp
	mov %rsp, %rbp
	push %rbx
	sub $104, %rsp
	mov %rdi, %rbx
	# gs = blok vlákna hned (clone ho nastavuje CLONE_SETTLS před prvním
	# kódem vlákna; kód runtime čte gs:8 i před lsl_thread_begin)
	lea 32(%rbx), %rsi
	mov $4097, %edi
	mov $158, %eax
	syscall
	mov $186, %eax
	syscall
	mov %rax, (%rbx)
	mov %rbx, %rdi
	mov $1, %esi
	mov $2147483647, %edx
	mov $202, %eax
	syscall
	call pthread_self
	mov %rax, %rdi
	lea 16(%rsp), %rsi
	call pthread_getattr_np
	lea 16(%rsp), %rdi
	mov %rsp, %rsi
	lea 8(%rsp), %rdx
	call pthread_attr_getstack
	mov (%rsp), %rsi
	add 8(%rsp), %rsi
	lea 16(%rsp), %rdi
	push %rsi
	push %rsi
	call pthread_attr_destroy
	pop %rsi
	pop %rsi
	mov %rbx, %rdi
	call lsl_thread_begin
	ud2

# lsl_arch_thread_exit(): konec vlákna pthread (uvolní jeho zásobník a TLS).
	.globl lsl_arch_thread_exit
	.p2align 4
lsl_arch_thread_exit:
	push %rbp
	mov %rsp, %rbp
	xor %edi, %edi
	call pthread_exit
	ud2

# Statická cesta vláken (os_linux.lsl ji s lsl_arch_threads = 1 nevolá,
# symbol ale musí existovat, jinak by ho linker hledal v knihovnách).
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

# Thread pointer (gs, ARCH_SET_GS) = blok vlákna runtime; 0 nebo -errno.
	.globl lsl_arch_set_thread_pointer
	.p2align 4
lsl_arch_set_thread_pointer:
	mov %rdi, %rsi
	mov $4097, %edi
	mov $158, %eax
	syscall
	ret

# Zápis slova bloku vlákna: lsl_arch_tls_store(posun, hodnota).
	.globl lsl_arch_tls_store
	.p2align 4
lsl_arch_tls_store:
	mov %rsi, %gs:(%rdi)
	xor %eax, %eax
	ret

# Chybový stav vlákna (blok vlákna +0 chyba, +8 příznak). qbe_error_flag se
# volá po každém volání, které může selhat: dvě instrukce bez rámce.
	.globl qbe_error_flag
	.p2align 4
qbe_error_flag:
	mov %gs:8, %rax
	ret

	.globl qbe_error_set
	.p2align 4
qbe_error_set:
	mov %rdi, %gs:0
	movq $1, %gs:8
	xor %eax, %eax
	ret

	.globl qbe_error_catch
	.p2align 4
qbe_error_catch:
	movq $0, %gs:8
	xor %eax, %eax
	ret

	.globl qbe_error_clear
	.p2align 4
qbe_error_clear:
	movq $0, %gs:0
	movq $0, %gs:8
	xor %eax, %eax
	ret

# Adresa stavu runtime (blok na začátku haldy).
	.bss
	.p2align 3
	.globl lsl_state
lsl_state:
	.zero 8
	.text

# Vlákna přes pthread (1); statická vrstva má 0.
	.data
	.p2align 3
	.globl lsl_arch_threads
lsl_arch_threads:
	.quad 1
	.text

		.text
# Zpětné volání z knihoven C do LSL (signály GTK, zdroje GLib, D-Bus):
# knihovna volá některý z vstupů lsl_arch_callback* se svými argumenty;
# vstup přesune uživatelský záznam (user_data) na první místo, zavolá
# funkci LSL ve slotu (vstup Any → Any, gtk.dispatch(záznam, a1..a6)) a
# její výsledek rozbalí na surové slovo pro volajícího v C (gboolean).
# Přípona udává pozici user_data: bez přípony první (G_CONNECT_SWAPPED,
# GSourceFunc), _u3 třetí (GAsyncReadyCallback, GChildWatchFunc), _u4
# čtvrtá (GBusNameAppearedCallback), _u7 sedmá (GDBusSignalCallback,
# na zásobníku), _u8 osmá s vynecháním prvního argumentu
# (GDBusInterfaceMethodCallFunc: spojení zná volající). Zarovnání zásobníku
# při volání drží push/sub.
	.globl lsl_arch_callback
	.p2align 4
lsl_arch_callback:
	push %rbx
	mov lsl_arch_callback_slot(%rip), %rax
	call *%rax
	mov %rax, %rdi
	call rt_runtime_unbox_dynamic_int
	pop %rbx
	ret

	.globl lsl_arch_callback_u3
	.p2align 4
lsl_arch_callback_u3:
	# (a1, a2, data) -> (data, a1, a2)
	push %rbx
	mov %rdx, %rax
	mov %rsi, %rdx
	mov %rdi, %rsi
	mov %rax, %rdi
	mov lsl_arch_callback_slot(%rip), %rax
	call *%rax
	mov %rax, %rdi
	call rt_runtime_unbox_dynamic_int
	pop %rbx
	ret

	.globl lsl_arch_callback_u4
	.p2align 4
lsl_arch_callback_u4:
	# (a1, a2, a3, data) -> (data, a1, a2, a3)
	push %rbx
	mov %rcx, %rax
	mov %rdx, %rcx
	mov %rsi, %rdx
	mov %rdi, %rsi
	mov %rax, %rdi
	mov lsl_arch_callback_slot(%rip), %rax
	call *%rax
	mov %rax, %rdi
	call rt_runtime_unbox_dynamic_int
	pop %rbx
	ret

	.globl lsl_arch_callback_u7
	.p2align 4
lsl_arch_callback_u7:
	# (a1..a6, data na zásobníku) -> (data, a1..a5, a6 na zásobníku)
	push %rbx
	sub $8, %rsp
	push %r9
	mov 32(%rsp), %rax
	mov %r8, %r9
	mov %rcx, %r8
	mov %rdx, %rcx
	mov %rsi, %rdx
	mov %rdi, %rsi
	mov %rax, %rdi
	mov lsl_arch_callback_slot(%rip), %rax
	call *%rax
	mov %rax, %rdi
	call rt_runtime_unbox_dynamic_int
	add $16, %rsp
	pop %rbx
	ret

	.globl lsl_arch_callback_u8
	.p2align 4
lsl_arch_callback_u8:
	# (a1..a6, a7 a data na zásobníku) -> (data, a2..a6, a7 na zásobníku)
	push %rbx
	sub $8, %rsp
	mov 24(%rsp), %rax
	push %rax
	mov 40(%rsp), %rdi
	mov lsl_arch_callback_slot(%rip), %rax
	call *%rax
	mov %rax, %rdi
	call rt_runtime_unbox_dynamic_int
	add $16, %rsp
	pop %rbx
	ret

# Zpětná volání OpenSSL bez user_data, která nemusí do LSL (modul tls):
# lsl_arch_return_one přijme každý certifikát protistrany (verify callback;
# aplikace si klíč připne sama), lsl_arch_alpn_select vybere ALPN serveru:
# (ssl, out, outlen, in, inlen, arg) -> arg[0](out, outlen, arg[1], arg[2],
# in, inlen), tedy SSL_select_next_proto se seznamem serveru v arg; shoda
# (OPENSSL_NPN_NEGOTIATED = 1) vrací SSL_TLSEXT_ERR_OK, jinak NOACK (3),
# spojení pokračuje bez ALPN jako u Pythonu. Adresu SSL_select_next_proto
# dodá modul tls, runtime tak na libssl nezávisí.
	.globl lsl_arch_return_one
	.p2align 4
lsl_arch_return_one:
	mov $1, %eax
	ret

	.globl lsl_arch_alpn_select
	.p2align 4
lsl_arch_alpn_select:
	push %rbx
	mov %r9, %rbx
	mov %rsi, %rdi
	mov %rdx, %rsi
	mov %r8, %r9
	mov %rcx, %r8
	mov 8(%rbx), %rdx
	mov 16(%rbx), %rcx
	call *(%rbx)
	pop %rbx
	cmp $1, %eax
	jne 9f
	xor %eax, %eax
	ret
9:
	mov $3, %eax
	ret

	.data
	.p2align 3
	.globl lsl_arch_callback_slot
lsl_arch_callback_slot:
	.quad 0
	.text

.section .note.GNU-stack,"",@progbits
