# lsl: runtime
# Vrstva OS pro WebAssembly s WASI (preview1): rozhraní jako os_linux.lsl
# nad funkcemi lsl_wasi_* vrstvy architektury (runtime/arch/wasi_wasm32.wat).
# - chyba je záporné errno s hodnotami Linuxu (errno_of převádí kódy WASI),
# - cesty se otevírají vůči předotevřeným adresářům WASI (nejdelší shoda
#   prefixu; relativní cesty vůči ".", jinak "/"),
# - paměť: lineární paměť wasm; halda leží od HEAP_START, ostatní mapování
#   pod ní (map_anonymous ukrajuje od konce dat programu); nic se neuvolňuje,
# - vlákna: s wasi-threads skutečná (cíl wasm32-wasi-threads), jinak
#   sekvenčně (thread_run_pending); žádné procesy ani sockety (WASI
#   preview1 je nemá): tyto funkce vrací -ENOSYS.
load _platform as platform

# Krok procházení kořenů GC (zásobníky, registry): 64bitová slova.
ROOT_WORD_BYTES = 8
# Značka adres haldy: lineární paměť má 32bitové adresy; objekty mají
# v LSL bit 40 (backend wasm32 adresy před přístupem zkrátí), takže se
# celé číslo nespletete s adresou objektu (viz os_linux.lsl).
HEAP_ADDRESS_TAG = 1099511627776
load core

function thread_self_publish():
    return 0
end
THREAD_RESUME = 1
ENV_IGNORE_CASE = 0
THREAD_REGISTER_BYTES = 0

MAIN_STACK_TOP = 120
THREAD_TABLE = 112
MAIN_THREAD_BLOCK = 160
GC_GATE = 128
THREAD_SHADOW_BYTES = 4194304
HEAP_START = 1073741824
# Stav vrstvy (data vrstvy architektury nad lsl_state): +0 další volná
# adresa pod haldou, +8 tabulka předotevřených adresářů (0 = nenačtená),
# +16 počet spuštěných vláken (bez vláken), +24 příznaky blokujících oblastí
# vláken.
WASI_STATE = 1088

ENOSYS = 38
EBADF = 9
ENOENT = 2

FILETYPE_CHARACTER_DEVICE = 2
FILETYPE_DIRECTORY = 3
FILETYPE_REGULAR_FILE = 4
OFLAGS_CREAT = 1
OFLAGS_DIRECTORY = 2
OFLAGS_EXCL = 4
OFLAGS_TRUNC = 8
FDFLAGS_APPEND = 1
FDFLAGS_NONBLOCK = 4
LOOKUP_SYMLINK_FOLLOW = 1
RIGHTS_ALL = 536870911

# errno WASI -> errno Linuxu.
function errno_of(code):
    if code == 2 or code == 76:
        return 13
    elif code == 1:
        return 7
    elif code == 6:
        return 11
    elif code == 8:
        return 9
    elif code == 20:
        return 17
    elif code == 27:
        return 4
    elif code == 28:
        return 22
    elif code == 31:
        return 21
    elif code == 32:
        return 40
    elif code == 37:
        return 36
    elif code == 44:
        return 2
    elif code == 48:
        return 12
    elif code == 51:
        return 28
    elif code == 52:
        return 38
    elif code == 54:
        return 20
    elif code == 55:
        return 39
    elif code == 59:
        return 25
    elif code == 63:
        return 1
    elif code == 64:
        return 32
    elif code == 70:
        return 29
    end
    return 5
end

# 0 při úspěchu WASI, jinak záporné errno Linuxu.
function checked(code):
    if code == 0:
        return 0
    end
    return 0 - errno_of(code)
end

function syscall6(number, a, b, c, d, e, f):
    return 0 - ENOSYS
end

