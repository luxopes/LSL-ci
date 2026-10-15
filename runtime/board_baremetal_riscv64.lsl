# lsl: runtime
# Deska bare metal riscv64 pro os_baremetal.lsl: zařízení ze stromu zařízení
# Funkce vrací 0/1 (ne výraz s and/or): běží i v pasti a před inicializací
# haldy, kde dynamická pravdivost runtime ještě nefunguje.
# (FDT), tabulky stránek Sv39, kontext vlákna v TCB a příčiny pastí.
# Vrstva architektury: runtime/arch/baremetal_riscv64.S.
load core

# Kontext v TCB (lsl_strap): x_i na 8*i, f_i na 256+8*i.
REGISTER_SP = 16
REGISTER_TP = 32
REGISTER_A0 = 80
REGISTER_A1 = 88
CONTEXT_FCSR = 512
CONTEXT_PC = 520
CONTEXT_STATUS = 528
# Registry, které GC prohledá u zastaveného vlákna (x0-x31, f0-f31).
REGISTER_BYTES = 512
# sstatus nového vlákna: SPP = S, SPIE (přerušení po sret), FS = Initial.
NEW_STATUS = 8480

# Příčiny pastí (scause): přerušení mají nejvyšší bit.
CAUSE_SOFTWARE = 1
CAUSE_TIMER = 5
CAUSE_BREAKPOINT = 3

# Výchozí zařízení (qemu virt), když je FDT nemá.
RAM_START = 2147483648
RAM_DEFAULT = 134217728
UART_DEFAULT = 268435456
CLINT_DEFAULT = 33554432
TEST_DEFAULT = 1048576
TIMEBASE_DEFAULT = 10000000

# Stav desky (lsl_baremetal_state +160): +0 začátek RAM, +8 konec RAM,
# +16 UART, +24 posun registrů UART, +32 frekvence time, +40 kořen tabulek.
BOARD = 160

# Sv39: V R W X A D; listy zařízení RW, kód RX, data jen pro čtení R.
PTE_VALID = 1
PTE_READ = 2
PTE_WRITE = 4
PTE_EXECUTE = 8
PTE_ACCESSED = 64
PTE_DIRTY = 128
PAGE = 4096
MEGA = 2097152
GIGA = 1073741824
# Identita pokrývá prvních 256 GiB (kladná polovina Sv39); oblast zásobníků
# vláken leží od 128 GiB, kde RAM ani zařízení nejsou.
IDENTITY_GIGAS = 128

function board_word(offset):
    return __lsl_qbe_load64(__lsl_symbol("lsl_baremetal_state") + BOARD + offset)
end

function set_board_word(offset, value):
    __lsl_qbe_store64(__lsl_symbol("lsl_baremetal_state") + BOARD + offset, value)
    return 0
end

function big32(address):
    return __lsl_qbe_shl(__lsl_qbe_load8(address), 24) | __lsl_qbe_shl(__lsl_qbe_load8(address + 1), 16) | __lsl_qbe_shl(__lsl_qbe_load8(address + 2), 8) | __lsl_qbe_load8(address + 3)
end

function clear(address, size):
    index = 0
    while index < size:
        __lsl_qbe_store64(address + index, 0)
        index += 8
    end
    return 0
end

function fdt_text_length(text):
    length = 0
    while __lsl_qbe_load8(text + length) != 0:
        length += 1
    end
    return length
end

# Číslo z buněk FDT (1 nebo 2 buňky po 32 bitech).
function cells_value(address, cells):
    if cells >= 2:
        return __lsl_qbe_shl(big32(address), 32) | big32(address + 4)
    end
    return big32(address)
end

# Začíná text prefixem (oba C řetězce)?
function starts_with(text, prefix):
    index = 0
    while __lsl_qbe_load8(prefix + index) != 0:
        if __lsl_qbe_load8(text + index) != __lsl_qbe_load8(prefix + index):
            return 0
        end
        index += 1
    end
    return 1
end

# Obsahuje seznam compatible (řetězce oddělené NUL) položku s prefixem?
function compatible_with(list, length, prefix):
    position = 0
    while position < length:
        if starts_with(list + position, prefix):
            return 1
        end
        position += fdt_text_length(list + position) + 1
    end
    return 0
end

function same_text(left, right):
    if starts_with(left, right) and __lsl_qbe_load8(left + fdt_text_length(right)) == 0:
        return 1
    end
    return 0
end

