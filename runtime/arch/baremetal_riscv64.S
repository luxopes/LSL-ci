# Vrstva architektury pro bare metal riscv64 (RV64GC, LP64D): jediné místo
# runtime s instrukcemi tohoto CPU.
# - M-mód: start všech hartů, ochrana PMP (S-mód smí celou paměť),
#   delegace výjimek a přerušení do S-módu a malá služba podle SBI: ecall
#   a7 = 0 nastaví časovač (mtimecmp), a7 = 1 pošle IPI hartu a0. Přerušení
#   časovače a IPI z CLINT předá jako STIP/SSIP.
# - S-mód: program se stránkováním Sv39 (os_baremetal.lsl). Past lsl_strap
#   uloží celý kontext vlákna do jeho TCB, zavolá lsl_baremetal_trap na
#   zásobníku pasti hartu a obnoví kontext TCB, který plánovač vrátí.
# TCB: x_i na 8*i, f_i na 256+8*i, fcsr +512, pc +520, sstatus +528, dál
# údaje plánovače (os_baremetal.lsl, TCB_BYTES). Blok hartu (sscratch):
# +0 aktuální TCB, +8 úschova t5, +16 vrchol zásobníku pasti, +24 mhartid.
	.option norelax

	.equ MAX_HARTS, 8
	.equ TCB_BYTES, 704
	.equ HART_BYTES, 64
	.equ TRAP_STACK, 20480

# Start: deska skočí na začátek obrazu (qemu virt -bios none: 0x80000000)
# na všech hartech s a0 = mhartid a a1 = adresa stromu zařízení (FDT).
	.section .text.start, "ax", @progbits
	.globl _start
_start:
	csrr t0, mhartid
	li t1, MAX_HARTS
	bgeu t0, t1, 9f
	# Zásobník M-módu (1 KiB na hart) je v mscratch.
	la sp, lsl_mstacks
	addi t1, t0, 1
	slli t1, t1, 10
	add sp, sp, t1
	csrw mscratch, sp
	la t1, lsl_mtrap
	csrw mtvec, t1
	# PMP: S-mód smí celou paměť (NAPOT přes celý prostor, RWX).
	li t1, -1
	csrw pmpaddr0, t1
	li t1, 0x1f
	csrw pmpcfg0, t1
	# Výjimky kromě ecall z S-módu a přerušení S-módu řeší S-mód.
	li t1, 0xb1ff
	csrw medeleg, t1
	li t1, 0x222
	csrw mideleg, t1
	# S-mód smí číst time, cycle a instret.
	li t1, 7
	csrw mcounteren, t1
	# Časovač a IPI pro M-mód (předávají se do S-módu).
	li t1, 0x88
	csrw mie, t1
	# FPU zapnutá (FS = Initial).
	li t1, 0x2000
	csrs mstatus, t1
	bnez t0, 5f
	# Hart 0: FDT, nulování bss, zkouška CSR seed (Zkr: S-mód smí číst
	# seed jen s mseccfg.SSEED; bez Zkr past nastaví lsl_seed_absent).
	la t2, lsl_fdt
	sd a1, 0(t2)
	la t2, __bss_start
	la t3, __bss_end
1:	bgeu t2, t3, 2f
	sd zero, 0(t2)
	addi t2, t2, 8
	j 1b
2:	li t1, 0x200
lsl_seed_probe:
	csrs 0x747, t1
	la t2, lsl_s_start
	j 6f
	# Ostatní harty čekají, až hart 0 připraví stránkování a plánovač.
5:	la t2, lsl_harts_go
3:	ld t3, 0(t2)
	bnez t3, 4f
	nop
	j 3b
4:	la t2, lsl_s_secondary
6:	# Přechod do S-módu (MPP = 01) na adrese t2, a0 = mhartid.
	csrw mepc, t2
	li t1, 0x1800
	csrc mstatus, t1
	li t1, 0x800
	csrs mstatus, t1
	mv a0, t0
	mret
