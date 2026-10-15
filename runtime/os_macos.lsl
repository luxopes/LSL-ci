# lsl: runtime
# Vrstva OS pro macOS (x86_64 i arm64): jediné místo runtime s voláními
# libSystem. macOS nepodporuje přímá systémová volání ani statické programy,
# runtime proto volá POSIX funkce knihovny (chyba = -1 a errno). Rozhraní je
# stejné jako os_linux.lsl:
# - výsledek je hodnota, nebo záporné errno s hodnotami Linuxu (errno_of),
# - příznaky open a hodiny mají hodnoty Linuxu (modul platformy), převádí
#   je open_flags a os_clock_gettime,
# - adresa socketu má tvar Linuxu (rodina v prvních 2 bajtech), connect ji
#   převede na tvar BSD (délka, rodina).
# Funkce s proměnným počtem argumentů (open, openat, fcntl, ioctl) a fstat
# volá přes můstky vrstvy architektury (na arm64 jdou variabilní argumenty
# přes zásobník). int výsledky libSystem mají jen 32 bitů (int32).
load _platform as platform

# Krok procházení kořenů GC (zásobníky, registry): 64bitová slova.
ROOT_WORD_BYTES = 8
load core

THREAD_SELF_PUBLISH = 1
THREAD_RESUME = 0
ENV_IGNORE_CASE = 0
# Registry zastaveného vlákna leží na jeho zásobníku (thread_registers 0).
THREAD_REGISTER_BYTES = 0

THREAD_TABLE = 112
MAIN_STACK_TOP = 120
STACK_BYTES = 8392704

# Hodnoty macOS.
MAC_O_NONBLOCK = 4
MAC_O_APPEND = 8
MAC_O_NOFOLLOW = 256
MAC_O_CREAT = 512
MAC_O_TRUNC = 1024
MAC_O_EXCL = 2048
MAC_O_CLOEXEC = 16777216
MAC_MAP_SHARED = 1
MAC_MAP_PRIVATE = 2
MAC_MAP_ANON = 4096
MAC_CLOCK_MONOTONIC = 6
MAC_SIGUSR1 = 30
MAC_SA_RESTART = 2
MAC_RLIMIT_NOFILE = 8
MAC_SC_NPROCESSORS_ONLN = 58
F_GETFL = 3
F_SETFL = 4
F_SETFD = 2
FD_CLOEXEC = 1
STAT_BYTES = 256
STAT_MODE = 4
UL_COMPARE_AND_WAIT = 1
ULF_WAKE_ALL = 256
POSIX_SPAWN_CLOEXEC_DEFAULT = 16384
PTHREAD_CREATE_DETACHED = 2
# Linuxové příznaky socket(2), které macOS nemá (nastaví se fcntl).
LINUX_SOCK_NONBLOCK = 2048
LINUX_SOCK_CLOEXEC = 524288
# os_spawn: program nejde spustit (posix_spawn hlásí chybu hned). Není to
# platné pid; os_wait vrátí 127 jako potomek po execve na Linuxu.
SPAWN_FAILED = 1099511627776

function int32(value):
    return __lsl_qbe_s32(value & 4294967295)
end

# errno macOS -> errno Linuxu (1..34 jsou stejné).
function errno_of(code):
    if code >= 1 and code <= 34:
        return code
    elif code == 35:
        return 11
    elif code == 36:
        return 115
    elif code == 38:
        return 88
    elif code == 47:
        return 97
    elif code == 48:
        return 98
    elif code == 54:
        return 104
    elif code == 57:
        return 107
    elif code == 60:
        return 110
    elif code == 61:
        return 111
    elif code == 62:
        return 40
    elif code == 63:
        return 36
    elif code == 66:
        return 39
    elif code == 78:
        return 38
    end
    return 5
end

function last_errno():
    return 0 - errno_of(__lsl_qbe_s32(__lsl_qbe_load32(__lsl_qbe_call0(__lsl_symbol("__error")))))
end

# Výsledek int funkce (-1 = chyba v errno).
function checked(result):
    value = int32(result)
    if value == -1:
        return last_errno()
    end
    return value
end

# Výsledek ssize_t/off_t funkce.
function checked64(result):
    if result == -1:
        return last_errno()
    end
    return result
