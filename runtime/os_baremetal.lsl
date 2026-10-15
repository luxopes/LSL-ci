# lsl: runtime
# Vrstva OS pro bare metal (bez operačního systému): rozhraní jako
# os_linux.lsl. Chyba je záporné errno Linuxu. CPU a zařízení řeší deska
# (_runtime_board, runtime/board_baremetal_<arch>.lsl).
# - vstup a výstup: hostitel (semihosting), je-li k dispozici: stdin,
#   stdout, stderr, soubory, argumenty, čas a návratový kód; jinak konzole
#   na UART a konec přes zařízení desky,
# - paměť: identita RAM se stránkováním (kód jen ke čtení a spuštění, data
#   bez spuštění); halda roste od konce obrazu nahoru, ostatní mapování
#   ukrajuje alokátor rámců od konce RAM dolů (nuluje je, neuvolňuje),
# - zásobníky vláken (8 MiB) ve vlastní virtuální oblasti, stránky se
#   přidělí při prvním přístupu; pod zásobníkem je nenamapovaná stráž,
#   hlavní zásobník a zásobníky pastí mají strážní stránku: přetečení
#   zásobníku ukončí program se zprávou,
# - vlákna: preemptivní plánovač (časový kvantum 10 ms) na všech hartech
#   (jádrech), futex, spánek, zastavení vláken pro GC s uloženým kontextem,
# - entropie z CSR seed (Zkr), jinak z /dev/urandom hostitele,
# - procesy ani sockety nejsou: tyto funkce vrací -ENOSYS.
# Kritické sekce alokátoru rámců běží jen v pasti (na zásobníku pasti):
# výpadek stránky zásobníku vlákna je obslouží, aniž by čekal na zámek,
# který vlákno drží.
load _platform as platform
load _runtime_board as board
load core

THREAD_SELF_PUBLISH = 0
THREAD_RESUME = 1
ENV_IGNORE_CASE = 0
THREAD_REGISTER_BYTES = 512

MAIN_STACK_TOP = 120
THREAD_TABLE = 112
TLS_STACK_TOP = 16
# Stav vrstvy (lsl_baremetal_state): +0 spodní hranice rámců, +8 konec
# zpřístupněné haldy, +16 čítač tid, +32 čas hostitele při prvním dotazu
# (s), +40 čas desky v tu chvíli + 1, +48 začátek haldy, +56 zámek rámců,
# +64 zámek plánovače, +72 zámek deskriptorů, +80 kurzor plánovače,
# +88 čítač oblastí zásobníků, +96 plánovač běží, +104 další připravená
# vlákna po posledním výběru, +160.. deska.
DESCRIPTORS = 64
# TCB (lsl_tcbs; kontext podle desky do +536): +536 stav, +544 hart, na
# kterém běží, +552 adresa čekání, +560 termín (čas desky, 0 žádný),
# +568 zastaveno pro GC, +576 požadavek, +584.. argumenty, +608 výsledek,
# +616 položka tabulky vláken, +624 tid.
TCB_BYTES = 704
TCB_COUNT = 129
MAX_HARTS = 8
HART_BYTES = 64
FREE = 0
RUNNABLE = 1
RUNNING = 2
BLOCKED = 3
SLEEPING = 4
# Požadavky na plánovač (lsl_arch_request).
REQUEST_YIELD = 1
REQUEST_WAIT = 2
REQUEST_SLEEP = 3
REQUEST_EXIT = 4
REQUEST_ALLOCATE = 5
REQUEST_COMMIT = 6
# Zásobníky vláken: oblast od 128 GiB, každé vlákno 16 MiB adres, z nich
# horních STACK_BYTES namapovaných podle potřeby.
STACK_REGION = 137438953472
STACK_SLOT = 16777216
STACK_SLOTS = 8192
STACK_BYTES = 8392704

