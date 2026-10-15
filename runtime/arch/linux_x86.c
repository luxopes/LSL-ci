/* Vrstva architektury pro Linux x86 (i686, SSE2), 32 bitů: jediné místo
 * runtime s instrukcemi a systémovými voláními tohoto CPU. Stejné funkce
 * jako linux_x86_64.S. Runtime se pro tento cíl překládá přes C (LuxIR
 * c32): parametry a výsledky jsou 64bitová slova LuxIR (uint64_t, cdecl na
 * zásobníku, výsledek v edx:eax), ukazatele v nich zabírají dolních 32 bitů.
 *
 * Blok vlákna runtime je báze segmentu %gs: položka TLS v GDT ze
 * set_thread_area; nová vlákna dostanou vlastní položku se stejným číslem
 * přes CLONE_SETTLS (user_desc). */
#include <stdint.h>

#define LSL_ARCH __attribute__((used))

uint64_t lsl_state __asm__("lsl_state") = 0;
/* Číslo položky TLS v GDT (set_thread_area hlavního vlákna). */
uint32_t lsl_tls_entry __asm__("lsl_tls_entry") = 0xffffffffu;

/* Systémové volání přes int 0x80: číslo v eax, argumenty ebx, ecx, edx,
 * esi, edi, ebp. -4095..-1 je chyba (rozšíří se znaménkem), vše ostatní je
 * nezáporná hodnota (i adresa nad 2 GiB). Argumenty cdecl: číslo na 4(%esp),
 * a..f po 8 bajtech od 12(%esp); po uložení čtyř registrů o 16 dál. */
__asm__(
	".text\n.globl lsl_arch_syscall6\n.type lsl_arch_syscall6,@function\n.p2align 4\n"
	"lsl_arch_syscall6:\n"
	"	push %ebp\n	push %edi\n	push %esi\n	push %ebx\n"
	"	mov 20(%esp), %eax\n"
	"	mov 28(%esp), %ebx\n"
	"	mov 36(%esp), %ecx\n"
	"	mov 44(%esp), %edx\n"
	"	mov 52(%esp), %esi\n"
	"	mov 60(%esp), %edi\n"
	"	mov 68(%esp), %ebp\n"
	"	int $0x80\n"
	"	xor %edx, %edx\n"
	"	cmp $-4095, %eax\n"
	"	jb 1f\n"
	"	mov $-1, %edx\n"
	"1:	pop %ebx\n	pop %esi\n	pop %edi\n	pop %ebp\n"
	"	ret\n"
	/* lsl_arch_spill(buffer 96 B) -> ukazatel zásobníku; uloží callee-saved
	 * ebx, esi, edi, ebp pro konzervativní GC. */
	".globl lsl_arch_spill\n.type lsl_arch_spill,@function\n.p2align 4\n"
	"lsl_arch_spill:\n"
	"	mov 4(%esp), %eax\n"
	"	mov %ebx, (%eax)\n"
	"	mov %esi, 4(%eax)\n"
	"	mov %edi, 8(%eax)\n"
	"	mov %ebp, 12(%eax)\n"
	"	mov %esp, %eax\n"
	"	xor %edx, %edx\n"
	"	ret\n"
	/* lsl_arch_clone_thread(flags, zásobník, ctid, tls) -> tid nebo -errno.
	 * i386 clone: (flags, stack, ptid, user_desc, ctid). user_desc (16 B na
	 * zásobníku, jádro ho zkopíruje): stejná položka GDT, báze tls, limit
	 * 4 GiB po stránkách, 32bitový segment (příznaky 0x51). Potomek najde
	 * na novém zásobníku položku a funkci (dvě 64bitová slova) a zavolá
	 * lsl_thread_main(položka, funkce). */
	".globl lsl_arch_clone_thread\n.type lsl_arch_clone_thread,@function\n.p2align 4\n"
	"lsl_arch_clone_thread:\n"
	"	push %ebp\n	push %edi\n	push %esi\n	push %ebx\n"
	"	sub $16, %esp\n"
	"	mov lsl_tls_entry, %eax\n"
	"	mov %eax, (%esp)\n"
	"	mov 60(%esp), %eax\n"
	"	mov %eax, 4(%esp)\n"
	"	movl $0xfffff, 8(%esp)\n"
	"	movl $0x51, 12(%esp)\n"
	"	mov 36(%esp), %ebx\n"
	"	mov 44(%esp), %ecx\n"
	"	xor %edx, %edx\n"
	"	mov %esp, %esi\n"
	"	mov 52(%esp), %edi\n"
	"	mov $120, %eax\n"
	"	int $0x80\n"
	"	test %eax, %eax\n"
	"	jz 2f\n"
	"	add $16, %esp\n"
	"	mov %eax, %edx\n"
	"	sar $31, %edx\n"
	"	pop %ebx\n	pop %esi\n	pop %edi\n	pop %ebp\n"
	"	ret\n"
	"2:	xor %ebp, %ebp\n"
	"	mov (%esp), %eax\n"
	"	mov 4(%esp), %ebx\n"
	"	mov 8(%esp), %ecx\n"
	"	mov 12(%esp), %edx\n"
	"	push %edx\n	push %ecx\n	push %ebx\n	push %eax\n"
	"	call lsl_thread_main\n"
	"	ud2\n"
	/* návrat ze signálu: bez SA_SIGINFO staví jádro starý rámec, proto
	 * sigreturn (119) po odebrání čísla signálu */
	".globl lsl_arch_signal_restorer\n.type lsl_arch_signal_restorer,@function\n.p2align 4\n"
	"lsl_arch_signal_restorer:\n"
	"	pop %eax\n"
	"	mov $119, %eax\n"
	"	int $0x80\n"
	/* start procesu: vrchol zásobníku (argc) jako 64bitové slovo */
	".globl _start\n.type _start,@function\n.p2align 4\n"
	"_start:\n"
	"	xor %ebp, %ebp\n"
	"	mov %esp, %eax\n"
	"	and $-16, %esp\n"
	"	sub $8, %esp\n"
	"	push $0\n"
	"	push %eax\n"
	"	call lsl_runtime_start\n"
	"	ud2\n");