end

function syscall6(number, a, b, c, d, e, f):
    return 0 - platform.ENOSYS
end

# Paměť.
function mmap(address, length, protection, flags, descriptor, offset):
    return checked64(__lsl_qbe_call6(__lsl_symbol("mmap"), address, length, protection, flags, descriptor, offset))
end

function mprotect(address, length, protection):
    return checked(__lsl_qbe_call3(__lsl_symbol("mprotect"), address, length, protection))
end

function munmap(address, length):
    return checked(__lsl_qbe_call2(__lsl_symbol("munmap"), address, length))
end

function unmap(address, length):
    return munmap(address, length)
end

function map_anonymous(size, extra_flags):
    return mmap(0, size, 3, MAC_MAP_PRIVATE | MAC_MAP_ANON, -1, 0)
end

# Začátek haldy. mmap bere adresu jen jako nápovědu a na arm64 by halda
# rychle narazila na sdílenou cache dyld, proto se adresní prostor haldy
# (HEAP_RESERVE) vyhradí předem bez přístupu; map_at v něm jen zpřístupní
# stránky (mprotect). Rezervace: lsl_mac_heap +0 začátek, +8 konec. Když
# se nepovede, platí navržená adresa jako na Linuxu.
HEAP_RESERVE = 68719476736
HEAP_ALIGN = 65536

function heap_base(hint):
    reserved = mmap(0, HEAP_RESERVE + HEAP_ALIGN, 0, MAC_MAP_PRIVATE | MAC_MAP_ANON, -1, 0)
    if reserved < 0:
        return hint
    end
    start = (reserved + HEAP_ALIGN - 1) & -HEAP_ALIGN
    region = __lsl_symbol("lsl_mac_heap")
    __lsl_qbe_store64(region, start)
    __lsl_qbe_store64(region + 8, start + HEAP_RESERVE)
    return start
end

# Paměť přesně na adrese: 1 = hotovo, 0 = místo je obsazené. Uvnitř
# rezervace haldy mprotect, jinak mmap s adresou jako nápovědou (výsledek
# se porovná).
function map_at(address, size):
    region = __lsl_symbol("lsl_mac_heap")
    start = __lsl_qbe_load64(region)
    if start != 0 and not __lsl_qbe_ult(address, start) and not __lsl_qbe_ult(__lsl_qbe_load64(region + 8), address + size):
        return mprotect(address, size, 3) == 0
    end
    result = mmap(address, size, 3, MAC_MAP_PRIVATE | MAC_MAP_ANON, -1, 0)
    if result == address:
        return 1
    end
    if result >= 0:
        call munmap(result, size)
    end
    return 0
end

function map_shared(fd, length, offset):
    return mmap(0, length, 3, MAC_MAP_SHARED, fd, offset)
end

# Soubory.
function open_flags(flags):
    result = flags & 3
    if flags & platform.O_CREAT != 0:
        result = result | MAC_O_CREAT
    end
    if flags & platform.O_TRUNC != 0:
        result = result | MAC_O_TRUNC
    end
    if flags & platform.O_EXCL != 0:
        result = result | MAC_O_EXCL
    end
    if flags & platform.O_APPEND != 0:
        result = result | MAC_O_APPEND
    end
    if flags & platform.O_NONBLOCK != 0:
        result = result | MAC_O_NONBLOCK
    end
    if flags & platform.O_NOFOLLOW != 0:
        result = result | MAC_O_NOFOLLOW
    end
    if flags & platform.O_CLOEXEC != 0:
        result = result | MAC_O_CLOEXEC
    end
    if flags & platform.O_DIRECTORY != 0:
        result = result | 1048576
    end
    return result
end

function open(path, flags, mode):
    return checked(__lsl_qbe_call3(__lsl_symbol("lsl_arch_open"), path, open_flags(flags), mode))
end

function read(fd, buffer, count):
    return checked64(__lsl_qbe_call3(__lsl_symbol("read"), fd, buffer, count))
end

function write(fd, buffer, count):
    return checked64(__lsl_qbe_call3(__lsl_symbol("write"), fd, buffer, count))
end

function pread(fd, buffer, count, offset):
    return checked64(__lsl_qbe_call4(__lsl_symbol("pread"), fd, buffer, count, offset))
