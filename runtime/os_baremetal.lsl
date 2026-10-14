# lsl: runtime
# Vrstva OS pro bare metal riscv64 (M-mód, deska qemu virt): rozhraní jako
# os_linux.lsl bez operačního systému. Chyba je záporné errno Linuxu.
# - vstup a výstup: semihosting, je-li k dispozici (debugger nebo qemu
#   -semihosting): stdin/stdout/stderr hostitele, soubory hostitele,
#   argumenty, čas a návratový kód; jinak konzole na UART 16550 a konec
#   přes zařízení sifive_test (qemu virt),
# - paměť: RAM podle stromu zařízení (FDT); halda roste od konce obrazu
#   (lsl_image_end) nahoru, ostatní mapování ukrajuje runtime od konce RAM
#   dolů; nic se neuvolňuje, nová paměť se nuluje,
# - monotónní čas z CLINT mtime (10 MHz), spánek čeká aktivně,
# - entropie z CSR seed (Zkr), jinak z /dev/urandom hostitele,
# - vlákna běží sekvenčně (thread_run_pending), procesy ani sockety nejsou:
#   tyto funkce vrací -ENOSYS.
# Bez ochrany paměti: přetečení zásobníku (8 MiB) se nezachytí.
load _platform as platform
load core

THREAD_SELF_PUBLISH = 0
THREAD_RESUME = 0
ENV_IGNORE_CASE = 0
THREAD_REGISTER_BYTES = 0

MAIN_STACK_TOP = 120
# Zařízení desky qemu virt.
UART = 268435456
SIFIVE_TEST = 1048576
CLINT_MTIME = 33603576
# mtime: 10 MHz = 100 ns na tik.
MTIME_NANOSECONDS = 100
RAM_START = 2147483648
RAM_DEFAULT = 134217728
# Stav vrstvy (lsl_baremetal_state, 64 B): +0 spodní hranice mapování od
# konce RAM, +8 konec zpřístupněné haldy, +16 počet spuštěných vláken,
# +24 tabulka deskriptorů, +32 čas hostitele při prvním dotazu (s),
# +40 mtime v tu chvíli, +48 začátek haldy.
# Tabulka deskriptorů: 64 záznamů po 16 B: +0 handle semihostingu (0 =
# volný), +8 pozice v souboru.
DESCRIPTORS = 64

ENOSYS = 38
EBADF = 9
ENOENT = 2
EEXIST = 17
ESPIPE = 29
EIO = 5

# Operace semihostingu.
SYS_OPEN = 1
SYS_CLOSE = 2
SYS_WRITE = 5
SYS_READ = 6
SYS_ISTTY = 9
SYS_SEEK = 10
SYS_FLEN = 12
SYS_REMOVE = 14
SYS_TIME = 17
SYS_ERRNO = 19
SYS_GET_CMDLINE = 21
SYS_EXIT = 24
APPLICATION_EXIT = 131110

function layer_state():
    return __lsl_symbol("lsl_baremetal_state")
end

function host():
    return __lsl_qbe_load64(__lsl_symbol("lsl_semihost_absent")) == 0
end

function semihost(operation, block):
    return __lsl_qbe_call2(__lsl_symbol("lsl_arch_semihost"), operation, block)
end

# Záporné errno poslední chyby hostitele (qemu na Linuxu: hodnoty Linuxu).
function host_error():
    code = semihost(SYS_ERRNO, 0)
    if code <= 0 or code > 4095:
        return 0 - EIO
    end
    return 0 - code
end

function syscall6(number, a, b, c, d, e, f):
    return 0 - ENOSYS
end

function big32(address):
    return __lsl_qbe_shl(__lsl_qbe_load8(address), 24) | __lsl_qbe_shl(__lsl_qbe_load8(address + 1), 16) | __lsl_qbe_shl(__lsl_qbe_load8(address + 2), 8) | __lsl_qbe_load8(address + 3)
end

function text_length(text):
    length = 0
    while __lsl_qbe_load8(text + length) != 0:
        length += 1
    end
    return length
end