# Uzel FDT po END_NODE: frame je záznam uzlu (64 B), parent záznam rodiče.
# Záznam: +0 #address-cells, +8 #size-cells (pro potomky), +16 compatible,
# +24 délka compatible, +32 reg, +40 délka reg, +48 reg-shift, +56 jméno.
function node_done(frame, parent, depth):
    compatible = __lsl_qbe_load64(frame + 16)
    compatible_length = __lsl_qbe_load64(frame + 24)
    reg = __lsl_qbe_load64(frame + 32)
    reg_length = __lsl_qbe_load64(frame + 40)
    address_cells = __lsl_qbe_load64(parent)
    size_cells = __lsl_qbe_load64(parent + 8)
    if reg == 0 or reg_length < __lsl_qbe_shl(address_cells + size_cells, 2):
        return 0
    end
    start = cells_value(reg, address_cells)
    size = cells_value(reg + __lsl_qbe_shl(address_cells, 2), size_cells)
    name = __lsl_qbe_load64(frame + 56)
    if depth == 2 and starts_with(name, __lsl_address("memory") + 16):
        if start <= RAM_START and start + size > RAM_START:
            call set_board_word(0, start)
            call set_board_word(8, start + size)
        end
    elif compatible != 0:
        if compatible_with(compatible, compatible_length, __lsl_address("ns16550") + 16) and board_word(16) == 0:
            call set_board_word(16, start)
            call set_board_word(24, __lsl_qbe_load64(frame + 48))
        elif compatible_with(compatible, compatible_length, __lsl_address("sifive,test") + 16):
            __lsl_qbe_store64(__lsl_symbol("lsl_test_device"), start)
        elif compatible_with(compatible, compatible_length, __lsl_address("riscv,clint0") + 16) or compatible_with(compatible, compatible_length, __lsl_address("sifive,clint0") + 16):
            __lsl_qbe_store64(__lsl_symbol("lsl_clint"), start)
        end
    end
    return 0
end

# Zařízení desky ze stromu zařízení (adresa od M-módu v lsl_fdt). Chybějící
# položky zůstanou na hodnotách qemu virt.
function discover():
    call set_board_word(0, RAM_START)
    call set_board_word(8, RAM_START + RAM_DEFAULT)
    call set_board_word(16, 0)
    call set_board_word(24, 0)
    call set_board_word(32, TIMEBASE_DEFAULT)
    fdt = __lsl_qbe_load64(__lsl_symbol("lsl_fdt"))
    if fdt == 0 or big32(fdt) != 3490578157:
        call set_board_word(16, UART_DEFAULT)
        return 0
    end
    __lsl_qbe_store64(__lsl_symbol("lsl_test_device"), 0)
    position = fdt + big32(fdt + 8)
    strings = fdt + big32(fdt + 12)
    limit = position + big32(fdt + 36)
    frames = __lsl_qbe_alloc(2176)
    call clear(frames, 2176)
    # Kořen: výchozí #address-cells 2, #size-cells 1 (specifikace FDT).
    __lsl_qbe_store64(frames, 2)
    __lsl_qbe_store64(frames + 8, 1)
    depth = 0
    while position < limit:
        token = big32(position)
        if token == 1:
            name = position + 4
            depth += 1
            if depth > 32:
                break
            end
            frame = frames + __lsl_qbe_shl(depth, 6)
            __lsl_qbe_zero(frame, 64)
            __lsl_qbe_store64(frame, 2)
            __lsl_qbe_store64(frame + 8, 1)
            __lsl_qbe_store64(frame + 56, name)
            position = (name + fdt_text_length(name) + 4) & -4
        elif token == 2:
            if depth >= 1:
                call node_done(frames + __lsl_qbe_shl(depth, 6), frames + __lsl_qbe_shl(depth - 1, 6), depth)
            end
            depth -= 1
            position += 4
        elif token == 3:
            length = big32(position + 4)
            name = strings + big32(position + 8)
            value = position + 12
            frame = frames + __lsl_qbe_shl(depth, 6)
            if same_text(name, __lsl_address("#address-cells") + 16) and length >= 4:
                __lsl_qbe_store64(frame, big32(value))
            elif same_text(name, __lsl_address("#size-cells") + 16) and length >= 4:
                __lsl_qbe_store64(frame + 8, big32(value))
            elif same_text(name, __lsl_address("compatible") + 16):
                __lsl_qbe_store64(frame + 16, value)
                __lsl_qbe_store64(frame + 24, length)
            elif same_text(name, __lsl_address("reg") + 16):
                __lsl_qbe_store64(frame + 32, value)
                __lsl_qbe_store64(frame + 40, length)
            elif same_text(name, __lsl_address("reg-shift") + 16) and length >= 4:
                __lsl_qbe_store64(frame + 48, big32(value))
            elif same_text(name, __lsl_address("timebase-frequency") + 16) and length >= 4:
                frequency = big32(value)
                if length >= 8:
                    frequency = cells_value(value, 2)
                end
                if frequency > 0:
                    call set_board_word(32, frequency)
                end
            end
            position = (value + length + 3) & -4
        elif token == 4:
            position += 4
        else:
            break
        end
    end
    if board_word(16) == 0:
        call set_board_word(16, UART_DEFAULT)
    end
    return 0