end

function lseek(fd, offset, whence):
    return checked64(__lsl_qbe_call3(__lsl_symbol("lseek"), fd, offset, whence))
end

function close(fd):
    return checked(__lsl_qbe_call1(__lsl_symbol("close"), fd))
end

function ioctl(fd, request, argument):
    return checked(__lsl_qbe_call3(__lsl_symbol("lsl_arch_ioctl"), fd, request, argument))
end

function fcntl(fd, command, argument):
    return checked(__lsl_qbe_call3(__lsl_symbol("lsl_arch_fcntl"), fd, command, argument))
end

# Druh souboru (S_IFMT >> 12: 8 soubor, 1 roura, 2 znakové zařízení).
function file_kind(fd):
    status = __lsl_qbe_alloc(STAT_BYTES)
    result = checked(__lsl_qbe_call2(__lsl_symbol("lsl_arch_fstat"), fd, status))
    if result < 0:
        return result
    end
    return __lsl_qbe_lshr(__lsl_qbe_load16(status + STAT_MODE), 12) & 15
end

function is_terminal(fd):
    return int32(__lsl_qbe_call1(__lsl_symbol("isatty"), fd)) == 1
end

function make_directory(path, mode):
    return checked(__lsl_qbe_call2(__lsl_symbol("mkdir"), path, mode))
end

function remove_file(path):
    return checked(__lsl_qbe_call1(__lsl_symbol("unlink"), path))
end

function remove_directory(path):
    return checked(__lsl_qbe_call1(__lsl_symbol("rmdir"), path))
end

# Přejmenování bez přepsání cíle (renamex_np, RENAME_EXCL; macOS 10.12+).
function rename_path(source, destination):
    return checked(__lsl_qbe_call3(__lsl_symbol("renamex_np"), source, destination, 4))
end

function access(path):
    return checked(__lsl_qbe_call2(__lsl_symbol("access"), path, 0))
end

# socket s příznaky Linuxu (SOCK_CLOEXEC, SOCK_NONBLOCK přes fcntl).
function socket(domain, kind, protocol):
    fd = checked(__lsl_qbe_call3(__lsl_symbol("socket"), domain, kind & ~(LINUX_SOCK_NONBLOCK | LINUX_SOCK_CLOEXEC), protocol))
    if fd < 0:
        return fd
    end
    if kind & LINUX_SOCK_CLOEXEC != 0:
        call fcntl(fd, F_SETFD, FD_CLOEXEC)
    end
    if kind & LINUX_SOCK_NONBLOCK != 0:
        call fcntl(fd, F_SETFL, fcntl(fd, F_GETFL, 0) | MAC_O_NONBLOCK)
    end
    return fd
end

# Adresa ve tvaru Linuxu (rodina 16 bitů) -> BSD (délka, rodina 8 bitů).
function connect(fd, address, length):
    if length < 2 or length > 255:
        return 0 - platform.EINVAL
    end
    converted = __lsl_qbe_alloc(256)
    index = 0
    while index < length:
        __lsl_qbe_store8(converted + index, __lsl_qbe_load8(address + index))
        index += 1
    end
    __lsl_qbe_store8(converted, length)
    __lsl_qbe_store8(converted + 1, __lsl_qbe_load8(address))
    return checked(__lsl_qbe_call3(__lsl_symbol("connect"), fd, converted, length))
end

function exit_process(status):
    call __lsl_qbe_call1(__lsl_symbol("_exit"), status)
    return 0
end

# Čekání na slovo (futex Linuxu) přes __ulock_wait: porovná 32 bitů.
function futex_wait(address, expected):
    call __lsl_qbe_call4(__lsl_symbol("__ulock_wait"), UL_COMPARE_AND_WAIT, address, expected & 4294967295, 0)
    return 0
end

function futex_wait_timeout(address, expected, timespec):
    microseconds = __lsl_qbe_load64(timespec) * 1000000 + __lsl_qbe_udiv(__lsl_qbe_load64(timespec + 8) + 999, 1000)
    if microseconds <= 0:
        microseconds = 1
    elif microseconds > 4294967295:
        microseconds = 4294967295
    end
    call __lsl_qbe_call4(__lsl_symbol("__ulock_wait"), UL_COMPARE_AND_WAIT, address, expected & 4294967295, microseconds)
    return 0