# Paměť pod haldou: ukrajuje se od konce dat a stínového zásobníku
# programu (atomicky: volají ji i vlákna).
function map_anonymous(size, extra_flags):
    while True:
        next = __lsl_qbe_load64(WASI_STATE)
        start = (next + 65535) & -65536
        finish = start + ((size + 65535) & -65536)
        if finish > HEAP_START or not __lsl_qbe_call1(__lsl_symbol("lsl_wasm_memory_reserve"), finish):
            return -12
        end
        if __lsl_qbe_call3(__lsl_symbol("lsl_arch_cas64"), WASI_STATE, next, finish) == next:
            return start
        end
    end
    return -12
end

# Stránky volného bloku se zde jádru nevracejí.
function release_pages(address, length):
    return 0
end

# Řídce zapisovaná oblast; zde bez zvláštního zacházení.
function map_sparse(size):
    return map_anonymous(size, 0)
end

function map_at(address, size):
    address = address & 4294967295
    if address < HEAP_START:
        return 0
    end
    return __lsl_qbe_call1(__lsl_symbol("lsl_wasm_memory_reserve"), address + size) != 0
end

# Volá se při startu před prvním mapováním: oblast pod haldou začíná za
# daty a stínovým zásobníkem hlavního vlákna.
function heap_base(hint):
    if __lsl_qbe_load64(WASI_STATE) == 0:
        __lsl_qbe_store64(WASI_STATE, __lsl_qbe_call0(__lsl_symbol("lsl_wasm_data_end")))
    end
    return HEAP_START
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

# I/O: jeden vektor (iovec wasm32: +0 adresa, +4 délka).
function write(fd, buffer, count):
    vector = __lsl_qbe_alloc(16)
    __lsl_qbe_store32(vector, buffer)
    __lsl_qbe_store32(vector + 4, count)
    done = __lsl_qbe_alloc(8)
    __lsl_qbe_store64(done, 0)
    result = checked(__lsl_qbe_call4(__lsl_symbol("lsl_wasi_fd_write"), fd, vector, 1, done))
    if result < 0:
        return result
    end
    return __lsl_qbe_load32(done)
end

function read(fd, buffer, count):
    vector = __lsl_qbe_alloc(16)
    __lsl_qbe_store32(vector, buffer)
    __lsl_qbe_store32(vector + 4, count)
    done = __lsl_qbe_alloc(8)
    __lsl_qbe_store64(done, 0)
    # Čtení může čekat (stdin, roura): GC zatím vlákno nepotřebuje zastavit.
    call enter_blocking()
    code = __lsl_qbe_call4(__lsl_symbol("lsl_wasi_fd_read"), fd, vector, 1, done)
    call leave_blocking()
    result = checked(code)
    if result < 0:
        return result
    end
    return __lsl_qbe_load32(done)
end

function pread(fd, buffer, count, offset):
    vector = __lsl_qbe_alloc(16)
    __lsl_qbe_store32(vector, buffer)
    __lsl_qbe_store32(vector + 4, count)
    done = __lsl_qbe_alloc(8)
    __lsl_qbe_store64(done, 0)
    result = checked(__lsl_qbe_call5(__lsl_symbol("lsl_wasi_fd_pread"), fd, vector, 1, offset, done))
    if result < 0:
        return result
    end
    return __lsl_qbe_load32(done)
end

function lseek(fd, offset, whence):
    position = __lsl_qbe_alloc(8)
    __lsl_qbe_store64(position, 0)
    result = checked(__lsl_qbe_call4(__lsl_symbol("lsl_wasi_fd_seek"), fd, offset, whence, position))
    if result < 0:
        return result
    end
    return __lsl_qbe_load64(position)
end

function close(fd):
    return checked(__lsl_qbe_call1(__lsl_symbol("lsl_wasi_fd_close"), fd))
end

# Typ souboru deskriptoru (fdstat +0), nebo záporné errno.
function file_type(fd):
    status = __lsl_qbe_alloc(24)
    result = checked(__lsl_qbe_call2(__lsl_symbol("lsl_wasi_fd_fdstat_get"), fd, status))
    if result < 0:
        return result
    end
    return __lsl_qbe_load8(status)
end