# Konec RAM z uzlu memory stromu zařízení (#address-cells = #size-cells = 2,
# jako qemu virt); bez platného FDT 128 MiB od RAM_START.
function ram_end():
    fdt = __lsl_qbe_load64(__lsl_symbol("lsl_fdt"))
    if fdt < RAM_START or big32(fdt) != 3490578157:
        return RAM_START + RAM_DEFAULT
    end
    position = fdt + big32(fdt + 8)
    strings = fdt + big32(fdt + 12)
    limit = fdt + big32(fdt + 4)
    depth = 0
    memory = 0
    while position < limit:
        token = big32(position)
        if token == 1:
            name = position + 4
            depth += 1
            if depth == 2 and __lsl_qbe_load8(name) == 109 and __lsl_qbe_load8(name + 1) == 101 and __lsl_qbe_load8(name + 2) == 109 and __lsl_qbe_load8(name + 3) == 111 and __lsl_qbe_load8(name + 4) == 114 and __lsl_qbe_load8(name + 5) == 121:
                memory = 1
            end
            position = (name + text_length(name) + 4) & -4
        elif token == 2:
            if depth == 2:
                memory = 0
            end
            depth -= 1
            position += 4
        elif token == 3:
            length = big32(position + 4)
            name = strings + big32(position + 8)
            value = position + 12
            if memory and length >= 16 and __lsl_qbe_load8(name) == 114 and __lsl_qbe_load8(name + 1) == 101 and __lsl_qbe_load8(name + 2) == 103 and __lsl_qbe_load8(name + 3) == 0:
                start = __lsl_qbe_shl(big32(value), 32) | big32(value + 4)
                size = __lsl_qbe_shl(big32(value + 8), 32) | big32(value + 12)
                if start <= RAM_START and start + size > RAM_START:
                    return start + size
                end
            end
            position = (value + length + 3) & -4
        elif token == 4:
            position += 4
        else:
            break
        end
    end
    return RAM_START + RAM_DEFAULT
end

# Volá se při startu jako první: halda od konce obrazu, mapování od konce RAM.
function heap_base(hint):
    base = (__lsl_symbol("lsl_image_end") + 65535) & -65536
    __lsl_qbe_store64(layer_state(), ram_end() & -65536)
    __lsl_qbe_store64(layer_state() + 8, base)
    __lsl_qbe_store64(layer_state() + 48, base)
    return base
end

function zero(address, size):
    finish = address + size
    while address < finish:
        __lsl_qbe_store64(address, 0)
        address += 8
    end
    return 0
end

function map_anonymous(size, extra_flags):
    bottom = __lsl_qbe_load64(layer_state())
    start = (bottom - ((size + 65535) & -65536)) & -65536
    if size <= 0 or start < __lsl_qbe_load64(layer_state() + 8):
        return -12
    end
    __lsl_qbe_store64(layer_state(), start)
    call zero(start, (size + 7) & -8)
    return start
end

# Halda: souvislá oblast pod mapováními; nově zpřístupněná část se nuluje.
function map_at(address, size):
    finish = address + size
    if address < __lsl_qbe_load64(layer_state() + 48) or finish > __lsl_qbe_load64(layer_state()):
        return 0
    end
    committed = __lsl_qbe_load64(layer_state() + 8)
    if finish > committed:
        start = address
        if committed > start:
            start = committed
        end
        call zero(start, finish - start)
        __lsl_qbe_store64(layer_state() + 8, finish)
    end
    return 1
end

function unmap(address, length):
    return 0
end

function mmap(address, length, protection, flags, descriptor, offset):
    return map_anonymous(length, 0)
end

function mprotect(address, length, protection):
    return 0
end

function munmap(address, length):
    return 0
end

function map_shared(fd, length, offset):
    return 0 - ENOSYS
end

# Konzole UART 16550 (LSR +5: bit 0 přijatý bajt, bit 5 volný vysílač).
function uart_put(character):
    while __lsl_qbe_load8(UART + 5) & 32 == 0:
        call __lsl_qbe_call0(__lsl_symbol("lsl_arch_pause"))
    end
    __lsl_qbe_store8(UART, character)
    return 0