end

function futex_wake(address, count):
    operation = UL_COMPARE_AND_WAIT
    if count != 1:
        operation = operation | ULF_WAKE_ALL
    end
    call __lsl_qbe_call3(__lsl_symbol("__ulock_wake"), operation, address, 0)
    return 0
end

function getpid():
    return int32(__lsl_qbe_call0(__lsl_symbol("getpid")))
end

# Identita vlákna: systémově jedinečné ID (pthread_threadid_np). pthread_t
# nestačí: macOS ho po skončení vlákna hned přidělí dalšímu.
function gettid():
    identifier = __lsl_qbe_alloc(8)
    __lsl_qbe_store64(identifier, 0)
    call __lsl_qbe_call2(__lsl_symbol("pthread_threadid_np"), 0, identifier)
    return __lsl_qbe_load64(identifier)
end

# pthread_t vlákna položky (pro pthread_kill) v lsl_mac_threads.
function thread_handle(entry):
    index = __lsl_qbe_lshr(entry - __lsl_qbe_load64(core.state() + THREAD_TABLE) - 8, 6)
    return __lsl_symbol("lsl_mac_threads") + __lsl_qbe_shl(index, 3)
end

function sched_yield():
    call __lsl_qbe_call0(__lsl_symbol("sched_yield"))
    return 0
end

# Počet CPU jako maska afinity (macOS afinitu procesu nemá).
function sched_getaffinity(size, mask):
    count = __lsl_qbe_call1(__lsl_symbol("sysconf"), MAC_SC_NPROCESSORS_ONLN)
    if count < 1:
        count = 1
    end
    if count > __lsl_qbe_shl(size, 3):
        count = __lsl_qbe_shl(size, 3)
    end
    index = 0
    while index < size:
        __lsl_qbe_store8(mask + index, 0)
        index += 1
    end
    index = 0
    while index < count:
        byte = mask + __lsl_qbe_lshr(index, 3)
        __lsl_qbe_store8(byte, __lsl_qbe_load8(byte) | __lsl_qbe_shl(1, index & 7))
        index += 1
    end
    return __lsl_qbe_lshr(count + 7, 3)
end

function os_clock_gettime(clock, timespec):
    identifier = 0
    if clock == platform.CLOCK_MONOTONIC:
        identifier = MAC_CLOCK_MONOTONIC
    end
    return checked(__lsl_qbe_call2(__lsl_symbol("clock_gettime"), identifier, timespec))
end

function os_nanosleep(request, remaining):
    return checked(__lsl_qbe_call2(__lsl_symbol("nanosleep"), request, remaining))
end

# Start procesu: TSD slot bloku vlákna a blok argumentů jako na zásobníku
# Linuxu (argc, argv[0..argc-1], 0, prostředí, 0) z argumentů main. Řetězce
# zůstávají, kde je nechal dyld. Blok, nebo 0 při chybě.
function process_arguments(stack):
    key = __lsl_qbe_alloc(8)
    __lsl_qbe_store64(key, 0)
    if int32(__lsl_qbe_call2(__lsl_symbol("pthread_key_create"), key, 0)) != 0:
        return 0
    end
    __lsl_qbe_store64(__lsl_symbol("lsl_tls_slot"), __lsl_qbe_load64(key))
    arguments = __lsl_symbol("lsl_mac_args")
    argc = int32(__lsl_qbe_load64(arguments))
    argv = __lsl_qbe_load64(arguments + 8)
    envp = __lsl_qbe_load64(arguments + 16)
    count = 0
    while envp != 0 and __lsl_qbe_load64(envp + __lsl_qbe_shl(count, 3)) != 0:
        count += 1
    end
    block = map_anonymous(__lsl_qbe_shl(argc + count + 3, 3), 0)
    if block < 0:
        return 0
    end
    __lsl_qbe_store64(block, argc)
    index = 0
    while index < argc:
        __lsl_qbe_store64(block + 8 + __lsl_qbe_shl(index, 3), __lsl_qbe_load64(argv + __lsl_qbe_shl(index, 3)))
        index += 1
    end
    environment = block + __lsl_qbe_shl(argc + 2, 3)
    index = 0
    while index < count:
        __lsl_qbe_store64(environment + __lsl_qbe_shl(index, 3), __lsl_qbe_load64(envp + __lsl_qbe_shl(index, 3)))
        index += 1
    end
    return block