ENOSYS = 38
EBADF = 9
ENOENT = 2
EEXIST = 17
ESPIPE = 29
EIO = 5
EAGAIN = 11
ETIMEDOUT = 110

# Operace hostitele (semihosting).
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
    return board.host_available()
end

function host_call(operation, block):
    return board.semihost_call(operation, block)
end

# Záporné errno poslední chyby hostitele (qemu na Linuxu: hodnoty Linuxu).
function host_error():
    code = host_call(SYS_ERRNO, 0)
    if code <= 0 or code > 4095:
        return 0 - EIO
    end
    return 0 - code
end

function syscall6(number, a, b, c, d, e, f):
    return 0 - ENOSYS
end

function text_length(text):
    length = 0
    while __lsl_qbe_load8(text + length) != 0:
        length += 1
    end
    return length
end

function cas(address, expected, value):
    return __lsl_qbe_call3(__lsl_symbol("lsl_arch_cas64"), address, expected, value)
end

function pause():
    call __lsl_qbe_call0(__lsl_symbol("lsl_arch_pause"))
    return 0
end

# Spinlock (slovo 0 volno / 1 drženo); volající má vypnutá přerušení.
function spin_lock(word):
    while cas(word, 0, 1) != 0:
        call pause()
    end
    return 0
end

function spin_unlock(word):
    call __lsl_qbe_call2(__lsl_symbol("lsl_arch_xchg64"), word, 0)
    return 0
end

function irq_save():
    return __lsl_qbe_call0(__lsl_symbol("lsl_arch_irq_save"))
end

function irq_restore(flags):
    call __lsl_qbe_call1(__lsl_symbol("lsl_arch_irq_restore"), flags)
    return 0
end

# Zámek tabulky deskriptorů: krátké sekce v kontextu vlákna; při sporu se
# ustoupí jiným vláknům (držitel mohl být přerušen).
function descriptor_lock():
    while cas(layer_state() + 72, 0, 1) != 0:
        call sched_yield()
    end
    return 0
end

function descriptor_unlock():
    call spin_unlock(layer_state() + 72)
    return 0
end

function scheduling():
    return __lsl_qbe_load64(layer_state() + 96) != 0
end

function zero(address, size):
    finish = address + size
    while address < finish:
        __lsl_qbe_store64(address, 0)
        address += 8
    end
    return 0
end

# Alokátor rámců (od konce RAM dolů, 4 KiB): jen v pasti nebo před startem
# plánovače (jediný hart, přerušení vypnutá). Vynulovaná paměť, nebo -12.
function lsl_baremetal_frames(size):
    call spin_lock(layer_state() + 56)
    bottom = __lsl_qbe_load64(layer_state())
    start = (bottom - ((size + 4095) & -4096)) & -4096
    result = -12
    if size > 0 and start >= __lsl_qbe_load64(layer_state() + 8):
        __lsl_qbe_store64(layer_state(), start)
        result = start
    end
    call spin_unlock(layer_state() + 56)
    if result > 0:
        call zero(result, (size + 4095) & -4096)
    end
    return result
end

# Zpřístupnění haldy (souvislá oblast pod rámci; nová část se nuluje).
function commit(address, size):
    finish = address + size
    if address < __lsl_qbe_load64(layer_state() + 48):
        return 0
    end
    call spin_lock(layer_state() + 56)
    committed = __lsl_qbe_load64(layer_state() + 8)
    result = 1
    start = 0
    if finish > __lsl_qbe_load64(layer_state()):
        result = 0
    elif finish > committed:
        start = address
        if committed > start:
            start = committed
        end
        __lsl_qbe_store64(layer_state() + 8, finish)
    end
    call spin_unlock(layer_state() + 56)
    if result and start != 0:
        call zero(start, finish - start)
    end
    return result
end