# Druh souboru jako S_IFMT >> 12 Linuxu: 8 soubor, 2 znakové zařízení,
# 4 adresář, 1 ostatní (roura, socket).
function file_kind(fd):
    kind = file_type(fd)
    if kind < 0:
        return kind
    elif kind == FILETYPE_REGULAR_FILE:
        return 8
    elif kind == FILETYPE_CHARACTER_DEVICE:
        return 2
    elif kind == FILETYPE_DIRECTORY:
        return 4
    end
    return 1
end

function is_terminal(fd):
    return file_type(fd) == FILETYPE_CHARACTER_DEVICE
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

# Předotevřené adresáře: tabulka (map_anonymous) +0 počet, pak záznamy po
# 16 B: deskriptor, adresa jména (NUL na konci).
function preopens():
    table = __lsl_qbe_load64(WASI_STATE + 8)
    if table != 0:
        return table
    end
    table = map_anonymous(65536, 0)
    if table < 0:
        return 0
    end
    names = table + 16 * 512
    used = 0
    count = 0
    information = __lsl_qbe_alloc(16)
    fd = 3
    while count < 500:
        if __lsl_qbe_call2(__lsl_symbol("lsl_wasi_fd_prestat_get"), fd, information) != 0:
            break
        end
        length = __lsl_qbe_load32(information + 4)
        if __lsl_qbe_load8(information) == 0 and used + length + 1 < 65536 - 16 * 512:
            if __lsl_qbe_call3(__lsl_symbol("lsl_wasi_fd_prestat_dir_name"), fd, names + used, length) == 0:
                __lsl_qbe_store8(names + used + length, 0)
                __lsl_qbe_store64(table + 8 + __lsl_qbe_shl(count, 4), fd)
                __lsl_qbe_store64(table + 16 + __lsl_qbe_shl(count, 4), names + used)
                used += length + 1
                count += 1
            end
        end
        fd += 1
    end
    __lsl_qbe_store64(table, count)
    __lsl_qbe_store64(WASI_STATE + 8, table)
    return table
end

function text_length(text):
    length = 0
    while __lsl_qbe_load8(text + length) != 0:
        length += 1
    end
    return length
end

# Jméno předotevřeného adresáře bez koncového "/" (kromě samotného "/").
function prefix_length(name):
    length = text_length(name)
    while length > 1 and __lsl_qbe_load8(name + length - 1) == 47:
        length -= 1
    end
    return length
end

# Cesta (C řetězec) -> adresář WASI do out +0, relativní cesta +8 a její
# délka +16. 1, nebo 0 (žádný předotevřený adresář ji nepokrývá).
function resolve(path, out):
    table = preopens()
    if table == 0:
        return 0
    end
    count = __lsl_qbe_load64(table)
    best = -1
    best_length = -1
    absolute = __lsl_qbe_load8(path) == 47
    index = 0
    while index < count:
        name = __lsl_qbe_load64(table + 16 + __lsl_qbe_shl(index, 4))
        length = prefix_length(name)
        matches = 0
        if absolute and __lsl_qbe_load8(name) == 47:
            if length == 1:
                matches = 1
            else:
                matches = 1
                position = 0
                while position < length:
                    if __lsl_qbe_load8(path + position) != __lsl_qbe_load8(name + position):
                        matches = 0
                        break
                    end
                    position += 1
                end
                character = __lsl_qbe_load8(path + length)
                if matches and character != 0 and character != 47:
                    matches = 0
                end
            end
        elif not absolute and length == 1 and __lsl_qbe_load8(name) == 46:
            matches = 1
            length = 0
        end
        if matches and length > best_length:
            best = index
            best_length = length
        end
        index += 1
    end
    if best < 0:
        return 0
    end
    rest = path
    if absolute:
        rest = path + best_length
    end
    while __lsl_qbe_load8(rest) == 47:
        rest += 1
    end
    if __lsl_qbe_load8(rest) == 0:
        rest = __lsl_address(".") + 16
    end
    __lsl_qbe_store64(out, __lsl_qbe_load64(table + 8 + __lsl_qbe_shl(best, 4)))
    __lsl_qbe_store64(out + 8, rest)
    __lsl_qbe_store64(out + 16, text_length(rest))
    return 1