end

function uart_write(buffer, count):
    index = 0
    while index < count:
        character = __lsl_qbe_load8(buffer + index)
        if character == 10:
            call uart_put(13)
        end
        call uart_put(character)
        index += 1
    end
    return count
end

# Čte, co přišlo; čeká alespoň na jeden bajt. Enter (CR) je konec řádku.
function uart_read(buffer, count):
    done = 0
    while done < count:
        if __lsl_qbe_load8(UART + 5) & 1 == 0:
            if done > 0:
                break
            end
            call __lsl_qbe_call0(__lsl_symbol("lsl_arch_pause"))
        else:
            character = __lsl_qbe_load8(UART)
            if character == 13:
                character = 10
            end
            __lsl_qbe_store8(buffer + done, character)
            done += 1
            if character == 10:
                break
            end
        end
    end
    return done
end

function descriptors():
    table = __lsl_qbe_load64(layer_state() + 24)
    if table == 0:
        table = map_anonymous(16 * DESCRIPTORS, 0)
        if table < 0:
            return 0
        end
        __lsl_qbe_store64(layer_state() + 24, table)
    end
    return table
end

# Otevře soubor hostitele s módem fopen (0 "r" ... 11 "a+b"): handle, nebo
# záporné errno.
function host_open(path, mode):
    block = __lsl_qbe_alloc(24)
    __lsl_qbe_store64(block, path)
    __lsl_qbe_store64(block + 8, mode)
    __lsl_qbe_store64(block + 16, text_length(path))
    handle = semihost(SYS_OPEN, block)
    if handle < 0 or handle == 4294967295:
        return host_error()
    end
    return handle
end

# Záznam deskriptoru, nebo 0. Deskriptory 0-2 jsou konzole hostitele
# (":tt"), otevřou se při prvním použití.
function entry_of(fd):
    if not host() or fd < 0 or fd >= DESCRIPTORS:
        return 0
    end
    table = descriptors()
    if table == 0:
        return 0
    end
    entry = table + __lsl_qbe_shl(fd, 4)
    if __lsl_qbe_load64(entry) == 0 and fd <= 2:
        handle = host_open(__lsl_address(":tt") + 16, __lsl_qbe_shl(fd, 2))
        if handle < 0:
            return 0
        end
        __lsl_qbe_store64(entry, handle + 1)
    end
    if __lsl_qbe_load64(entry) == 0:
        return 0
    end
    return entry
end

function handle_of(entry):
    return __lsl_qbe_load64(entry) - 1
end

# Přenos semihostingu (SYS_READ, SYS_WRITE): přenesené bajty, nebo errno.
function transfer(operation, entry, buffer, count):
    block = __lsl_qbe_alloc(24)
    __lsl_qbe_store64(block, handle_of(entry))
    __lsl_qbe_store64(block + 8, buffer)
    __lsl_qbe_store64(block + 16, count)
    left = semihost(operation, block)
    if left < 0 or left > count:
        return host_error()
    end
    __lsl_qbe_store64(entry + 8, __lsl_qbe_load64(entry + 8) + count - left)
    return count - left
end

function write(fd, buffer, count):
    if not host():
        if fd == 1 or fd == 2:
            return uart_write(buffer, count)
        end
        return 0 - EBADF
    end
    entry = entry_of(fd)
    if entry == 0:
        return 0 - EBADF
    end
    if count == 0:
        return 0
    end
    return transfer(SYS_WRITE, entry, buffer, count)
end

function read(fd, buffer, count):
    if not host():
        if fd == 0:
            return uart_read(buffer, count)
        end
        return 0 - EBADF
    end
    entry = entry_of(fd)
    if entry == 0:
        return 0 - EBADF
    end
    if count == 0:
        return 0
    end
    return transfer(SYS_READ, entry, buffer, count)
end

function seek_to(entry, position):
    block = __lsl_qbe_alloc(16)
    __lsl_qbe_store64(block, handle_of(entry))
    __lsl_qbe_store64(block + 8, position)
    if semihost(SYS_SEEK, block) != 0:
        return host_error()
    end
    __lsl_qbe_store64(entry + 8, position)
    return position