# Požadavek na plánovač z kontextu vlákna: obslouží ho past (SSIP).
function request(operation, first, second, third):
    tcb = __lsl_qbe_call0(__lsl_symbol("lsl_arch_current_tcb"))
    __lsl_qbe_store64(tcb + 584, first)
    __lsl_qbe_store64(tcb + 592, second)
    __lsl_qbe_store64(tcb + 600, third)
    __lsl_qbe_store64(tcb + 576, operation)
    call __lsl_qbe_call1(__lsl_symbol("lsl_arch_request"), tcb)
    return __lsl_qbe_load64(tcb + 608)
end

function map_anonymous(size, extra_flags):
    if scheduling():
        return request(REQUEST_ALLOCATE, size, 0, 0)
    end
    return lsl_baremetal_frames(size)
end

function map_at(address, size):
    if scheduling():
        return request(REQUEST_COMMIT, address, size, 0)
    end
    return commit(address, size)
end

function tcb_at(index):
    return __lsl_symbol("lsl_tcbs") + index * TCB_BYTES
end

function hart_at(index):
    return __lsl_symbol("lsl_harts") + index * HART_BYTES
end

function hart_count():
    count = __lsl_qbe_load64(__lsl_symbol("lsl_hart_count"))
    if count > MAX_HARTS:
        return MAX_HARTS
    end
    return count
end

# Inicializace TCB nečinnosti hartu (pc = lsl_arch_idle).
function init_idle(hart, index):
    idle = __lsl_symbol("lsl_idle_tcbs") + index * TCB_BYTES
    call board.init_context(idle, __lsl_qbe_load64(hart + 16), 0, 0, 0, __lsl_symbol("lsl_arch_idle"))
    __lsl_qbe_store64(idle + 536, RUNNING)
    __lsl_qbe_store64(hart + 32, idle)
    return idle
end

# Start (z lsl_runtime_start jako první volání vrstvy OS): zařízení,
# stránkování, plánovač s hlavním vláknem (TCB 0), další harty.
function heap_base(hint):
    call board.discover()
    base = (__lsl_symbol("lsl_image_end") + 65535) & -65536
    __lsl_qbe_store64(layer_state(), board.ram_end() & -4096)
    __lsl_qbe_store64(layer_state() + 8, base)
    __lsl_qbe_store64(layer_state() + 48, base)
    __lsl_qbe_store64(layer_state() + 16, 1)
    root = board.build_tables(__lsl_symbol("lsl_baremetal_frames"))
    if root == 0:
        call exit_process(71)
    end
    main = tcb_at(0)
    __lsl_qbe_store64(main + 536, RUNNING)
    __lsl_qbe_store64(main + 544, hart_at(0))
    __lsl_qbe_store64(main + 624, 1)
    call init_idle(hart_at(0), 0)
    __lsl_qbe_store64(layer_state() + 96, 1)
    call board.set_timer(board.time() + slice())
    call board.enable_paging(root)
    __lsl_qbe_store64(__lsl_symbol("lsl_harts_go"), 1)
    return base
end

# Další hart (z lsl_s_secondary, přerušení vypnutá): TCB nečinnosti.
function lsl_baremetal_secondary(hart):
    index = __lsl_qbe_udiv(hart - hart_at(0), HART_BYTES)
    idle = init_idle(hart, index)
    __lsl_qbe_store64(hart, idle)
    call board.set_timer(board.time() + slice())
    return 0
end

function slice():
    return __lsl_qbe_udiv(board.timebase(), 100)
end

# Probudí čekající na adrese (nejvýš count); volající drží zámek plánovače.
function wake_locked(address, count):
    woken = 0
    index = 0
    while index < TCB_COUNT and woken < count:
        tcb = tcb_at(index)
        if __lsl_qbe_load64(tcb + 536) == BLOCKED and __lsl_qbe_load64(tcb + 552) == address:
            __lsl_qbe_store64(tcb + 536, RUNNABLE)
            __lsl_qbe_store64(tcb + 560, 0)
            __lsl_qbe_store64(tcb + 608, 0)
            woken += 1
        end
        index += 1
    end
    return woken
