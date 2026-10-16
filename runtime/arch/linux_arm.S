// Vrstva architektury pro Linux ARM (armv7-a, EABI, hard-float), 32 bitů:
// jediné místo runtime s instrukcemi a systémovými voláními tohoto CPU.
// Stejné funkce jako linux_arm64.S. Parametry a výsledky jsou 64bitová
// slova LuxIR (AAPCS: dvojice r0:r1, r2:r3, pak zásobník po 8 bajtech;
// výsledek r0:r1), ukazatele v nich zabírají dolních 32 bitů.
//
// Blok vlákna runtime je tam, kam ukazuje TPIDRURO (mrc p15, 0, rX, c13,
// c0, 3); hlavní vlákno ho nastaví voláním set_tls, nová vlákna
// CLONE_SETTLS.

	.syntax unified
	.arm
	.fpu vfpv3-d16

	.data
	.balign 8
	.globl lsl_state
lsl_state:
	.quad 0

	.text

// Výsledek jádra v r0: -4095..-1 je chyba (záporné errno, rozšíří se
// znaménkem), vše ostatní je nezáporná hodnota (i adresa nad 2 GiB).
.macro kernel_result
	movw ip, #0xf001
	movt ip, #0xffff
	mov r1, #0
	cmp r0, ip
	mvnhs r1, #0
.endm

// lsl_arch_syscall6(číslo, a1..a6) -> výsledek jádra: číslo v r0:r1,
// a1 v r2:r3, a2..a6 na [sp], po uložení čtyř registrů od [sp+16].
	.globl lsl_arch_syscall6
	.type lsl_arch_syscall6, %function
	.p2align 2