end

function ram_start():
    return board_word(0)
end

function ram_end():
    return board_word(8)
end

function timebase():
    return board_word(32)
end

function time():
    return __lsl_qbe_call0(__lsl_symbol("lsl_arch_time"))
end

function set_timer(deadline):
    call __lsl_qbe_call1(__lsl_symbol("lsl_arch_set_timer"), deadline)
    return 0
end

# IPI hartu (blok hartu +24 = mhartid).
function wake_hart(hart):
    call __lsl_qbe_call1(__lsl_symbol("lsl_arch_send_ipi"), __lsl_qbe_load64(hart + 24))
    return 0
end

# UART 16550 (LSR = registr 5: bit 0 přijatý bajt, bit 5 volný vysílač).
function uart_register(index):
    return board_word(16) + __lsl_qbe_shl(index, board_word(24))
end

function uart_ready_out():
    return __lsl_qbe_load8(uart_register(5)) & 32 != 0
end

function uart_ready_in():
    return __lsl_qbe_load8(uart_register(5)) & 1 != 0
end

function uart_put_raw(character):
    __lsl_qbe_store8(uart_register(0), character)
    return 0
end

function uart_get_raw():
    return __lsl_qbe_load8(uart_register(0))
end

# Konec bez hostitele: zařízení sifive_test (0x5555 úspěch, jinak kód).
function power_off(status):
    device = __lsl_qbe_load64(__lsl_symbol("lsl_test_device"))
    if device != 0:
        if status == 0:
            __lsl_qbe_store32(device, 21845)
        else:
            __lsl_qbe_store32(device, __lsl_qbe_shl(status & 65535, 16) | 13107)
        end
    end
    return 0
end

# Zastavená past je ebreak semihostingu (slli zero,zero,0x1f; ebreak;
# srai zero,zero,7)? Pokračuje se za ní.
function host_probe_fault(cause, pc):
    if cause != CAUSE_BREAKPOINT:
        return 0
    end
    if __lsl_qbe_load32(pc - 4) == 32509971 and __lsl_qbe_load32(pc + 4) == 1081102355:
        return 1
    end
    return 0
end

function host_probe_skip(pc):
    return pc + 8
end

# Výpadek stránky (instrukce, čtení, zápis).
function page_fault(cause):
    if cause == 12 or cause == 13 or cause == 15:
        return 1
    end
    return 0
end

function semihost_call(operation, block):
    return __lsl_qbe_call2(__lsl_symbol("lsl_arch_semihost"), operation, block)
end

function host_available():
    return __lsl_qbe_load64(__lsl_symbol("lsl_semihost_absent")) == 0
end

# Tabulky stránek: allocate(bytes) vrací vynulovanou stránku (os_baremetal).
function leaf(address, flags):
    return __lsl_qbe_shl(__lsl_qbe_lshr(address, 12), 10) | flags | PTE_VALID | PTE_ACCESSED | PTE_DIRTY
end

function table_entry(address):
    return __lsl_qbe_shl(__lsl_qbe_lshr(address, 12), 10) | PTE_VALID
end

function entry_address(entry):
    return __lsl_qbe_shl(__lsl_qbe_lshr(entry, 10), 12)
end

# Oprávnění stránky obrazu: kód RX, data jen pro čtení R, stráže žádné,
# zbytek RW.
function image_flags(address):
    if address < __lsl_symbol("lsl_text_end"):
        return PTE_READ | PTE_EXECUTE
    elif address < __lsl_symbol("lsl_rodata_end"):
        return PTE_READ
    end
    stacks = __lsl_symbol("lsl_trap_stacks")
    if address >= stacks and address < __lsl_symbol("lsl_stack_guard"):
        if __lsl_qbe_urem(address - stacks, 20480) < PAGE:
            return 0
        end
    end
    guard = __lsl_symbol("lsl_stack_guard")
    if address >= guard and address < guard + PAGE:
        return 0
    end
    return PTE_READ | PTE_WRITE
end

# Leží adresa ve strážní stránce obrazu (hlavní zásobník, zásobníky pastí)?
function image_guard(address):
    if address < RAM_START or address >= __lsl_symbol("lsl_image_end"):
        return 0
    end
    if image_flags(address) == 0 and address >= __lsl_symbol("lsl_rodata_end"):
        return 1
    end
    return 0