end

# Probudí nečinné harty (kromě vlastního), aby si vybraly připravené vlákno.
function kick(self):
    index = 0
    count = hart_count()
    while index < count:
        hart = hart_at(index)
        if hart != self and __lsl_qbe_load64(hart) == __lsl_qbe_load64(hart + 32) and __lsl_qbe_load64(hart + 32) != 0:
            call board.wake_hart(hart)
        end
        index += 1
    end
    return 0
end

# Požadavek vlákna v pasti (zámek plánovače drží volající).
function serve(tcb, operation):
    first = __lsl_qbe_load64(tcb + 584)
    result = 0
    if operation == REQUEST_WAIT:
        if __lsl_qbe_load32(first) == (__lsl_qbe_load64(tcb + 592) & 4294967295):
            __lsl_qbe_store64(tcb + 536, BLOCKED)
            __lsl_qbe_store64(tcb + 552, first)
            __lsl_qbe_store64(tcb + 560, __lsl_qbe_load64(tcb + 600))
        else:
            result = 0 - EAGAIN
        end
    elif operation == REQUEST_SLEEP:
        __lsl_qbe_store64(tcb + 536, SLEEPING)
        __lsl_qbe_store64(tcb + 560, first)
    elif operation == REQUEST_EXIT:
        # Stav položky 1 -> 0 až tady, mimo zásobník vlákna: nové vlákno ho
        # pak smí převzít. Během zastavování pro GC (stav 4/2) se počká.
        if cas(first + 16, 1, 0) == 1:
            call wake_locked(first + 16, 2147483647)
            __lsl_qbe_store64(tcb + 536, FREE)
            __lsl_qbe_store64(tcb + 568, 0)
        else:
            result = -1
        end
    elif operation == REQUEST_ALLOCATE:
        result = lsl_baremetal_frames(first)
    elif operation == REQUEST_COMMIT:
        result = commit(first, __lsl_qbe_load64(tcb + 592))
    end
    __lsl_qbe_store64(tcb + 608, result)
    __lsl_qbe_store64(tcb + 576, 0)
    return 0
end

# Výběr dalšího vlákna (round robin) a nastavení časovače hartu.
function schedule(current, hart):
    if __lsl_qbe_load64(current + 536) == RUNNING and current != __lsl_qbe_load64(hart + 32):
        __lsl_qbe_store64(current + 536, RUNNABLE)
    end
    now = board.time()
    cursor = __lsl_qbe_load64(layer_state() + 80)
    next = 0
    woken = 0
    step = 1
    while step <= TCB_COUNT:
        index = __lsl_qbe_urem(cursor + step, TCB_COUNT)
        tcb = tcb_at(index)
        status = __lsl_qbe_load64(tcb + 536)
        if status == BLOCKED or status == SLEEPING:
            due = __lsl_qbe_load64(tcb + 560)
            if due != 0 and due <= now:
                if status == BLOCKED:
                    __lsl_qbe_store64(tcb + 608, 0 - ETIMEDOUT)
                end
                __lsl_qbe_store64(tcb + 536, RUNNABLE)
                __lsl_qbe_store64(tcb + 560, 0)
                status = RUNNABLE
                woken += 1
            end
        end
        if status == RUNNABLE and __lsl_qbe_load64(tcb + 568) == 0:
            if next == 0:
                next = tcb
                __lsl_qbe_store64(layer_state() + 80, index)
            else:
                woken += 1
            end
        end
        step += 1
    end
    if next == 0:
        next = __lsl_qbe_load64(hart + 32)
    else:
        __lsl_qbe_store64(next + 536, RUNNING)
        __lsl_qbe_store64(next + 544, hart)
    end
    __lsl_qbe_store64(hart, next)
    # Připravená vlákna navíc: probudit nečinné harty (lsl_baremetal_trap).
    __lsl_qbe_store64(layer_state() + 104, woken != 0)
    return next