9:	wfi
	j 9b

	.text
# Past M-módu (vlastní zásobník z mscratch).
	.p2align 2
lsl_mtrap:
	csrrw sp, mscratch, sp
	addi sp, sp, -32
	sd t0, 0(sp)
	sd t1, 8(sp)
	sd t2, 16(sp)
	sd t3, 24(sp)
	csrr t0, mcause
	bltz t0, 3f
	li t1, 9
	beq t0, t1, 1f
	# Neplatná instrukce při zkoušce CSR seed: Zkr chybí.
	li t1, 2
	bne t0, t1, 8f
	csrr t1, mepc
	la t2, lsl_seed_probe
	bne t1, t2, 8f
	addi t1, t1, 4
	csrw mepc, t1
	la t2, lsl_seed_absent
	li t3, 1
	sd t3, 0(t2)
	j 7f
	# ecall z S-módu.
1:	csrr t1, mepc
	addi t1, t1, 4
	csrw mepc, t1
	la t1, lsl_clint
	ld t1, 0(t1)
	bnez a7, 2f
	# Časovač: mtimecmp[hart] = a0, zrušit čekající STIP, povolit MTIE.
	csrr t2, mhartid
	slli t2, t2, 3
	add t2, t2, t1
	li t3, 0x4000
	add t2, t2, t3
	sd a0, 0(t2)
	li t2, 0x20
	csrc mip, t2
	li t2, 0x80
	csrs mie, t2
	j 7f
	# IPI: msip[a0] = 1.
2:	slli t2, a0, 2
	add t2, t2, t1
	li t3, 1
	sw t3, 0(t2)
	j 7f
3:	slli t0, t0, 1
	srli t0, t0, 1
	li t1, 7
	bne t0, t1, 4f
	# Časovač M: předat jako STIP, MTIE vypnout do dalšího nastavení.
	li t2, 0x80
	csrc mie, t2
	li t2, 0x20
	csrs mip, t2
	j 7f
4:	li t1, 3
	bne t0, t1, 7f
	# IPI: zrušit msip a předat jako SSIP.
	la t1, lsl_clint
	ld t1, 0(t1)
	csrr t2, mhartid
	slli t2, t2, 2
	add t2, t2, t1
	sw zero, 0(t2)
	li t2, 2
	csrs mip, t2
7:	ld t0, 0(sp)
	ld t1, 8(sp)
	ld t2, 16(sp)
	ld t3, 24(sp)
	addi sp, sp, 32
	csrrw sp, mscratch, sp
	mret
	# Jiná past v M-módu je chyba runtime: konec se stavem 70 (sifive_test).
8:	la t1, lsl_test_device
	ld t1, 0(t1)
	beqz t1, 9f
	li t2, (70 << 16) | 0x3333
	sw t2, 0(t1)
9:	wfi
	j 9b

# S-mód, hart 0: blok hartu 0 s TCB hlavního vlákna, past, zkouška
# semihostingu, pak lsl_runtime_start na hlavním zásobníku.
lsl_s_start:
	la t0, lsl_harts
	csrw sscratch, t0
	la t1, lsl_tcbs
	sd t1, 0(t0)
	la t1, lsl_trap_stacks + TRAP_STACK
	sd t1, 16(t0)
	sd a0, 24(t0)
	la t1, lsl_strap
	csrw stvec, t1
	la sp, lsl_stack_top
	# Bez debuggeru/hostitele skončí ebreak v pasti, která nastaví
	# lsl_semihost_absent.
	li a0, 0x13
	li a1, 0
	call lsl_arch_semihost
	mv a0, sp
	li ra, 0
	li s0, 0
	call lsl_runtime_start
1:	wfi
	j 1b