end

function os_environment():
    block = __lsl_qbe_load64(__lsl_qbe_load64(__lsl_symbol("lsl_state")) + MAIN_STACK_TOP)
    return block + __lsl_qbe_shl(__lsl_qbe_load64(block) + 2, 3)
end

# Cesta ke spuštěnému programu (bez NUL), délka nebo záporná chyba.
function os_executable_path(buffer, size):
    capacity = __lsl_qbe_alloc(8)
    __lsl_qbe_store64(capacity, size)
    if int32(__lsl_qbe_call2(__lsl_symbol("_NSGetExecutablePath"), buffer, capacity)) != 0:
        return 0 - platform.ENAMETOOLONG
    end
    length = 0
    while length < size and __lsl_qbe_load8(buffer + length) != 0:
        length += 1
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
        if written > 0:
            buffer += written
            count -= written
        elif written != 0 - platform.EINTR:
            return -1
        end
    end
    return 0
end

# Anonymní soubor (memfd Linuxu): dočasný soubor v $TMPDIR, hned smazaný.
function os_memfd(name):
    template = __lsl_qbe_alloc(1088)
    length = 0
    directory = environment_value("TMPDIR")
    if directory == 0:
        directory = __lsl_address("/tmp") + 16
    end
    while __lsl_qbe_load8(directory + length) != 0 and length < 1024:
        __lsl_qbe_store8(template + length, __lsl_qbe_load8(directory + length))
        length += 1
    end
    suffix = __lsl_address("/lsl.XXXXXX") + 16
    index = 0
    while index <= 11:
        __lsl_qbe_store8(template + length + index, __lsl_qbe_load8(suffix + index))
        index += 1
    end
    fd = checked(__lsl_qbe_call2(__lsl_symbol("mkostemp"), template, MAC_O_CLOEXEC))
    if fd >= 0:
        call __lsl_qbe_call1(__lsl_symbol("unlink"), template)
    end
    return fd
end

# Hodnota proměnné prostředí jako C řetězec, nebo 0.
function environment_value(name):
    entry_pointer = os_environment()
    length = __lsl_qbe_load64(name + 8)
    while __lsl_qbe_load64(entry_pointer) != 0:
        entry = __lsl_qbe_load64(entry_pointer)
        index = 0
        while index < length and __lsl_qbe_load8(entry + index) == __lsl_qbe_load8(name + 16 + index):
            index += 1
        end
        if index == length and __lsl_qbe_load8(entry + length) == 61:
            return entry + length + 1
        end
        entry_pointer += 8
    end
    return 0
end

# Roura s FD_CLOEXEC: fds dostane dvě 32bitová čísla (čtení, zápis).
function os_pipe(fds):
    result = checked(__lsl_qbe_call1(__lsl_symbol("pipe"), fds))
    if result < 0:
        return result
    end
    call fcntl(__lsl_qbe_s32(__lsl_qbe_load32(fds)), F_SETFD, FD_CLOEXEC)
    call fcntl(__lsl_qbe_s32(__lsl_qbe_load32(fds + 4)), F_SETFD, FD_CLOEXEC)
    return 0
end

function os_limit_descriptors(limit):
    rlimit = __lsl_qbe_alloc(16)
    __lsl_qbe_store64(rlimit, limit)
    __lsl_qbe_store64(rlimit + 8, limit)
    return checked(__lsl_qbe_call2(__lsl_symbol("setrlimit"), MAC_RLIMIT_NOFILE, rlimit))
end

function os_wait(pid):
    if pid == SPAWN_FAILED:
        return 127
    end
    status = __lsl_qbe_alloc(8)
    while True:
        __lsl_qbe_store64(status, 0)
        result = checked(__lsl_qbe_call3(__lsl_symbol("waitpid"), pid, status, 0))
        if result != 0 - platform.EINTR:
            break
        end
    end
    if result < 0:
        return result
    end
    return os_exit_code(__lsl_qbe_load32(status))