end

# Past S-módu (lsl_strap, přerušení vypnutá, zásobník pasti): obslouží
# příčinu a vrátí TCB, jehož kontext se obnoví.
function lsl_baremetal_trap(cause, pc, value, tcb, hart):
    if cause >= 0:
        if board.host_probe_fault(cause, pc):
            __lsl_qbe_store64(__lsl_symbol("lsl_semihost_absent"), 1)
            __lsl_qbe_store64(tcb + board.REGISTER_A0, -1)
            __lsl_qbe_store64(tcb + board.CONTEXT_PC, board.host_probe_skip(pc))
            return tcb
        end
        if board.page_fault(cause) and stack_fault(value):
            return tcb
        end
        call fault(cause, pc, value)
        return tcb
    end
    code = cause & 255
    call spin_lock(layer_state() + 64)
    if code == board.CAUSE_SOFTWARE:
        call __lsl_qbe_call0(__lsl_symbol("lsl_arch_clear_soft"))
        operation = __lsl_qbe_load64(tcb + 576)
        if operation != 0:
            call serve(tcb, operation)
        end
    end
    now = board.time()
    next = schedule(tcb, hart)
    others = __lsl_qbe_load64(layer_state() + 104)
    deadline = now + slice()
    index = 0
    while index < TCB_COUNT:
        other = tcb_at(index)
        status = __lsl_qbe_load64(other + 536)
        due = __lsl_qbe_load64(other + 560)
        if (status == BLOCKED or status == SLEEPING) and due != 0 and due < deadline:
            deadline = due
        end
        index += 1
    end
    call spin_unlock(layer_state() + 64)
    if deadline <= now:
        deadline = now + 1
    end
    call board.set_timer(deadline)
    if others:
        call kick(hart)
    end
    return next
end

# Výpadek stránky v oblasti zásobníků vláken: stránka v rozsahu zásobníku
# se namapuje (1), pod ním je stráž (0 = přetečení).
function stack_fault(address):
    if address < STACK_REGION or address >= STACK_REGION + STACK_SLOTS * STACK_SLOT:
        return 0
    end
    top = STACK_REGION + (__lsl_qbe_lshr(address - STACK_REGION, 24) + 1) * STACK_SLOT
    if address < top - STACK_BYTES:
        return 0
    end
    frame = lsl_baremetal_frames(4096)
    if frame < 0:
        return 0
    end
    call spin_lock(layer_state() + 56)
    mapped = board.map_stack_page(address & -4096, frame, __lsl_symbol("lsl_baremetal_table_page"))
    call spin_unlock(layer_state() + 56)
    return mapped != 0
end

# Stránka pro tabulku stránek (volá se pod zámkem rámců).
function lsl_baremetal_table_page(size):
    bottom = __lsl_qbe_load64(layer_state())
    start = (bottom - 4096) & -4096
    if start < __lsl_qbe_load64(layer_state() + 8):
        return -12
    end
    __lsl_qbe_store64(layer_state(), start)
    call zero(start, 4096)
    return start
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

# Konzole UART (deska): konec řádku jako CR LF; čtení čeká na bajt.
function uart_put(character):
    while not board.uart_ready_out():
        call pause()
    end
    call board.uart_put_raw(character)
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

function uart_read(buffer, count):
    done = 0
    while done < count:
        if not board.uart_ready_in():
            if done > 0:
                break
            end
            call sched_yield()
        else:
            character = board.uart_get_raw()
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
    return __lsl_symbol("lsl_baremetal_descriptors")
end