# S-mód, další harty: pořadí přihlášení určí blok hartu, TCB nečinnosti
# a zásobník pasti; stránkování podle hartu 0 (lsl_satp).
lsl_s_secondary:
	la t0, lsl_hart_count
	li t1, 1
	amoadd.d.aqrl t2, t1, (t0)
	li t1, MAX_HARTS
	bgeu t2, t1, 2f
	li t1, HART_BYTES
	mul t3, t2, t1
	la t0, lsl_harts
	add t0, t0, t3
	csrw sscratch, t0
	li t1, TCB_BYTES
	mul t3, t2, t1
	la t1, lsl_idle_tcbs
	add t1, t1, t3
	sd t1, 0(t0)
	li t1, TRAP_STACK
	addi t3, t2, 1
	mul t3, t3, t1
	la t1, lsl_trap_stacks
	add t1, t1, t3
	sd t1, 16(t0)
	sd a0, 24(t0)
	la t1, lsl_strap
	csrw stvec, t1
	la t1, lsl_satp
	ld t1, 0(t1)
	csrw satp, t1
	sfence.vma
	ld sp, 16(t0)
	mv a0, t0
	li ra, 0
	li s0, 0
	call lsl_baremetal_secondary
	# Nečinnost s povolenými přerušeními (SIE, STIE + SSIE).
	li t1, 0x22
	csrs sie, t1
	csrsi sstatus, 2
	j lsl_arch_idle
2:	wfi
	j 2b

# Nečinnost hartu: nepoužívá zásobník (past ho přepíše).
	.globl lsl_arch_idle
	.p2align 2
lsl_arch_idle:
	wfi
	j lsl_arch_idle

# Past S-módu: kontext do aktuálního TCB, plánovač, kontext vybraného TCB.
	.p2align 2