end

function os_exit_code(status):
    signal = status & 127
    if signal != 0:
        return signal + 128
    end
    return __lsl_qbe_lshr(status, 8) & 255
end

function os_kill(pid):
    if pid == SPAWN_FAILED:
        return 0
    end
    return checked(__lsl_qbe_call2(__lsl_symbol("kill"), pid, 9))
end

# Spustí program bez shellu (posix_spawn, bez hledání v PATH). argv je pole
# ukazatelů na C řetězce zakončené nulou, clean vybere prázdné prostředí.
# output < 0: potomek dostane standardní deskriptory rodiče (run), jinak
# input (< 0 stdin rodiče), output a error (capture). Díky
# POSIX_SPAWN_CLOEXEC_DEFAULT potomek zdědí jen tyto tři deskriptory.
# Limity velikosti souborů a core dumpů posix_spawn nenastaví (na rozdíl od
# Linuxu). Vrací pid, SPAWN_FAILED (program nejde spustit), nebo chybu.
function os_spawn(path, argv, clean, input, output, error, parent_end):
    actions = __lsl_qbe_alloc(8)
    attributes = __lsl_qbe_alloc(8)
    pid = __lsl_qbe_alloc(8)
    __lsl_qbe_store64(pid, 0)
    if int32(__lsl_qbe_call1(__lsl_symbol("posix_spawn_file_actions_init"), actions)) != 0:
        return 0 - platform.ENOMEM
    end
    if int32(__lsl_qbe_call1(__lsl_symbol("posix_spawnattr_init"), attributes)) != 0:
        call __lsl_qbe_call1(__lsl_symbol("posix_spawn_file_actions_destroy"), actions)
        return 0 - platform.ENOMEM
    end
    call __lsl_qbe_call2(__lsl_symbol("posix_spawnattr_setflags"), attributes, POSIX_SPAWN_CLOEXEC_DEFAULT)
    if output >= 0:
        call spawn_stream(actions, input, 0)
        call spawn_stream(actions, output, 1)
        call spawn_stream(actions, error, 2)
    else:
        call spawn_stream(actions, -1, 0)
        call spawn_stream(actions, -1, 1)
        call spawn_stream(actions, -1, 2)
    end
    environment = 0
    if clean:
        environment = __lsl_qbe_alloc(8)
        __lsl_qbe_store64(environment, 0)
    else:
        environment = os_environment()
    end
    result = int32(__lsl_qbe_call6(__lsl_symbol("posix_spawn"), pid, path, actions, attributes, argv, environment))
    call __lsl_qbe_call1(__lsl_symbol("posix_spawn_file_actions_destroy"), actions)
    call __lsl_qbe_call1(__lsl_symbol("posix_spawnattr_destroy"), attributes)
    if result != 0:
        return SPAWN_FAILED
    end
    return int32(__lsl_qbe_load64(pid))
end

# Deskriptor target v potomkovi: source < 0 nebo stejné číslo = zdědit.
function spawn_stream(actions, source, target):
    if source < 0 or source == target:
        call __lsl_qbe_call2(__lsl_symbol("posix_spawn_file_actions_addinherit_np"), actions, target)
    else:
        call __lsl_qbe_call3(__lsl_symbol("posix_spawn_file_actions_adddup2"), actions, source, target)
    end
    return 0
end

# Vlákna: pthread_create s 8 MiB zásobníkem, odpojené. Vlákno se zveřejní
# samo v lsl_thread_begin (vrchol zásobníku z pthread_get_stackaddr_np).
function thread_stack(top, size, guard):
    return 0
end