# Otevře soubor hostitele s módem fopen (0 "r" ... 11 "a+b"): handle, nebo
# záporné errno.
function host_open(path, mode):
    block = __lsl_qbe_alloc(24)
    __lsl_qbe_store64(block, path)
    __lsl_qbe_store64(block + 8, mode)
    __lsl_qbe_store64(block + 16, text_length(path))
    handle = host_call(SYS_OPEN, block)
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
        # Souběžné první použití: platí první handle, druhý se zavře.
        if __lsl_qbe_call3(__lsl_symbol("lsl_arch_cas64"), entry, 0, handle + 1) != 0:
            block = __lsl_qbe_alloc(8)
            __lsl_qbe_store64(block, handle)
            call host_call(SYS_CLOSE, block)
        end
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
    left = host_call(operation, block)
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
    if host_call(SYS_SEEK, block) != 0:
        return host_error()
    end
    __lsl_qbe_store64(entry + 8, position)
    return position
end

function file_length(entry):
    block = __lsl_qbe_alloc(8)
    __lsl_qbe_store64(block, handle_of(entry))
    length = host_call(SYS_FLEN, block)
    if length < 0:
        return host_error()
    end
    return length
end

function terminal_entry(entry):
    block = __lsl_qbe_alloc(8)
    __lsl_qbe_store64(block, handle_of(entry))
    return host_call(SYS_ISTTY, block) == 1
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
    if host_call(SYS_CLOSE, block) != 0:
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
    call host_call(SYS_CLOSE, block)
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
    handle = host_open(path, selected)
    if handle < 0:
        return handle
    end
    call descriptor_lock()
    fd = 3
    while fd < DESCRIPTORS and __lsl_qbe_load64(table + __lsl_qbe_shl(fd, 4)) != 0:
        fd += 1
    end
    if fd < DESCRIPTORS:
        __lsl_qbe_store64(table + __lsl_qbe_shl(fd, 4), handle + 1)
    end
    call descriptor_unlock()
    if fd >= DESCRIPTORS:
        block = __lsl_qbe_alloc(8)
        __lsl_qbe_store64(block, handle)
        call host_call(SYS_CLOSE, block)
        return -24
    end
    entry = table + __lsl_qbe_shl(fd, 4)
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
    if host_call(SYS_REMOVE, block) != 0:
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
    call host_call(SYS_CLOSE, block)
    return 0
end

# Konec programu: hostitel (návratový kód), jinak zařízení desky.
function exit_process(status):
    if host():
        block = __lsl_qbe_alloc(16)
        __lsl_qbe_store64(block, APPLICATION_EXIT)
        __lsl_qbe_store64(block + 8, status)
        call host_call(SYS_EXIT, block)
    end
    call board.power_off(status)
    while True:
        call pause()
    end
    return 0
end

function write_text(text):
    call write(2, text + 16, __lsl_qbe_load64(text + 8))
    return 0
end

function write_hex(value):
    digits = __lsl_qbe_alloc(16)
    call hex_digits(digits, value)
    call write(2, digits, 16)
    return 0
end

# Přetečení zásobníku: stráž zásobníku vlákna, hlavního zásobníku nebo
# zásobníku pasti.
function overflow_address(address):
    if address >= STACK_REGION and address < STACK_REGION + STACK_SLOTS * STACK_SLOT:
        return 1
    end
    return board.image_guard(address)
end

# Neobsloužená past procesoru: příčina, adresa instrukce a adresa přístupu;
# program končí se stavem 70.
function fault(cause, pc, value):
    if board.page_fault(cause) and overflow_address(value):
        call write_text("LSL runtime crash: stack overflow at 0x")
        call write_hex(pc)
        call write_text("\n")
        call exit_process(70)
    end
    call write_text("LSL runtime crash: exception 0x")
    call write_hex(cause)
    call write_text(" at 0x")
    call write_hex(pc)
    call write_text(" (address 0x")
    call write_hex(value)
    call write_text(")\n")
    call exit_process(70)
    return 0
end