end

# open(cesta, příznaky Linuxu, mód): deskriptor, nebo záporné errno.
function open(path, flags, mode):
    target = __lsl_qbe_alloc(24)
    if not resolve(path, target):
        return 0 - ENOENT
    end
    oflags = 0
    if flags & platform.O_CREAT != 0:
        oflags = oflags | OFLAGS_CREAT
    end
    if flags & platform.O_EXCL != 0:
        oflags = oflags | OFLAGS_EXCL
    end
    if flags & platform.O_TRUNC != 0:
        oflags = oflags | OFLAGS_TRUNC
    end
    if flags & platform.O_DIRECTORY != 0:
        oflags = oflags | OFLAGS_DIRECTORY
    end
    fdflags = 0
    if flags & platform.O_APPEND != 0:
        fdflags = fdflags | FDFLAGS_APPEND
    end
    if flags & platform.O_NONBLOCK != 0:
        fdflags = fdflags | FDFLAGS_NONBLOCK
    end
    lookup = LOOKUP_SYMLINK_FOLLOW
    if flags & platform.O_NOFOLLOW != 0:
        lookup = 0
    end
    opened = __lsl_qbe_alloc(8)
    __lsl_qbe_store64(opened, 0)
    result = checked(__lsl_qbe_call8(__lsl_symbol("lsl_wasi_path_open"), __lsl_qbe_load64(target), lookup, __lsl_qbe_load64(target + 8), __lsl_qbe_load64(target + 16), oflags, RIGHTS_ALL, fdflags, opened))
    if result < 0:
        return result
    end
    return __lsl_qbe_load32(opened)
end

# Funkce s cestou: kind 0 mkdir, 1 unlink, 2 rmdir.
function path_call(path, kind):
    target = __lsl_qbe_alloc(24)
    if not resolve(path, target):
        return 0 - ENOENT
    end
    directory = __lsl_qbe_load64(target)
    rest = __lsl_qbe_load64(target + 8)
    length = __lsl_qbe_load64(target + 16)
    if kind == 0:
        return checked(__lsl_qbe_call3(__lsl_symbol("lsl_wasi_path_create_directory"), directory, rest, length))
    elif kind == 1:
        return checked(__lsl_qbe_call3(__lsl_symbol("lsl_wasi_path_unlink_file"), directory, rest, length))
    end
    return checked(__lsl_qbe_call3(__lsl_symbol("lsl_wasi_path_remove_directory"), directory, rest, length))
end

function make_directory(path, mode):
    return path_call(path, 0)
end

function remove_file(path):
    return path_call(path, 1)
end

function remove_directory(path):
    return path_call(path, 2)
end

function access(path):
    target = __lsl_qbe_alloc(24)
    if not resolve(path, target):
        return 0 - ENOENT
    end
    status = __lsl_qbe_alloc(64)
    return checked(__lsl_qbe_call5(__lsl_symbol("lsl_wasi_path_filestat_get"), __lsl_qbe_load64(target), LOOKUP_SYMLINK_FOLLOW, __lsl_qbe_load64(target + 8), __lsl_qbe_load64(target + 16), status))
end

function exit_process(status):
    call __lsl_qbe_call1(__lsl_symbol("lsl_wasi_proc_exit"), status)
    return 0
end

# Futex (vlákna: memory.atomic.wait32; bez vláken na nic nikdo nečeká).
function futex_wait(address, expected):
    return futex_wait_ns(address, expected, -1)
end

function futex_wait_ns(address, expected, timeout):
    if not threads():
        return 0
    end
    call enter_blocking()
    result = __lsl_qbe_call3(__lsl_symbol("lsl_wasm_wait32"), address, expected & 4294967295, timeout)
    call leave_blocking()
    if result == 1:
        return -11
    elif result == 2:
        return -110
    end
    return 0
end