# Volá se pod zámkem tabulky vláken: vlákno se zveřejní až po uložení
# pthread_t. tid = jedinečné ID vlákna.
function thread_start(entry, top, function):
    attributes = __lsl_qbe_alloc(128)
    thread = __lsl_qbe_alloc(8)
    __lsl_qbe_store64(thread, 0)
    if int32(__lsl_qbe_call1(__lsl_symbol("pthread_attr_init"), attributes)) != 0:
        return -1
    end
    call __lsl_qbe_call2(__lsl_symbol("pthread_attr_setstacksize"), attributes, STACK_BYTES)
    call __lsl_qbe_call2(__lsl_symbol("pthread_attr_setdetachstate"), attributes, PTHREAD_CREATE_DETACHED)
    result = int32(__lsl_qbe_call4(__lsl_symbol("pthread_create"), thread, attributes, __lsl_symbol("lsl_arch_thread_start"), entry))
    call __lsl_qbe_call1(__lsl_symbol("pthread_attr_destroy"), attributes)
    if result != 0:
        return -1
    end
    __lsl_qbe_store64(thread_handle(entry), __lsl_qbe_load64(thread))
    identifier = __lsl_qbe_alloc(8)
    __lsl_qbe_store64(identifier, 0)
    call __lsl_qbe_call2(__lsl_symbol("pthread_threadid_np"), __lsl_qbe_load64(thread), identifier)
    return __lsl_qbe_load64(identifier)
end

# Konec vlákna: stav 1 -> 0 a probudit čekající join. Když GC vlákno právě
# zastavuje (stav 4 nebo 2), počká se, až ho signál pustí.
function thread_exit(entry):
    while __lsl_qbe_call3(__lsl_symbol("lsl_arch_cas64"), entry + 16, 1, 0) != 1:
        call sched_yield()
    end
    call futex_wake(entry + 16, 2147483647)
    call __lsl_qbe_call1(__lsl_symbol("pthread_exit"), 0)
    return 0
end

# Zastavení pro GC: SIGUSR1 (obsluha lsl_thread_signal uloží registry
# na zásobník vlákna a uspí se na bráně GC, jako na Linuxu).
function thread_suspend(process, entry):
    return int32(__lsl_qbe_call2(__lsl_symbol("pthread_kill"), __lsl_qbe_load64(thread_handle(entry)), MAC_SIGUSR1))
end

function thread_resume(entry):
    return 0
end

function thread_registers(entry):
    return 0
end

# Obsluha SIGUSR1 pro zastavení světa; SA_RESTART: vnitřní GC nesmí vracet
# EINTR z I/O ani čekání na procesy. struct sigaction: +0 obsluha,
# +8 maska (32 bitů), +12 příznaky.
function install_thread_suspend():
    action = __lsl_qbe_alloc(16)
    __lsl_qbe_store64(action, __lsl_symbol("lsl_thread_signal"))
    __lsl_qbe_store32(action + 8, 0)
    __lsl_qbe_store32(action + 12, MAC_SA_RESTART)
    return checked(__lsl_qbe_call3(__lsl_symbol("sigaction"), MAC_SIGUSR1, action, 0))
end

function tgkill(process, thread, signal):
    return 0 - platform.ENOSYS
end

# Časový limit potomka capture: hlídací vlákno (pthread bez bloku vlákna
# runtime, volá jen libSystem) po milliseconds pošle SIGTERM a po sekundě
# SIGKILL jako coreutils timeout. Hlídání (mmap): +0 pid, +8 limit v ms,
# +16 stav (0 čeká, 1 ukončuje, 2 zrušeno, 3 ukončeno), +24 vypršelo.
# Zrušení proběhne před úklidem potomka, signál tak nezasáhne cizí proces.
# Paměť uvolní hlídač po zrušení (stav 2), jinak rušící strana.
WATCH_BYTES = 16384

function process_deadline(pid, milliseconds):
    watch = map_anonymous(WATCH_BYTES, 0)
    if watch < 0:
        return 0
    end
    __lsl_qbe_store64(watch, pid)
    __lsl_qbe_store64(watch + 8, milliseconds)
    if pid == SPAWN_FAILED:
        __lsl_qbe_store64(watch + 16, 3)
        return watch
    end
    attributes = __lsl_qbe_alloc(128)
    thread = __lsl_qbe_alloc(8)
    if int32(__lsl_qbe_call1(__lsl_symbol("pthread_attr_init"), attributes)) != 0:
        call munmap(watch, WATCH_BYTES)
        return 0
    end
    call __lsl_qbe_call2(__lsl_symbol("pthread_attr_setdetachstate"), attributes, PTHREAD_CREATE_DETACHED)
    result = int32(__lsl_qbe_call4(__lsl_symbol("pthread_create"), thread, attributes, __lsl_symbol("lsl_process_watchdog"), watch))
    call __lsl_qbe_call1(__lsl_symbol("pthread_attr_destroy"), attributes)
    if result != 0:
        call munmap(watch, WATCH_BYTES)
        return 0
    end
    return watch