# Čas desky pro termín za timespec (0 = bez termínu).
function deadline_after(timespec):
    if timespec == 0:
        return 0
    end
    seconds = __lsl_qbe_load64(timespec)
    nanoseconds = __lsl_qbe_load64(timespec + 8)
    if seconds < 0 or nanoseconds < 0:
        return board.time() + 1
    end
    if seconds > 1000000000:
        seconds = 1000000000
    end
    frequency = board.timebase()
    return board.time() + seconds * frequency + __lsl_qbe_udiv(nanoseconds * __lsl_qbe_udiv(frequency, 1000) , 1000000) + 1
end

function futex_wait(address, expected):
    return request(REQUEST_WAIT, address, expected, 0)
end

function futex_wait_timeout(address, expected, timespec):
    return request(REQUEST_WAIT, address, expected, deadline_after(timespec))
end

function futex_wake(address, count):
    flags = irq_save()
    call spin_lock(layer_state() + 64)
    woken = wake_locked(address, count)
    call spin_unlock(layer_state() + 64)
    call irq_restore(flags)
    if woken > 0:
        call kick(0)
    end
    return woken
end

function getpid():
    return 1
end

function gettid():
    return __lsl_qbe_load64(__lsl_qbe_call0(__lsl_symbol("lsl_arch_current_tcb")) + 624)
end

function sched_yield():
    if scheduling():
        call request(REQUEST_YIELD, 0, 0, 0)
    end
    return 0
end

# Harty, které se přihlásily (MAX_HARTS nejvýš).
function sched_getaffinity(size, mask):
    count = hart_count()
    if size < 1:
        return -22
    end
    index = 0
    while index < size:
        __lsl_qbe_store8(mask + index, 0)
        index += 1
    end
    index = 0
    while index < count and __lsl_qbe_lshr(index, 3) < size:
        address = mask + __lsl_qbe_lshr(index, 3)
        __lsl_qbe_store8(address, __lsl_qbe_load8(address) | __lsl_qbe_shl(1, index & 7))
        index += 1
    end
    return __lsl_qbe_lshr(count + 7, 3)
end

# Čas desky v nanosekundách (bez přetečení pro libovolnou frekvenci do
# 9 GHz).
function board_nanoseconds():
    ticks = board.time()
    frequency = board.timebase()
    seconds = __lsl_qbe_udiv(ticks, frequency)
    rest = __lsl_qbe_urem(ticks, frequency)
    return seconds * 1000000000 + __lsl_qbe_udiv(rest * 1000000000, frequency)
end

# Monotónní čas od startu; reálný čas = čas hostitele při prvním dotazu
# (SYS_TIME, jinak 0 = 1970) + uplynulý čas desky.
function os_clock_gettime(clock, timespec):
    now = board_nanoseconds()
    if clock != platform.CLOCK_MONOTONIC:
        if __lsl_qbe_load64(layer_state() + 40) == 0:
            seconds = 0
            if host():
                seconds = host_call(SYS_TIME, 0)
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

function os_nanosleep(request_time, remaining):
    seconds = __lsl_qbe_load64(request_time)
    nanoseconds = __lsl_qbe_load64(request_time + 8)
    if seconds < 0 or nanoseconds < 0 or nanoseconds >= 1000000000:
        return -22
    end
    if remaining != 0:
        __lsl_qbe_store64(remaining, 0)
        __lsl_qbe_store64(remaining + 8, 0)
    end
    call request(REQUEST_SLEEP, deadline_after(request_time), 0, 0)
    return 0
end

# Vlákna. TCB vlákna = položka tabulky vláken runtime + 1 (TCB 0 je
# hlavní vlákno).
function tcb_of(entry):
    index = __lsl_qbe_lshr(entry - __lsl_qbe_load64(core.state() + THREAD_TABLE) - 8, 6)
    return tcb_at(index + 1)
end

# Zásobník vlákna: oblast 16 MiB adres ve STACK_REGION, použije se znovu.
function thread_stack(top, size, guard):
    if top != 0:
        return top
    end
    slot = __lsl_qbe_call2(__lsl_symbol("lsl_arch_add64"), layer_state() + 88, 1)
    if slot >= STACK_SLOTS:
        return -1
    end
    return STACK_REGION + (slot + 1) * STACK_SLOT