function futex_wait_timeout(address, expected, timespec):
    seconds = __lsl_qbe_load64(timespec)
    nanoseconds = __lsl_qbe_load64(timespec + 8)
    if seconds < 0 or nanoseconds < 0:
        return -110
    end
    if seconds > 9000000000:
        return futex_wait_ns(address, expected, -1)
    end
    return futex_wait_ns(address, expected, seconds * 1000000000 + nanoseconds)
end

function futex_wake(address, count):
    if not threads():
        return 0
    end
    limit = count
    if limit > 2147483647:
        limit = 2147483647
    end
    return __lsl_qbe_call2(__lsl_symbol("lsl_wasm_notify"), address, limit)
end

function getpid():
    return 1
end

function gettid():
    return 1
end

function sched_yield():
    call __lsl_qbe_call0(__lsl_symbol("lsl_wasi_sched_yield"))
    return 0
end

function sched_getaffinity(size, mask):
    if size < 1:
        return -22
    end
    __lsl_qbe_store8(mask, 1)
    return 1
end

# Hodiny (WASI: 0 reálný čas, 1 monotónní; v nanosekundách).
function os_clock_gettime(clock, timespec):
    identifier = 0
    if clock == platform.CLOCK_MONOTONIC:
        identifier = 1
    end
    time = __lsl_qbe_alloc(8)
    result = checked(__lsl_qbe_call2(__lsl_symbol("lsl_wasi_clock_time_get"), identifier, time))
    if result < 0:
        return result
    end
    __lsl_qbe_store64(timespec, __lsl_qbe_udiv(__lsl_qbe_load64(time), 1000000000))
    __lsl_qbe_store64(timespec + 8, __lsl_qbe_urem(__lsl_qbe_load64(time), 1000000000))
    return 0
end

# Spánek přes poll_oneoff s relativním časovačem (subscription 48 B:
# +8 druh 0 = hodiny, +16 id hodin, +24 timeout v ns).
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
    total = 0
    if seconds > 9000000000:
        total = 9000000000000000000
    else:
        total = seconds * 1000000000 + nanoseconds
    end
    subscription = __lsl_qbe_alloc(48)
    __lsl_qbe_zero(subscription, 48)
    __lsl_qbe_store32(subscription + 16, 1)
    __lsl_qbe_store64(subscription + 24, total)
    event = __lsl_qbe_alloc(32)
    count = __lsl_qbe_alloc(8)
    call enter_blocking()
    code = __lsl_qbe_call4(__lsl_symbol("lsl_wasi_poll_oneoff"), subscription, event, 1, count)
    call leave_blocking()
    return checked(code)
end

# Blok argumentů jako na zásobníku Linuxu (argc, argv[], 0, prostředí, 0,
# řetězce) z args_get a environ_get. WASI dává pole 32bitových ukazatelů.
function process_arguments(stack):
    call preopens()
    flags = map_anonymous(1024, 0)
    if flags < 0:
        return 0
    end
    __lsl_qbe_store64(WASI_STATE + 24, flags)
    sizes = __lsl_qbe_alloc(16)
    __lsl_qbe_zero(sizes, 16)
    if __lsl_qbe_call2(__lsl_symbol("lsl_wasi_args_sizes_get"), sizes, sizes + 4) != 0:
        return 0
    end
    if __lsl_qbe_call2(__lsl_symbol("lsl_wasi_environ_sizes_get"), sizes + 8, sizes + 12) != 0:
        return 0
    end
    argc = __lsl_qbe_load32(sizes)
    argument_bytes = __lsl_qbe_load32(sizes + 4)
    envc = __lsl_qbe_load32(sizes + 8)
    environment_bytes = __lsl_qbe_load32(sizes + 12)
    pointers = __lsl_qbe_shl(argc + envc + 3, 3)
    narrow = __lsl_qbe_shl(argc + envc + 2, 2)
    block = map_anonymous(pointers + narrow + argument_bytes + environment_bytes + 16, 0)
    if block < 0:
        return 0
    end
    narrow_argv = block + pointers
    narrow_environ = narrow_argv + __lsl_qbe_shl(argc + 1, 2)
    argument_text = narrow_argv + narrow
    environment_text = argument_text + argument_bytes
    if __lsl_qbe_call2(__lsl_symbol("lsl_wasi_args_get"), narrow_argv, argument_text) != 0:
        return 0
    end
    if __lsl_qbe_call2(__lsl_symbol("lsl_wasi_environ_get"), narrow_environ, environment_text) != 0:
        return 0
    end
    __lsl_qbe_store64(block, argc)
    index = 0
    while index < argc:
        __lsl_qbe_store64(block + 8 + __lsl_qbe_shl(index, 3), __lsl_qbe_load32(narrow_argv + __lsl_qbe_shl(index, 2)))
        index += 1
    end
    __lsl_qbe_store64(block + 8 + __lsl_qbe_shl(argc, 3), 0)
    environment = block + __lsl_qbe_shl(argc + 2, 3)
    index = 0
    while index < envc:
        __lsl_qbe_store64(environment + __lsl_qbe_shl(index, 3), __lsl_qbe_load32(narrow_environ + __lsl_qbe_shl(index, 2)))
        index += 1
    end
    __lsl_qbe_store64(environment + __lsl_qbe_shl(envc, 3), 0)
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