uint64_t lsl_arch_syscall6(uint64_t, uint64_t, uint64_t, uint64_t, uint64_t, uint64_t, uint64_t);

LSL_ARCH uint64_t
lsl_arch_syscall3(uint64_t number, uint64_t a, uint64_t b, uint64_t c)
{
	return lsl_arch_syscall6(number, a, b, c, 0, 0, 0);
}

/* Atomické operace nad 64bitovým slovem (lock cmpxchg8b). Slova runtime
 * jsou zarovnaná na 8 bajtů; bez toho by clang na i386 (zarovnání uint64_t
 * 4) volal libatomic. */
typedef uint64_t lsl_word __attribute__((aligned(8)));
LSL_ARCH uint64_t
lsl_arch_cas64(uint64_t address, uint64_t expected, uint64_t value)
{
	lsl_word *word = (lsl_word *)(uintptr_t)address;

	__atomic_compare_exchange_n(word, &expected, value, 0, __ATOMIC_SEQ_CST, __ATOMIC_SEQ_CST);
	return expected;
}

LSL_ARCH uint64_t
lsl_arch_xchg64(uint64_t address, uint64_t value)
{
	return __atomic_exchange_n((lsl_word *)(uintptr_t)address, value, __ATOMIC_SEQ_CST);
}

LSL_ARCH uint64_t
lsl_arch_add64(uint64_t address, uint64_t value)
{
	return __atomic_fetch_add((lsl_word *)(uintptr_t)address, value, __ATOMIC_SEQ_CST);
}

LSL_ARCH uint64_t
lsl_arch_pause(void)
{
	__asm__ volatile("pause");
	return 0;
}

/* x86 má koherentní instrukční cache. */
LSL_ARCH uint64_t
lsl_arch_sync_code(uint64_t address, uint64_t length)
{
	(void)address;
	(void)length;
	return 0;
}

/* lsl_arch_sqrt(bity) -> bity: odmocnina binary64 podle IEEE 754 (sqrtsd). */
LSL_ARCH uint64_t
lsl_arch_sqrt(uint64_t bits)
{
	double value;

	__builtin_memcpy(&value, &bits, 8);
	value = __builtin_sqrt(value);
	__builtin_memcpy(&bits, &value, 8);
	return bits;
}

LSL_ARCH uint64_t
lsl_arch_tls_load(uint64_t offset)
{
	uint32_t low, high;

	__asm__ volatile("movl %%gs:(%2), %0\n\tmovl %%gs:4(%2), %1" : "=&r"(low), "=&r"(high) : "r"((uint32_t)offset) : "memory");
	return ((uint64_t)high << 32) | low;
}

LSL_ARCH uint64_t
lsl_arch_tls_store(uint64_t offset, uint64_t value)
{
	__asm__ volatile("movl %0, %%gs:(%2)\n\tmovl %1, %%gs:4(%2)" : : "r"((uint32_t)value), "r"((uint32_t)(value >> 32)), "r"((uint32_t)offset) : "memory");
	return 0;
}

/* set_thread_area (243) s user_desc: položka GDT s bází bloku, pak %gs na
 * ni (selektor: číslo * 8 + RPL 3). */
LSL_ARCH uint64_t
lsl_arch_set_thread_pointer(uint64_t block)
{
	uint32_t desc[4];
	uint64_t result;
	uint32_t selector;

	desc[0] = lsl_tls_entry;
	desc[1] = (uint32_t)block;
	desc[2] = 0xfffff;
	desc[3] = 0x51;
	result = lsl_arch_syscall6(243, (uint32_t)(uintptr_t)desc, 0, 0, 0, 0, 0);
	if ((int64_t)result < 0)
		return result;
	lsl_tls_entry = desc[0];
	selector = desc[0] * 8 + 3;
	__asm__ volatile("movw %w0, %%gs" : : "r"(selector) : "memory");
	return 0;
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