end

function file_length(entry):
    block = __lsl_qbe_alloc(8)
    __lsl_qbe_store64(block, handle_of(entry))
    length = semihost(SYS_FLEN, block)
    if length < 0:
        return host_error()
    end
    return length
end

function terminal_entry(entry):
    block = __lsl_qbe_alloc(8)
    __lsl_qbe_store64(block, handle_of(entry))
    return semihost(SYS_ISTTY, block) == 1
end

function lseek(fd, offset, whence):
    entry = entry_of(fd)
    if entry == 0:
        return 0 - EBADF
    end
    if terminal_entry(entry):
        return 0 - ESPIPE
    end
    target = offset
    if whence == 1:
        target = __lsl_qbe_load64(entry + 8) + offset
    elif whence == 2:
        length = file_length(entry)
        if length < 0:
            return length
        end
        target = length + offset
    elif whence != 0:
        return -22
    end
    if target < 0:
        return -22
    end
    return seek_to(entry, target)
end

function pread(fd, buffer, count, offset):
    entry = entry_of(fd)
    if entry == 0:
        return 0 - EBADF
    end
    saved = __lsl_qbe_load64(entry + 8)
    result = seek_to(entry, offset)
    if result < 0:
        return result
    end
    result = transfer(SYS_READ, entry, buffer, count)
    call seek_to(entry, saved)
    return result
end

function close(fd):
    entry = entry_of(fd)
    if entry == 0:
        return 0 - EBADF
    end
    block = __lsl_qbe_alloc(8)
    __lsl_qbe_store64(block, handle_of(entry))
    __lsl_qbe_store64(entry, 0)
    __lsl_qbe_store64(entry + 8, 0)
    if semihost(SYS_CLOSE, block) != 0:
        return host_error()
    end
    return 0
end

# Druh souboru jako S_IFMT >> 12 Linuxu: 8 soubor, 2 znakové zařízení.
function file_kind(fd):
    if not host():
        if fd >= 0 and fd <= 2:
            return 2
        end
        return 0 - EBADF
    end
    entry = entry_of(fd)
    if entry == 0:
        return 0 - EBADF
    end
    if terminal_entry(entry):
        return 2
    end
    return 8
end

function is_terminal(fd):
    return file_kind(fd) == 2
end

function ioctl(fd, request, argument):
    return -25
end

function socket(domain, kind, protocol):
    return 0 - ENOSYS
end

function connect(fd, address, length):
    return 0 - ENOSYS
end

function exists(path):
    handle = host_open(path, 1)
    if handle < 0:
        return 0
    end
    block = __lsl_qbe_alloc(8)
    __lsl_qbe_store64(block, handle)
    call semihost(SYS_CLOSE, block)
    return 1
end

# open(cesta, příznaky Linuxu, mód) nad souborem hostitele; adresáře
# semihosting nezná.
function open(path, flags, mode):
    if not host():
        return 0 - ENOENT
    end
    if flags & platform.O_DIRECTORY != 0:
        return 0 - ENOSYS
    end
    access_mode = flags & 3
    create = flags & platform.O_CREAT != 0
    if create and flags & platform.O_EXCL != 0 and exists(path):
        return 0 - EEXIST
    end
    # Módy fopen: 1 "rb", 3 "r+b", 5 "wb", 7 "w+b", 9 "ab", 11 "a+b".
    selected = 1
    if flags & platform.O_APPEND != 0:
        selected = 9
        if access_mode == 2:
            selected = 11
        end
    elif access_mode != 0 and flags & platform.O_TRUNC != 0:
        selected = 5
        if access_mode == 2:
            selected = 7
        end
    elif access_mode != 0:
        selected = 3
        if create and not exists(path):
            selected = 7
        end
    end
    table = descriptors()
    if table == 0:
        return -12
    end
    fd = 3
    while fd < DESCRIPTORS and __lsl_qbe_load64(table + __lsl_qbe_shl(fd, 4)) != 0:
        fd += 1
    end
    if fd >= DESCRIPTORS:
        return -24
    end
    handle = host_open(path, selected)
    if handle < 0:
        return handle
    end
    entry = table + __lsl_qbe_shl(fd, 4)
    __lsl_qbe_store64(entry, handle + 1)
    __lsl_qbe_store64(entry + 8, 0)
    if selected >= 9:
        length = file_length(entry)
        if length > 0:
            __lsl_qbe_store64(entry + 8, length)
        end
    end
    return fd