end

# Volá se pod zámkem tabulky vláken: kontext nového vlákna a zařazení.
# Příznak zastavení pro GC (+568) se nemění: vlákno, které GC zastavilo
# dřív, než vzniklo, poběží až po thread_resume.
function thread_start(entry, top, function):
    tcb = tcb_of(entry)
    tid = __lsl_qbe_call2(__lsl_symbol("lsl_arch_add64"), layer_state() + 16, 1) + 1
    call board.init_context(tcb, top, entry + 32, entry, function, __lsl_symbol("lsl_arch_thread_entry"))
    __lsl_qbe_store64(tcb + 576, 0)
    __lsl_qbe_store64(tcb + 616, entry)
    __lsl_qbe_store64(tcb + 624, tid)
    __lsl_qbe_store64(tcb + 560, 0)
    flags = irq_save()
    call spin_lock(layer_state() + 64)
    __lsl_qbe_store64(tcb + 536, RUNNABLE)
    call spin_unlock(layer_state() + 64)
    call irq_restore(flags)
    call kick(0)
    return tid
end

function thread_run_pending(entry):
    return 0
end

# Konec vlákna: stav položky vynuluje plánovač (REQUEST_EXIT); během
# zastavování pro GC se to zkouší znovu.
function thread_exit(entry):
    while True:
        call request(REQUEST_EXIT, entry, 0, 0)
        call sched_yield()
    end
    return 0
end

# Zastavení pro GC (stav 4): plánovač vlákno nevybere a hart, na kterém
# běží, dostane IPI; čeká se, až neběží. Uložený sp do +24, stav 2.
function thread_suspend(process, entry):
    tcb = tcb_of(entry)
    flags = irq_save()
    call spin_lock(layer_state() + 64)
    __lsl_qbe_store64(tcb + 568, 1)
    running = __lsl_qbe_load64(tcb + 536) == RUNNING
    hart = __lsl_qbe_load64(tcb + 544)
    call spin_unlock(layer_state() + 64)
    call irq_restore(flags)
    if running:
        call board.wake_hart(hart)
        while __lsl_qbe_load64(tcb + 536) == RUNNING:
            call pause()
        end
    end
    if __lsl_qbe_load64(tcb + 616) == entry and __lsl_qbe_load64(tcb + 536) != FREE:
        __lsl_qbe_store64(entry + 24, __lsl_qbe_load64(tcb + board.REGISTER_SP))
    else:
        __lsl_qbe_store64(entry + 24, __lsl_qbe_load64(entry + 8))
    end
    __lsl_qbe_store64(entry + 16, 2)
    return 0
end

function thread_resume(entry):
    tcb = tcb_of(entry)
    __lsl_qbe_store64(entry + 16, 1)
    flags = irq_save()
    call spin_lock(layer_state() + 64)
    __lsl_qbe_store64(tcb + 568, 0)
    call spin_unlock(layer_state() + 64)
    call irq_restore(flags)
    call kick(0)
    return 0
end

function thread_registers(entry):
    return tcb_of(entry)
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
        if host_call(SYS_GET_CMDLINE, request) == 0:
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
    left = host_call(SYS_READ, block)
    __lsl_qbe_store64(block, handle)
    call host_call(SYS_CLOSE, block)
    if left != 0:
        return 0 - EIO
    end
    return 0
end

function tgkill(process, thread, signal):
    return 0 - ENOSYS
end

function install_thread_suspend():
    return 0
end

# Přejmenování (__lsl_rename) zatím není.
function rename_path(source, destination):
    return 0 - platform.ENOSYS
end

# Výpis adresáře (__lsl_list_directory) zatím není.
function directory_open(path):
    return 0 - ENOSYS
end

function directory_next(state, buffer, size):
    return 0
end

function directory_close(state):
    return 0
end