# Procesy WASI preview1 nemá.
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

# Vlákna. Cíl wasm32-wasi-threads (vrstva wasi_wasm32_threads.wat): každé
# vlákno je instance modulu nad sdílenou pamětí spuštěná přes thread-spawn
# s vlastním stínovým zásobníkem (THREAD_SHADOW_BYTES, mez hlídá LuxIR).
# Zastavení pro GC je kooperativní: vlákno ve stavu 4 se zastaví v
# nejbližším bezpečném bodě LuxIR (lsl_wasm_safepoint); vlákno, které čeká
# ve vrstvě OS (futex, spánek, čtení), je v blokující oblasti a GC ho
# podrží, aniž by se probudilo (příznak blokující oblasti 1 -> 2).
# Cíl wasm32-wasi (bez vláken): vlákno doběhne celé hned po spawnu
# (thread_run_pending, mimo zámek tabulky) na stejném stínovém zásobníku;
# platné sekvenční pořadí pro programy, kde vlákno nečeká na hlavní vlákno.
function threads():
    return __lsl_qbe_call0(__lsl_symbol("lsl_wasm_threads"))
end

# Příznak blokující oblasti vlákna (tabulka WASI_STATE +24, slovo na
# položku tabulky vláken): 0 běží, 1 čeká ve vrstvě OS, 2 čeká a drží ho GC.
function blocking_word(entry):
    index = __lsl_qbe_lshr(entry - __lsl_qbe_load64(core.state() + THREAD_TABLE) - 8, 6)
    return __lsl_qbe_load64(WASI_STATE + 24) + __lsl_qbe_shl(index, 3)
end

# Položka tabulky vláken aktuálního pracovního vlákna, nebo 0 (hlavní).
function current_entry():
    if not threads():
        return 0
    end
    block = __lsl_qbe_call0(__lsl_symbol("lsl_arch_thread_pointer"))
    if block == core.state() + MAIN_THREAD_BLOCK:
        return 0
    end
    return block - 32
end

function enter_blocking():
    entry = current_entry()
    if entry == 0:
        return 0
    end
    __lsl_qbe_store64(entry + 24, __lsl_qbe_call0(__lsl_symbol("lsl_wasm_sp")))
    word = blocking_word(entry)
    call __lsl_qbe_call2(__lsl_symbol("lsl_arch_xchg64"), word, 1)
    # Zastavení vyžádané dřív, než se vlákno přihlásilo: podržet se samo.
    if __lsl_qbe_load64(entry + 16) == 4 and __lsl_qbe_call3(__lsl_symbol("lsl_arch_cas64"), word, 1, 2) == 1:
        __lsl_qbe_store64(entry + 16, 2)
    end
    return 0
end