end

# Identita: zařízení (vše mimo RAM) jako 1 GiB RW, RAM po 2 MiB RW, obraz
# po stránkách podle image_flags. Vrací kořen, nebo 0.
function build_tables(allocate):
    root = __lsl_qbe_call1(allocate, PAGE)
    if root <= 0:
        return 0
    end
    start = ram_start()
    finish = ram_end()
    image_end = (__lsl_symbol("lsl_image_end") + MEGA - 1) & -MEGA
    giga = 0
    while giga < IDENTITY_GIGAS:
        low = giga * GIGA
        high = low + GIGA
        if high <= start or low >= finish:
            __lsl_qbe_store64(root + __lsl_qbe_shl(giga, 3), leaf(low, PTE_READ | PTE_WRITE))
        else:
            middle = __lsl_qbe_call1(allocate, PAGE)
            if middle <= 0:
                return 0
            end
            __lsl_qbe_store64(root + __lsl_qbe_shl(giga, 3), table_entry(middle))
            mega = 0
            while mega < 512:
                address = low + mega * MEGA
                if address >= start and address < image_end and address < finish:
                    table = __lsl_qbe_call1(allocate, PAGE)
                    if table <= 0:
                        return 0
                    end
                    __lsl_qbe_store64(middle + __lsl_qbe_shl(mega, 3), table_entry(table))
                    page = 0
                    while page < 512:
                        target = address + page * PAGE
                        flags = image_flags(target)
                        if flags != 0:
                            __lsl_qbe_store64(table + __lsl_qbe_shl(page, 3), leaf(target, flags))
                        end
                        page += 1
                    end
                else:
                    __lsl_qbe_store64(middle + __lsl_qbe_shl(mega, 3), leaf(address, PTE_READ | PTE_WRITE))
                end
                mega += 1
            end
        end
        giga += 1
    end
    call set_board_word(40, root)
    return root
end

# Položka listu 4 KiB pro adresu (tabulky chybějících úrovní vytvoří), nebo 0.
function page_entry(address, allocate):
    table = board_word(40)
    level = 2
    while level > 0:
        index = __lsl_qbe_lshr(address, 12 + 9 * level) & 511
        slot = table + __lsl_qbe_shl(index, 3)
        entry = __lsl_qbe_load64(slot)
        if entry & PTE_VALID == 0:
            next = __lsl_qbe_call1(allocate, PAGE)
            if next <= 0:
                return 0
            end
            __lsl_qbe_store64(slot, table_entry(next))
            table = next
        elif entry & (PTE_READ | PTE_WRITE | PTE_EXECUTE) != 0:
            # Velká stránka: oblast zásobníků do ní nepatří.
            return 0
        else:
            table = entry_address(entry)
        end
        level -= 1
    end
    return table + __lsl_qbe_shl(__lsl_qbe_lshr(address, 12) & 511, 3)
end

# Namapuje stránku zásobníku (frame = fyzická stránka). 1 nová, 2 už byla.
function map_stack_page(address, frame, allocate):
    slot = page_entry(address, allocate)
    if slot == 0:
        return 0
    end
    if __lsl_qbe_load64(slot) & PTE_VALID != 0:
        call __lsl_qbe_call1(__lsl_symbol("lsl_arch_flush_page"), address)
        return 2
    end
    __lsl_qbe_store64(slot, leaf(frame, PTE_READ | PTE_WRITE))
    call __lsl_qbe_call1(__lsl_symbol("lsl_arch_flush_page"), address)
    return 1
end

# Zapne stránkování (Sv39) na hartu 0 a povolí přerušení.
function enable_paging(root):
    call __lsl_qbe_call1(__lsl_symbol("lsl_arch_enable_paging"), __lsl_qbe_shl(8, 60) | __lsl_qbe_lshr(root, 12))
    return 0
end

# Kontext nového vlákna (TCB): zásobník, blok vlákna, argumenty, vstup.
function init_context(tcb, top, thread_pointer, first, second, entry):
    call clear(tcb, 536)
    __lsl_qbe_store64(tcb + REGISTER_SP, top)
    __lsl_qbe_store64(tcb + REGISTER_TP, thread_pointer)
    __lsl_qbe_store64(tcb + REGISTER_A0, first)
    __lsl_qbe_store64(tcb + REGISTER_A1, second)
    __lsl_qbe_store64(tcb + CONTEXT_PC, entry)
    __lsl_qbe_store64(tcb + CONTEXT_STATUS, NEW_STATUS)
    return 0
end