lsl_strap:
	csrrw t6, sscratch, t6
	sd t5, 8(t6)
	ld t5, 0(t6)
	sd x1, 8(t5)
	sd x2, 16(t5)
	sd x3, 24(t5)
	sd x4, 32(t5)
	sd x5, 40(t5)
	sd x6, 48(t5)
	sd x7, 56(t5)
	sd x8, 64(t5)
	sd x9, 72(t5)
	sd x10, 80(t5)
	sd x11, 88(t5)
	sd x12, 96(t5)
	sd x13, 104(t5)
	sd x14, 112(t5)
	sd x15, 120(t5)
	sd x16, 128(t5)
	sd x17, 136(t5)
	sd x18, 144(t5)
	sd x19, 152(t5)
	sd x20, 160(t5)
	sd x21, 168(t5)
	sd x22, 176(t5)
	sd x23, 184(t5)
	sd x24, 192(t5)
	sd x25, 200(t5)
	sd x26, 208(t5)
	sd x27, 216(t5)
	sd x28, 224(t5)
	sd x29, 232(t5)
	ld t4, 8(t6)
	sd t4, 240(t5)
	csrr t4, sscratch
	sd t4, 248(t5)
	csrw sscratch, t6
	fsd f0, 256(t5)
	fsd f1, 264(t5)
	fsd f2, 272(t5)
	fsd f3, 280(t5)
	fsd f4, 288(t5)
	fsd f5, 296(t5)
	fsd f6, 304(t5)
	fsd f7, 312(t5)
	fsd f8, 320(t5)
	fsd f9, 328(t5)
	fsd f10, 336(t5)
	fsd f11, 344(t5)
	fsd f12, 352(t5)
	fsd f13, 360(t5)
	fsd f14, 368(t5)
	fsd f15, 376(t5)
	fsd f16, 384(t5)
	fsd f17, 392(t5)
	fsd f18, 400(t5)
	fsd f19, 408(t5)
	fsd f20, 416(t5)
	fsd f21, 424(t5)
	fsd f22, 432(t5)
	fsd f23, 440(t5)
	fsd f24, 448(t5)
	fsd f25, 456(t5)
	fsd f26, 464(t5)
	fsd f27, 472(t5)
	fsd f28, 480(t5)
	fsd f29, 488(t5)
	fsd f30, 496(t5)
	fsd f31, 504(t5)
	frcsr t4
	sd t4, 512(t5)
	csrr t4, sepc
	sd t4, 520(t5)
	csrr t4, sstatus
	sd t4, 528(t5)
	ld sp, 16(t6)
	mv a3, t5
	mv a4, t6
	csrr a0, scause
	csrr a1, sepc
	csrr a2, stval
	li ra, 0
	li s0, 0
	call lsl_baremetal_trap
	mv t6, a0
	ld t4, 520(t6)
	csrw sepc, t4
	ld t4, 528(t6)
	csrw sstatus, t4
	ld t4, 512(t6)
	fscsr t4
	fld f0, 256(t6)
	fld f1, 264(t6)
	fld f2, 272(t6)
	fld f3, 280(t6)
	fld f4, 288(t6)
	fld f5, 296(t6)
	fld f6, 304(t6)
	fld f7, 312(t6)
	fld f8, 320(t6)
	fld f9, 328(t6)
	fld f10, 336(t6)
	fld f11, 344(t6)
	fld f12, 352(t6)
	fld f13, 360(t6)
	fld f14, 368(t6)
	fld f15, 376(t6)
	fld f16, 384(t6)
	fld f17, 392(t6)
	fld f18, 400(t6)
	fld f19, 408(t6)
	fld f20, 416(t6)
	fld f21, 424(t6)
	fld f22, 432(t6)
	fld f23, 440(t6)
	fld f24, 448(t6)
	fld f25, 456(t6)
	fld f26, 464(t6)
	fld f27, 472(t6)
	fld f28, 480(t6)
	fld f29, 488(t6)
	fld f30, 496(t6)
	fld f31, 504(t6)
	ld x1, 8(t6)
	ld x2, 16(t6)
	ld x3, 24(t6)
	ld x4, 32(t6)
	ld x5, 40(t6)
	ld x6, 48(t6)
	ld x7, 56(t6)
	ld x8, 64(t6)
	ld x9, 72(t6)
	ld x10, 80(t6)
	ld x11, 88(t6)
	ld x12, 96(t6)
	ld x13, 104(t6)
	ld x14, 112(t6)
	ld x15, 120(t6)
	ld x16, 128(t6)
	ld x17, 136(t6)
	ld x18, 144(t6)
	ld x19, 152(t6)
	ld x20, 160(t6)
	ld x21, 168(t6)
	ld x22, 176(t6)
	ld x23, 184(t6)
	ld x24, 192(t6)
	ld x25, 200(t6)
	ld x26, 208(t6)
	ld x27, 216(t6)
	ld x28, 224(t6)
	ld x29, 232(t6)
	ld x30, 240(t6)
	ld x31, 248(t6)
	sret

# Služby pro vrstvu OS.
# lsl_arch_request(tcb): požadavek (TCB +REQUEST) obslouží past SSIP;
# vrátí se, až ho plánovač vynuluje (vlákno mezitím mohlo čekat).
	.globl lsl_arch_request
	.p2align 4
lsl_arch_request:
	csrsi sip, 2
1:	ld t0, 576(a0)
	bnez t0, 1b
	li a0, 0
	ret

# lsl_arch_irq_save() -> předchozí SIE (2 nebo 0), přerušení vypnutá.
	.globl lsl_arch_irq_save
	.p2align 4
lsl_arch_irq_save:
	csrrci a0, sstatus, 2
	andi a0, a0, 2
	ret

	.globl lsl_arch_irq_restore
	.p2align 4
lsl_arch_irq_restore:
	csrs sstatus, a0
	li a0, 0
	ret

# Aktuální TCB (blok hartu v sscratch) bez přerušení: vlákno se mezitím
# nepřesune na jiný hart.
	.globl lsl_arch_current_tcb
	.p2align 4