end

# Spí po 10 ms, dokud limit nevyprší nebo hlídání nezruší capture.
function watchdog_sleep(watch, milliseconds):
    request = __lsl_qbe_alloc(16)
    waited = 0
    while waited < milliseconds:
        if __lsl_qbe_load64(watch + 16) == 2:
            return 0
        end
        __lsl_qbe_store64(request, 0)
        __lsl_qbe_store64(request + 8, 10000000)
        call __lsl_qbe_call2(__lsl_symbol("nanosleep"), request, 0)
        waited += 10
    end
    return 1
end

function lsl_process_watchdog(watch):
    if watchdog_sleep(watch, __lsl_qbe_load64(watch + 8)) and __lsl_qbe_call3(__lsl_symbol("lsl_arch_cas64"), watch + 16, 0, 1) == 0:
        __lsl_qbe_store64(watch + 24, 1)
        call __lsl_qbe_call2(__lsl_symbol("kill"), __lsl_qbe_load64(watch), 15)
        request = __lsl_qbe_alloc(16)
        __lsl_qbe_store64(request, 1)
        __lsl_qbe_store64(request + 8, 0)
        call __lsl_qbe_call2(__lsl_symbol("nanosleep"), request, 0)
        call __lsl_qbe_call2(__lsl_symbol("kill"), __lsl_qbe_load64(watch), 9)
        call __lsl_qbe_call2(__lsl_symbol("lsl_arch_xchg64"), watch + 16, 3)
        return 0
    end
    # Zrušeno: hlídání patří hlídači.
    call __lsl_qbe_call2(__lsl_symbol("munmap"), watch, WATCH_BYTES)
    return 0
end

# 1, když limit vypršel (potomek ukončen).
function process_deadline_cancel(watch):
    if __lsl_qbe_load64(watch + 16) != 3 and __lsl_qbe_call3(__lsl_symbol("lsl_arch_cas64"), watch + 16, 0, 2) == 0:
        return 0
    end
    while __lsl_qbe_load64(watch + 16) != 3:
        call sched_yield()
    end
    expired = __lsl_qbe_load64(watch + 24)
    call munmap(watch, WATCH_BYTES)
    return expired
end

# Počká na skončení potomka bez jeho úklidu (waitid s WNOWAIT): pid zůstane
# obsazený, dokud ho os_wait neuklidí. siginfo_t má 104 B.
P_PID = 1
WEXITED = 4
WNOWAIT = 32

function os_wait_exit(pid):
    if pid == SPAWN_FAILED:
        return 0
    end
    information = __lsl_qbe_alloc(128)
    while True:
        result = checked(__lsl_qbe_call4(__lsl_symbol("waitid"), P_PID, pid, information, WEXITED | WNOWAIT))
        if result != 0 - platform.EINTR:
            return result
        end
    end
    return 0
end

# Vlákno běží samo od thread_start; nic nečeká na spuštění.
function thread_run_pending(entry):
    return 0
end

# Výpis adresáře (__lsl_list_directory): opendir/readdir z libSystem
# (most lsl_arch_* kvůli symbolům $INODE64 na x86_64). struct dirent:
# +18 délka jména, +21 jméno. Handle je DIR*.
function directory_open(path):
    directory = __lsl_qbe_call1(__lsl_symbol("lsl_arch_opendir"), path)
    if directory == 0:
        return last_errno()
    end
    return directory
end

function directory_next(directory, buffer, size):
    entry = __lsl_qbe_call1(__lsl_symbol("lsl_arch_readdir"), directory)
    if entry == 0:
        return 0
    end
    length = __lsl_qbe_load16(entry + 18)
    if length > size:
        return 0 - platform.ENAMETOOLONG
    end
    index = 0
    while index < length:
        __lsl_qbe_store8(buffer + index, __lsl_qbe_load8(entry + 21 + index))
        index += 1
    end
    return length
end

function directory_close(directory):
    call __lsl_qbe_call1(__lsl_symbol("closedir"), directory)
    return 0
end