function leave_blocking():
    entry = current_entry()
    if entry == 0:
        return 0
    end
    word = blocking_word(entry)
    while __lsl_qbe_call3(__lsl_symbol("lsl_arch_cas64"), word, 1, 0) != 1:
        call __lsl_qbe_call3(__lsl_symbol("lsl_wasm_wait32"), word, 2, -1)
    end
    return 0
end

# Bezpečný bod (LuxIR volá $__safepoint, když je brána GC nenulová):
# vlákno ve stavu 4 zveřejní stínový zásobník, přejde do stavu 2 a čeká
# na bráně.
function lsl_wasm_safepoint():
    entry = current_entry()
    if entry == 0 or __lsl_qbe_load64(entry + 16) != 4:
        return 0
    end
    __lsl_qbe_store64(entry + 24, __lsl_qbe_call0(__lsl_symbol("lsl_wasm_sp")))
    __lsl_qbe_store64(entry + 16, 2)
    gate = core.state() + GC_GATE
    while __lsl_qbe_load64(gate) == 1:
        call __lsl_qbe_call3(__lsl_symbol("lsl_wasm_wait32"), gate, 1, -1)
    end
    return 0
end

function thread_stack(top, size, guard):
    if not threads():
        return 0
    end
    if top != 0:
        return top
    end
    stack = map_anonymous(THREAD_SHADOW_BYTES, 0)
    if stack < 0:
        return -1
    end
    return stack + THREAD_SHADOW_BYTES
end

function thread_start(entry, top, function):
    if threads():
        tid = __lsl_qbe_call1(__lsl_symbol("lsl_wasm_thread_spawn"), entry)
        if tid <= 0:
            return -1
        end
        return tid
    end
    count = __lsl_qbe_load64(WASI_STATE + 16) + 1
    __lsl_qbe_store64(WASI_STATE + 16, count)
    return count
end

function thread_run_pending(entry):
    if threads():
        return 0
    end
    main = __lsl_qbe_call0(__lsl_symbol("lsl_arch_thread_pointer"))
    __lsl_qbe_store64(entry + 48, __lsl_qbe_load64(main + 16))
    call __lsl_qbe_call1(__lsl_symbol("lsl_arch_set_thread_pointer"), entry + 32)
    call __lsl_qbe_call2(__lsl_symbol("lsl_thread_main"), entry, __lsl_qbe_load64(entry + 24))
    call __lsl_qbe_call1(__lsl_symbol("lsl_arch_set_thread_pointer"), main)
    __lsl_qbe_store64(entry + 16, 0)
    return 0
end

# Konec funkce vlákna. S vlákny: stav 1 -> 0 (během zastavování pro GC se
# vlákno nejdřív zastaví), probudit join a návrat z wasi_thread_start.
# Po vynulování stavu se stínový zásobník už nečte (LuxIR rámce jen
# zapisuje), nové vlákno ho tedy smí hned převzít.
function thread_exit(entry):
    if not threads():
        return 0
    end
    while __lsl_qbe_call3(__lsl_symbol("lsl_arch_cas64"), entry + 16, 1, 0) != 1:
        call lsl_wasm_safepoint()
    end
    call __lsl_qbe_call2(__lsl_symbol("lsl_wasm_notify"), entry + 16, 2147483647)
    return 0
end

# Zastavení pro GC (stav 4): vlákno v blokující oblasti GC podrží hned
# (zásobník zveřejnilo při vstupu), běžící vlákno se zastaví samo.
function thread_suspend(process, entry):
    if __lsl_qbe_call3(__lsl_symbol("lsl_arch_cas64"), blocking_word(entry), 1, 2) == 1:
        __lsl_qbe_store64(entry + 16, 2)
    end
    return 0
end

function thread_resume(entry):
    word = blocking_word(entry)
    __lsl_qbe_store64(entry + 16, 1)
    if __lsl_qbe_call3(__lsl_symbol("lsl_arch_cas64"), word, 2, 1) == 2:
        call __lsl_qbe_call2(__lsl_symbol("lsl_wasm_notify"), word, 1)
    end
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