lsl_arch_current_tcb:
	csrrci t0, sstatus, 2
	csrr a0, sscratch
	ld a0, 0(a0)
	andi t0, t0, 2
	csrs sstatus, t0
	ret

	.globl lsl_arch_clear_soft
	.p2align 4
lsl_arch_clear_soft:
	csrci sip, 2
	li a0, 0
	ret

# lsl_arch_set_timer(čas): ecall do M-módu.
	.globl lsl_arch_set_timer
	.p2align 4
lsl_arch_set_timer:
	li a7, 0
	ecall
	li a0, 0
	ret

# lsl_arch_send_ipi(mhartid).
	.globl lsl_arch_send_ipi
	.p2align 4
lsl_arch_send_ipi:
	li a7, 1
	ecall
	li a0, 0
	ret

	.globl lsl_arch_time
	.p2align 4
lsl_arch_time:
	rdtime a0
	ret

# Zapne stránkování na tomto hartu (satp) a povolí přerušení S-módu.
	.globl lsl_arch_enable_paging
	.p2align 4
lsl_arch_enable_paging:
	la t0, lsl_satp
	sd a0, 0(t0)
	sfence.vma
	csrw satp, a0
	sfence.vma
	li t1, 0x22
	csrs sie, t1
	csrsi sstatus, 2
	li a0, 0
	ret

	.globl lsl_arch_flush_page
	.p2align 4
lsl_arch_flush_page:
	sfence.vma a0, zero
	li a0, 0
	ret

# Sonda zásobníku: čtení stránek pod sp (namapuje je dřív, než vrstva OS
# vezme zámek, v jehož kritické sekci nesmí přijít výpadek stránky).
	.globl lsl_arch_stack_probe
	.p2align 4
lsl_arch_stack_probe:
	li t1, 4096
	mv t0, sp
	li t2, 4
1:	sub t0, t0, t1
	ld zero, 0(t0)
	addi t2, t2, -1
	bnez t2, 1b
	li a0, 0
	ret

# Vstup nového vlákna (TCB: a0 = položka tabulky, a1 = funkce).
	.globl lsl_arch_thread_entry
	.p2align 4
lsl_arch_thread_entry:
	li ra, 0
	li s0, 0
	call lsl_thread_main
1:	j 1b

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

# lsl_arch_entropy16() -> 16 bitů entropie z CSR seed (Zkr), nebo -1.
	.globl lsl_arch_entropy16
	.p2align 4
lsl_arch_entropy16:
	la a1, lsl_seed_absent
	ld a1, 0(a1)
	bnez a1, 2f
1:	csrrw a0, 0x015, zero
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

# Kód se za běhu nemění (fence.i jen pro úplnost rozhraní).
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
	.globl lsl_seed_absent
lsl_seed_absent:
	.zero 8
# Adresy zařízení pro M-mód (os_baremetal je přepíše podle FDT).
	.globl lsl_clint
lsl_clint:
	.dword 0x2000000
	.globl lsl_test_device
lsl_test_device:
	.dword 0x100000
	.globl lsl_harts_go
lsl_harts_go:
	.zero 8
	.globl lsl_hart_count
lsl_hart_count:
	.dword 1
	.globl lsl_satp
lsl_satp:
	.zero 8

	.bss
	.p2align 12
	.globl lsl_tcbs
lsl_tcbs:
	.zero 129 * TCB_BYTES
	.globl lsl_idle_tcbs
lsl_idle_tcbs:
	.zero MAX_HARTS * TCB_BYTES
	.globl lsl_harts
lsl_harts:
	.zero MAX_HARTS * HART_BYTES
lsl_mstacks:
	.zero (MAX_HARTS + 1) * 1024
	.p2align 3
	.globl lsl_state
lsl_state:
	.zero 8
	.globl lsl_baremetal_state
lsl_baremetal_state:
	.zero 256
	.globl lsl_baremetal_descriptors
lsl_baremetal_descriptors:
	.zero 64 * 16