end

function make_directory(path, mode):
    return 0 - ENOSYS
end

function remove_file(path):
    if not host():
        return 0 - ENOENT
    end
    block = __lsl_qbe_alloc(16)
    __lsl_qbe_store64(block, path)
    __lsl_qbe_store64(block + 8, text_length(path))
    if semihost(SYS_REMOVE, block) != 0:
        return host_error()
    end
    return 0
end

function remove_directory(path):
    return 0 - ENOSYS
end

function access(path):
    if not host():
        return 0 - ENOENT
    end
    handle = host_open(path, 1)
    if handle < 0:
        return handle
    end
    block = __lsl_qbe_alloc(8)
    __lsl_qbe_store64(block, handle)
    call semihost(SYS_CLOSE, block)
    return 0
end

function exit_process(status):
    if host():
        block = __lsl_qbe_alloc(16)
        __lsl_qbe_store64(block, APPLICATION_EXIT)
        __lsl_qbe_store64(block + 8, status)
        call semihost(SYS_EXIT, block)
    end
    if status == 0:
        __lsl_qbe_store32(SIFIVE_TEST, 21845)
    else:
        __lsl_qbe_store32(SIFIVE_TEST, __lsl_qbe_shl(status & 65535, 16) | 13107)
    end
    while True:
        call __lsl_qbe_call0(__lsl_symbol("lsl_arch_pause"))
    end
    return 0
end

function hex_digits(buffer, value):
    index = 15
    while index >= 0:
        digit = value & 15
        if digit < 10:
            __lsl_qbe_store8(buffer + index, 48 + digit)
        else:
            __lsl_qbe_store8(buffer + index, 87 + digit)
        end
        value = __lsl_qbe_lshr(value, 4)
        index -= 1
    end
    return 0
end

# Past procesoru (lsl_trap ve vrstvě architektury): příčina, adresa
# instrukce a hodnota mtval; program končí se stavem 70.
function lsl_baremetal_fault(cause, pc, value):
    message = "LSL runtime crash: exception 0x"
    call write(2, message + 16, __lsl_qbe_load64(message + 8))
    digits = __lsl_qbe_alloc(16)
    call hex_digits(digits, cause)
    call write(2, digits, 16)
    message = " at 0x"
    call write(2, message + 16, __lsl_qbe_load64(message + 8))
    call hex_digits(digits, pc)
    call write(2, digits, 16)
    message = " (mtval 0x"
    call write(2, message + 16, __lsl_qbe_load64(message + 8))
    call hex_digits(digits, value)
    call write(2, digits, 16)
    message = ")\n"
    call write(2, message + 16, __lsl_qbe_load64(message + 8))
    call exit_process(70)
    return 0
end

# Entropie pro stdlib random: CSR seed (Zkr), jinak /dev/urandom hostitele
# přes semihosting. 0, nebo záporné errno (-ENOSYS bez zdroje).
function lsl_baremetal_entropy(buffer, count):
    index = 0
    while index < count:
        value = __lsl_qbe_call0(__lsl_symbol("lsl_arch_entropy16"))
        if value < 0:
            break
        end
        __lsl_qbe_store8(buffer + index, value & 255)
        if index + 1 < count:
            __lsl_qbe_store8(buffer + index + 1, __lsl_qbe_lshr(value, 8) & 255)
        end
        index += 2
    end
    if index >= count:
        return 0
    end
    if not host():
        return 0 - ENOSYS
    end
    handle = host_open(__lsl_address("/dev/urandom") + 16, 1)
    if handle < 0:
        return handle
    end
    block = __lsl_qbe_alloc(24)
    __lsl_qbe_store64(block, handle)
    __lsl_qbe_store64(block + 8, buffer)
    __lsl_qbe_store64(block + 16, count)
    left = semihost(SYS_READ, block)
    __lsl_qbe_store64(block, handle)
    call semihost(SYS_CLOSE, block)
    if left != 0:
        return 0 - EIO
    end
    return 0
