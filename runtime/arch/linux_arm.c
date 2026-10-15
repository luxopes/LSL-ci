/* Vrstva architektury pro Linux ARM (armv7-a, EABI, hard-float), 32 bitů:
 * jediné místo runtime s instrukcemi a systémovými voláními tohoto CPU.
 * Stejné funkce jako linux_arm64.S. Runtime se pro tento cíl překládá přes
 * C (LuxIR c32): parametry a výsledky jsou 64bitová slova LuxIR (uint64_t),
 * ukazatele v nich zabírají dolních 32 bitů.
 *
 * Blok vlákna runtime je tam, kam ukazuje TPIDRURO (čtení mrc p15 c13 c0 3);
 * hlavní vlákno ho nastaví voláním set_tls, nová vlákna CLONE_SETTLS. */
#include <stdint.h>

#define LSL_ARCH __attribute__((used))

uint64_t lsl_state __asm__("lsl_state") = 0;

static inline uintptr_t
thread_block(void)
{
	uintptr_t value;

	__asm__ volatile("mrc p15, 0, %0, c13, c0, 3" : "=r"(value));
	return value;
}

/* Výsledek jádra: -4095..-1 je chyba (záporné errno, rozšíří se znaménkem),
 * vše ostatní je nezáporná hodnota (i adresa nad 2 GiB). */
static inline uint64_t
kernel_result(uint32_t value)
{
	if (value >= 0xfffff001u)
		return (uint64_t)(int64_t)(int32_t)value;
	return value;
}

LSL_ARCH uint64_t
lsl_arch_syscall6(uint64_t number, uint64_t a, uint64_t b, uint64_t c, uint64_t d, uint64_t e, uint64_t f)
{
	register uint32_t r7 __asm__("r7") = (uint32_t)number;
	register uint32_t r0 __asm__("r0") = (uint32_t)a;
	register uint32_t r1 __asm__("r1") = (uint32_t)b;
	register uint32_t r2 __asm__("r2") = (uint32_t)c;
	register uint32_t r3 __asm__("r3") = (uint32_t)d;
	register uint32_t r4 __asm__("r4") = (uint32_t)e;
	register uint32_t r5 __asm__("r5") = (uint32_t)f;

	__asm__ volatile("svc #0" : "+r"(r0) : "r"(r7), "r"(r1), "r"(r2), "r"(r3), "r"(r4), "r"(r5) : "memory");
	return kernel_result(r0);
}

LSL_ARCH uint64_t
lsl_arch_syscall3(uint64_t number, uint64_t a, uint64_t b, uint64_t c)
{
	return lsl_arch_syscall6(number, a, b, c, 0, 0, 0);
}

/* Atomické operace nad 64bitovým slovem (ldrexd/strexd, sekvenčně
 * konzistentní). */
LSL_ARCH uint64_t
lsl_arch_cas64(uint64_t address, uint64_t expected, uint64_t value)
{
	uint64_t *word = (uint64_t *)(uintptr_t)address;

	__atomic_compare_exchange_n(word, &expected, value, 0, __ATOMIC_SEQ_CST, __ATOMIC_SEQ_CST);
	return expected;
}

LSL_ARCH uint64_t
lsl_arch_xchg64(uint64_t address, uint64_t value)
{
	return __atomic_exchange_n((uint64_t *)(uintptr_t)address, value, __ATOMIC_SEQ_CST);
}

LSL_ARCH uint64_t
lsl_arch_add64(uint64_t address, uint64_t value)
{
	return __atomic_fetch_add((uint64_t *)(uintptr_t)address, value, __ATOMIC_SEQ_CST);
}

LSL_ARCH uint64_t
lsl_arch_pause(void)
{
	__asm__ volatile("yield");
	return 0;
}

/* lsl_arch_sync_code(adresa, délka): zapsaný kód do instrukční cache přes
 * soukromé volání ARM cacheflush (0xf0002). */
LSL_ARCH uint64_t
lsl_arch_sync_code(uint64_t address, uint64_t length)
{
	lsl_arch_syscall6(0xf0002, address, address + length, 0, 0, 0, 0);
	return 0;
}

/* lsl_arch_sqrt(bity) -> bity: odmocnina binary64 podle IEEE 754 (vsqrt). */
LSL_ARCH uint64_t
lsl_arch_sqrt(uint64_t bits)
{
	double value;

	__builtin_memcpy(&value, &bits, 8);
	value = __builtin_sqrt(value);
	__builtin_memcpy(&bits, &value, 8);
	return bits;
}