lsl_arch_syscall6:
	push {r4, r5, r7, lr}
	mov r7, r0
	mov r0, r2
	ldr r1, [sp, #16]
	ldr r2, [sp, #24]
	ldr r3, [sp, #32]
	ldr r4, [sp, #40]
	ldr r5, [sp, #48]
	svc #0
	kernel_result
	pop {r4, r5, r7, pc}

	.globl lsl_arch_syscall3
	.type lsl_arch_syscall3, %function
	.p2align 2
lsl_arch_syscall3:
	push {r7, lr}
	mov r7, r0
	mov r0, r2
	ldr r1, [sp, #8]
	ldr r2, [sp, #16]
	svc #0
	kernel_result
	pop {r7, pc}

// Atomické operace nad 64bitovým slovem (ldrexd/strexd, sekvenčně
// konzistentní přes dmb). Adresa v r0:r1.
// lsl_arch_cas64(adresa, očekávaná r2:r3, nová [sp]) -> původní hodnota
	.globl lsl_arch_cas64
	.type lsl_arch_cas64, %function
	.p2align 2
lsl_arch_cas64:
	push {r4, r5, r6, r7}
	ldr r4, [sp, #16]
	ldr r5, [sp, #20]
	mov ip, r0
	dmb ish
1:	ldrexd r0, r1, [ip]
	cmp r0, r2
	cmpeq r1, r3
	bne 2f
	strexd r6, r4, r5, [ip]
	cmp r6, #0
	bne 1b
	dmb ish
	pop {r4, r5, r6, r7}
	bx lr
2:	clrex
	dmb ish
	pop {r4, r5, r6, r7}
	bx lr

// lsl_arch_xchg64(adresa, hodnota r2:r3) -> původní hodnota
	.globl lsl_arch_xchg64
	.type lsl_arch_xchg64, %function
	.p2align 2
lsl_arch_xchg64:
	push {r4, lr}
	mov ip, r0
	dmb ish
1:	ldrexd r0, r1, [ip]
	strexd r4, r2, r3, [ip]
	cmp r4, #0
	bne 1b
	dmb ish
	pop {r4, pc}

// lsl_arch_add64(adresa, přírůstek r2:r3) -> původní hodnota
	.globl lsl_arch_add64
	.type lsl_arch_add64, %function
	.p2align 2
lsl_arch_add64:
	push {r4, r5, r6, lr}
	mov ip, r0
	dmb ish
1:	ldrexd r0, r1, [ip]
	adds r4, r0, r2
	adc r5, r1, r3
	strexd r6, r4, r5, [ip]
	cmp r6, #0
	bne 1b
	dmb ish
	pop {r4, r5, r6, pc}

	.globl lsl_arch_pause
	.type lsl_arch_pause, %function
	.p2align 2
lsl_arch_pause:
	yield
	mov r0, #0
	mov r1, #0
	bx lr

// lsl_arch_sync_code(adresa r0:r1, délka r2:r3): zapsaný kód do
// instrukční cache přes soukromé volání ARM cacheflush (0xf0002).
	.globl lsl_arch_sync_code
	.type lsl_arch_sync_code, %function
	.p2align 2
lsl_arch_sync_code:
	push {r7, lr}
	add r1, r0, r2
	mov r2, #0
	movw r7, #2
	movt r7, #0xf
	svc #0
	mov r0, #0
	mov r1, #0
	pop {r7, pc}

// lsl_arch_sqrt(bity) -> bity: odmocnina binary64 podle IEEE 754 (vsqrt).
	.globl lsl_arch_sqrt
	.type lsl_arch_sqrt, %function
	.p2align 2
lsl_arch_sqrt:
	vmov d0, r0, r1
	vsqrt.f64 d0, d0
	vmov r0, r1, d0
	bx lr

// lsl_arch_spill(buffer 96 B) -> ukazatel zásobníku; uloží callee-saved
// registry r4-r11 pro konzervativní GC (po 4 bajtech, jako zásobník).
	.globl lsl_arch_spill
	.type lsl_arch_spill, %function
	.p2align 2
lsl_arch_spill:
	stm r0, {r4-r11}
	mov r0, sp
	mov r1, #0
	bx lr

// lsl_arch_tls_load(posun) -> slovo bloku vlákna
	.globl lsl_arch_tls_load
	.type lsl_arch_tls_load, %function
	.p2align 2
lsl_arch_tls_load:
	mrc p15, 0, r2, c13, c0, 3
	add r2, r2, r0
	ldr r0, [r2]
	ldr r1, [r2, #4]
	bx lr

// lsl_arch_tls_store(posun, hodnota r2:r3)
	.globl lsl_arch_tls_store
	.type lsl_arch_tls_store, %function
	.p2align 2
lsl_arch_tls_store:
	mrc p15, 0, ip, c13, c0, 3
	add ip, ip, r0
	str r2, [ip]
	str r3, [ip, #4]
	mov r0, #0
	mov r1, #0
	bx lr

// set_tls (__ARM_NR_set_tls = 0xf0005) nastaví TPIDRURO volajícího vlákna.
	.globl lsl_arch_set_thread_pointer
	.type lsl_arch_set_thread_pointer, %function
	.p2align 2
lsl_arch_set_thread_pointer:
	push {r7, lr}
	movw r7, #5
	movt r7, #0xf
	svc #0
	kernel_result
	pop {r7, pc}

// Chybový stav vlákna: [0] hodnota chyby, [8] příznak.
	.globl qbe_error_flag
	.type qbe_error_flag, %function
	.p2align 2
qbe_error_flag:
	mrc p15, 0, r2, c13, c0, 3
	ldr r0, [r2, #8]
	ldr r1, [r2, #12]
	bx lr

	.globl qbe_error_set
	.type qbe_error_set, %function
	.p2align 2
qbe_error_set:
	mrc p15, 0, r2, c13, c0, 3
	str r0, [r2]
	str r1, [r2, #4]
	mov r3, #1
	str r3, [r2, #8]
	mov r3, #0
	str r3, [r2, #12]
	mov r0, #0
	mov r1, #0
	bx lr

	.globl qbe_error_catch
	.type qbe_error_catch, %function
	.p2align 2
qbe_error_catch:
	mrc p15, 0, r2, c13, c0, 3
	mov r0, #0
	str r0, [r2, #8]
	str r0, [r2, #12]
	mov r1, #0
	bx lr

	.globl qbe_error_clear
	.type qbe_error_clear, %function
	.p2align 2
qbe_error_clear:
	mrc p15, 0, r2, c13, c0, 3
	mov r0, #0
	str r0, [r2]
	str r0, [r2, #4]
	str r0, [r2, #8]
	str r0, [r2, #12]
	mov r1, #0
	bx lr

// lsl_arch_clone_thread(flags, zásobník, ctid, tls) -> tid nebo -errno.
// Argumenty jsou 64bitová slova: flags v r0:r1, zásobník v r2:r3, ctid na
// [sp], tls na [sp+8]. ARM clone má pořadí (flags, stack, ptid, tls, ctid).
// Potomek najde na novém zásobníku položku a funkci (dvě 64bitová slova)
// a zavolá lsl_thread_main(položka, funkce).
	.globl lsl_arch_clone_thread
	.type lsl_arch_clone_thread, %function
	.p2align 2
lsl_arch_clone_thread:
	push {r4, r5, r7, lr}
	mov r1, r2
	ldr r3, [sp, #24]
	ldr r4, [sp, #16]
	mov r2, #0
	mov r7, #120
	svc #0
	cmp r0, #0
	beq 1f
	asr r1, r0, #31
	pop {r4, r5, r7, pc}
1:	mov fp, #0
	mov lr, #0
	ldr r0, [sp]
	ldr r1, [sp, #4]
	ldr r2, [sp, #8]
	ldr r3, [sp, #12]
	bl lsl_thread_main
	udf #0

// Návrat ze signálu: bez SA_SIGINFO staví jádro ARM starý rámec, proto
// sigreturn (119), ne rt_sigreturn.
	.globl lsl_arch_signal_restorer
	.type lsl_arch_signal_restorer, %function
	.p2align 2
lsl_arch_signal_restorer:
	mov r7, #119
	svc #0

// Start procesu: vrchol zásobníku (argc) jako 64bitové slovo.
	.globl _start
	.type _start, %function
	.p2align 2
_start:
	mov r0, sp
	mov r1, #0
	bic sp, sp, #7
	mov fp, #0
	mov lr, #0
	bl lsl_runtime_start
	udf #0

	.section .note.GNU-stack,"",%progbits