end

# Jeden hart: na zámky ani bránu GC nikdo nečeká.
function futex_wait(address, expected):
    return 0
end

function futex_wait_timeout(address, expected, timespec):
    return 0
end

function futex_wake(address, count):
    return 0
end

function getpid():
    return 1
end

function gettid():
    return 1
end

function sched_yield():
    return 0
end

function sched_getaffinity(size, mask):
    if size < 1:
        return -22
    end
    __lsl_qbe_store8(mask, 1)
    return 1
end

function mtime_nanoseconds():
    return __lsl_qbe_load64(CLINT_MTIME) * MTIME_NANOSECONDS
end

# Monotónní čas od startu (mtime); reálný čas = čas hostitele při prvním
# dotazu (semihosting SYS_TIME, jinak 0 = 1970) + uplynulý mtime.
function os_clock_gettime(clock, timespec):
    now = mtime_nanoseconds()
    if clock != platform.CLOCK_MONOTONIC:
        if __lsl_qbe_load64(layer_state() + 40) == 0:
            seconds = 0
            if host():
                seconds = semihost(SYS_TIME, 0)
                if seconds < 0:
                    seconds = 0
                end
            end
            __lsl_qbe_store64(layer_state() + 32, seconds)
            __lsl_qbe_store64(layer_state() + 40, now + 1)
        end
        now = __lsl_qbe_load64(layer_state() + 32) * 1000000000 + now - (__lsl_qbe_load64(layer_state() + 40) - 1)
    end
    __lsl_qbe_store64(timespec, __lsl_qbe_udiv(now, 1000000000))
    __lsl_qbe_store64(timespec + 8, __lsl_qbe_urem(now, 1000000000))
    return 0
end

function os_nanosleep(request, remaining):
    seconds = __lsl_qbe_load64(request)
    nanoseconds = __lsl_qbe_load64(request + 8)
    if seconds < 0 or nanoseconds < 0 or nanoseconds >= 1000000000:
        return -22
    end
    if remaining != 0:
        __lsl_qbe_store64(remaining, 0)
        __lsl_qbe_store64(remaining + 8, 0)
    end
    if seconds > 9000000000:
        seconds = 9000000000
    end
    finish = mtime_nanoseconds() + seconds * 1000000000 + nanoseconds
    while mtime_nanoseconds() < finish:
        call __lsl_qbe_call0(__lsl_symbol("lsl_arch_pause"))
    end
    return 0
end

# Blok argumentů jako na zásobníku Linuxu (argc, argv[], 0, prostředí, 0).
# Semihosting předá příkazový řádek jako text oddělený mezerami; bez něj je
# argv ["lsl"]. Prostředí je prázdné.
function process_arguments(stack):
    block = map_anonymous(65536, 0)
    if block < 0:
        return 0
    end
    text = block + 32768
    length = 0
    if host():
        request = __lsl_qbe_alloc(16)
        __lsl_qbe_store64(request, text)
        __lsl_qbe_store64(request + 8, 32767)
        if semihost(SYS_GET_CMDLINE, request) == 0:
            length = __lsl_qbe_load64(request + 8)
            if length < 0 or length > 32767:
                length = 0
            end
        end
    end
    if length == 0:
        __lsl_qbe_store8(text, 108)
        __lsl_qbe_store8(text + 1, 115)
        __lsl_qbe_store8(text + 2, 108)
        length = 3
    end
    __lsl_qbe_store8(text + length, 0)
    argc = 0
    index = 0
    while index < length and argc < 4000:
        while index < length and __lsl_qbe_load8(text + index) == 32:
            __lsl_qbe_store8(text + index, 0)
            index += 1
        end
        if index >= length:
            break
        end
        __lsl_qbe_store64(block + 8 + __lsl_qbe_shl(argc, 3), text + index)
        argc += 1
        while index < length and __lsl_qbe_load8(text + index) != 32:
            index += 1
        end
    end
    __lsl_qbe_store64(block, argc)
    return block