/* lsl_arch_spill(buffer 96 B) -> ukazatel zásobníku; uloží callee-saved
 * registry r4-r11 pro konzervativní GC (po 4 bajtech, jako zásobník). */
__asm__(
	".text\n.arm\n.globl lsl_arch_spill\n.type lsl_arch_spill,%function\n.p2align 2\n"
	"lsl_arch_spill:\n"
	"	stm r0, {r4-r11}\n"
	"	mov r0, sp\n"
	"	mov r1, #0\n"
	"	bx lr\n");

LSL_ARCH uint64_t
lsl_arch_tls_load(uint64_t offset)
{
	uint64_t value;

	__builtin_memcpy(&value, (void *)(thread_block() + (uintptr_t)offset), 8);
	return value;
}

LSL_ARCH uint64_t
lsl_arch_tls_store(uint64_t offset, uint64_t value)
{
	__builtin_memcpy((void *)(thread_block() + (uintptr_t)offset), &value, 8);
	return 0;
}

/* set_tls (__ARM_NR_set_tls = 0xf0005) nastaví TPIDRURO volajícího vlákna. */
LSL_ARCH uint64_t
lsl_arch_set_thread_pointer(uint64_t block)
{
	return lsl_arch_syscall6(0xf0005, block, 0, 0, 0, 0, 0);
}

LSL_ARCH uint64_t
qbe_error_flag(void)
{
	return lsl_arch_tls_load(8);
}

LSL_ARCH uint64_t
qbe_error_set(uint64_t error)
{
	lsl_arch_tls_store(0, error);
	lsl_arch_tls_store(8, 1);
	return 0;
}

LSL_ARCH uint64_t
qbe_error_catch(void)
{
	lsl_arch_tls_store(8, 0);
	return 0;
}

LSL_ARCH uint64_t
qbe_error_clear(void)
{
	lsl_arch_tls_store(0, 0);
	lsl_arch_tls_store(8, 0);
	return 0;
}

/* lsl_arch_clone_thread(flags, zásobník, ctid, tls) -> tid nebo -errno.
 * Argumenty jsou 64bitová slova: flags v r0:r1, zásobník v r2:r3, ctid na
 * [sp], tls na [sp+8]. ARM clone má pořadí (flags, stack, ptid, tls, ctid).
 * Potomek najde na novém zásobníku položku a funkci (dvě 64bitová slova)
 * a zavolá lsl_thread_main(položka, funkce). */
__asm__(
	".text\n.arm\n.globl lsl_arch_clone_thread\n.type lsl_arch_clone_thread,%function\n.p2align 2\n"
	"lsl_arch_clone_thread:\n"
	"	push {r4, r5, r7, lr}\n"
	"	mov r1, r2\n"
	"	ldr r3, [sp, #24]\n"
	"	ldr r4, [sp, #16]\n"
	"	mov r2, #0\n"
	"	mov r7, #120\n"
	"	svc #0\n"
	"	cmp r0, #0\n"
	"	beq 1f\n"
	"	asr r1, r0, #31\n"
	"	pop {r4, r5, r7, pc}\n"
	"1:	mov fp, #0\n"
	"	mov lr, #0\n"
	"	ldr r0, [sp]\n"
	"	ldr r1, [sp, #4]\n"
	"	ldr r2, [sp, #8]\n"
	"	ldr r3, [sp, #12]\n"
	"	bl lsl_thread_main\n"
	"	udf #0\n"
	/* návrat ze signálu: bez SA_SIGINFO staví jádro ARM starý rámec, proto sigreturn (119), ne rt_sigreturn */
	".globl lsl_arch_signal_restorer\n.type lsl_arch_signal_restorer,%function\n.p2align 2\n"
	"lsl_arch_signal_restorer:\n"
	"	mov r7, #119\n"
	"	svc #0\n"
	/* start procesu: vrchol zásobníku (argc) jako 64bitové slovo */
	".globl _start\n.type _start,%function\n.p2align 2\n"
	"_start:\n"
	"	mov r0, sp\n"
	"	mov r1, #0\n"
	"	bic sp, sp, #7\n"
	"	mov fp, #0\n"
	"	mov lr, #0\n"
	"	bl lsl_runtime_start\n"
	"	udf #0\n");
