# Vrstva architektury pro bare metal riscv64 (RV64GC, M-mód, LP64D): jediné
# místo runtime s instrukcemi tohoto CPU. Start na hartu 0 (ostatní harty
# spí), zásobník a past z linker skriptu baremetal_riscv64.ld, semihosting
# (ARM/RISC-V) pro hostitelský vstup a výstup, je-li k dispozici.
	.option norelax

# Start: deska skočí na začátek obrazu (qemu virt -bios none: 0x80000000)
# s a0 = mhartid a a1 = adresa stromu zařízení (FDT).
	.section .text.start, "ax", @progbits
	.globl _start
_start:
	csrr t0, mhartid
	bnez t0, 3f
	la sp, lsl_stack_top
	la t0, lsl_trap
	csrw mtvec, t0
	la t0, lsl_trap_save
	csrw mscratch, t0
	# FPU zapnutá (mstatus.FS = Initial), zaokrouhlení k nejbližšímu.
	li t0, 0x2000
	csrs mstatus, t0
	fscsr zero
	la t0, lsl_fdt
	sd a1, 0(t0)
	la t0, __bss_start
	la t1, __bss_end
1:	bgeu t0, t1, 2f
	sd zero, 0(t0)
	addi t0, t0, 8
	j 1b
2:	# Zkouška semihostingu: bez debuggeru/hostitele skončí v pasti, která
	# nastaví lsl_semihost_absent.
	li a0, 0x13
	li a1, 0
	call lsl_arch_semihost
	mv a0, sp
	li ra, 0
	li s0, 0
	call lsl_runtime_start
3:	wfi
	j 3b

	.text
# lsl_arch_semihost(operace, parametr) -> výsledek: volání semihostingu
# (sekvence slli/ebreak/srai nesmí být komprimovaná ani přes hranici stránky).
	.globl lsl_arch_semihost
	.p2align 4
lsl_arch_semihost:
	.option push
	.option norvc
	slli zero, zero, 0x1f
	ebreak
	srai zero, zero, 7
	.option pop
	ret

# lsl_arch_entropy16() -> 16 bitů entropie z CSR seed (rozšíření Zkr), nebo
# -1, když ho CPU nemá (past nastaví lsl_seed_absent) nebo hlásí poruchu.
	.globl lsl_arch_entropy16
	.p2align 4
lsl_arch_entropy16:
	la a1, lsl_seed_absent
	ld a1, 0(a1)
	bnez a1, 2f
1:
lsl_arch_seed_read:
	csrrw a0, 0x015, zero
	srli a1, a0, 30
	andi a1, a1, 3
	li a2, 2
	beq a1, a2, 3f
	li a2, 3
	beq a1, a2, 2f
	# BIST nebo WAIT: zdroj se teprve plní.
	j 1b
2:	li a0, -1
	ret
3:	slli a0, a0, 48
	srli a0, a0, 48
	ret

# Past M-módu. ebreak semihostingu bez hostitele: a0 = -1, pokračuje se za
# sekvencí a lsl_semihost_absent = 1; obdobně neplatná instrukce čtení CSR
# seed bez Zkr (lsl_seed_absent = 1). Jiná past: lsl_baremetal_fault
# (os_baremetal) na vlastním zásobníku vypíše příčinu a ukončí program.
	.p2align 2
lsl_trap:
	csrrw t0, mscratch, t0
	sd t1, 0(t0)
	sd t2, 8(t0)
	sd t3, 16(t0)
	csrr t1, mcause
	li t2, 2
	bne t1, t2, 4f
	csrr t1, mepc
	la t2, lsl_arch_seed_read
	bne t1, t2, 1f
	addi t1, t1, 4
	csrw mepc, t1
	li a0, 1
	la t1, lsl_seed_absent
	sd a0, 0(t1)
	li a0, -1
	ld t1, 0(t0)
	ld t2, 8(t0)
	ld t3, 16(t0)
	csrrw t0, mscratch, t0
	mret
4:	li t2, 3
	bne t1, t2, 1f
	csrr t1, mepc
	lwu t2, -4(t1)
	li t3, 0x01f01013
	bne t2, t3, 1f
	lwu t2, 4(t1)
	li t3, 0x40705013
	bne t2, t3, 1f
	addi t1, t1, 8
	csrw mepc, t1
	li a0, 1
	la t1, lsl_semihost_absent
	sd a0, 0(t1)
	li a0, -1
	ld t1, 0(t0)
	ld t2, 8(t0)
	ld t3, 16(t0)
	csrrw t0, mscratch, t0
	mret
1:	la sp, lsl_trap_stack_top
	csrr a0, mcause
	csrr a1, mepc
	csrr a2, mtval
	li ra, 0
	li s0, 0
	call lsl_baremetal_fault
2:	wfi
	j 2b

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

# Jeden hart: fence.i stačí.
	.globl lsl_arch_sync_code
	.p2align 4
lsl_arch_sync_code:
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

	.globl lsl_arch_thread_pointer
	.p2align 4
lsl_arch_thread_pointer:
	mv a0, tp
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

	.data
	.p2align 3
	.globl lsl_fdt
lsl_fdt:
	.zero 8
	.globl lsl_semihost_absent
lsl_semihost_absent:
	.zero 8
lsl_seed_absent:
	.zero 8
lsl_trap_save:
	.zero 32

	.bss
	.p2align 3
	.globl lsl_state
lsl_state:
	.zero 8
	.globl lsl_baremetal_state
lsl_baremetal_state:
	.zero 64