end

function os_environment():
    block = __lsl_qbe_load64(__lsl_qbe_load64(__lsl_symbol("lsl_state")) + MAIN_STACK_TOP)
    return block + __lsl_qbe_shl(__lsl_qbe_load64(block) + 2, 3)
end

# Cesta k programu WASI nezná: argv[0], jak ho předal hostitel.
function os_executable_path(buffer, size):
    block = __lsl_qbe_load64(__lsl_qbe_load64(__lsl_symbol("lsl_state")) + MAIN_STACK_TOP)
    if __lsl_qbe_load64(block) == 0:
        return 0 - ENOENT
    end
    name = __lsl_qbe_load64(block + 8)
    length = text_length(name)
    if length >= size:
        return -36
    end
    index = 0
    while index < length:
        __lsl_qbe_store8(buffer + index, __lsl_qbe_load8(name + index))
        index += 1
    end
    return length
end

function os_read(fd, buffer, count):
    return read(fd, buffer, count)
end

function os_close(fd):
    return close(fd)
end

function os_lseek(fd, offset, whence):
    return lseek(fd, offset, whence)
end

function os_write_all(fd, buffer, count):
    while count > 0:
        written = write(fd, buffer, count)
        if written <= 0:
            return -1
        end
        buffer += written
        count -= written
    end
    return 0
end

# Procesy bez operačního systému nejsou.
function os_memfd(name):
    return 0 - ENOSYS
end

function os_pipe(fds):
    return 0 - ENOSYS
end

function os_limit_descriptors(limit):
    return 0 - ENOSYS
end

function os_spawn(path, argv, clean, input, output, error, parent_end):
    return 0 - ENOSYS
end

function os_wait(pid):
    return -10
end

function os_wait_exit(pid):
    return 0
end

function os_exit_code(status):
    return status
end

function os_kill(pid):
    return 0 - ENOSYS
end

function process_deadline(pid, milliseconds):
    return 0
end

function process_deadline_cancel(watch):
    return 0
end

# Jeden hart bez plánovače. Vlákno proto doběhne celé hned po spawnu
# (thread_run_pending, mimo zámek tabulky) na stejném stínovém zásobníku:
# platné sekvenční pořadí pro programy, kde vlákno nečeká na hlavní vlákno.
# Blok vlákna má vrchol zásobníku hlavního vlákna, takže GC smí běžet i ve
# vlákně a prohledá celý zásobník. tid je pořadové číslo spawnu.
function thread_stack(top, size, guard):
    return 0
end

function thread_start(entry, top, function):
    count = __lsl_qbe_load64(layer_state() + 16) + 1
    __lsl_qbe_store64(layer_state() + 16, count)
    return count
end

function thread_run_pending(entry):
    main = __lsl_qbe_call0(__lsl_symbol("lsl_arch_thread_pointer"))
    __lsl_qbe_store64(entry + 48, __lsl_qbe_load64(main + 16))
    call __lsl_qbe_call1(__lsl_symbol("lsl_arch_set_thread_pointer"), entry + 32)
    call __lsl_qbe_call2(__lsl_symbol("lsl_thread_main"), entry, __lsl_qbe_load64(entry + 24))
    call __lsl_qbe_call1(__lsl_symbol("lsl_arch_set_thread_pointer"), main)
    __lsl_qbe_store64(entry + 16, 0)
    return 0
end

# Konec funkce vlákna: návrat do thread_run_pending.
function thread_exit(entry):
    return 0
end

function thread_suspend(process, entry):
    return 0
end

function thread_resume(entry):
    return 0
end

function thread_registers(entry):
    return 0
end

function install_thread_suspend():
    return 0
end

function tgkill(process, thread, signal):
    return 0 - ENOSYS
end
