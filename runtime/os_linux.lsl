# lsl: runtime
# Vrstva OS pro Linux: jediné místo runtime se systémovými voláními Linuxu.
# Používá jen volání, která mají x86_64, arm64 i rv64 (openat místo open,
# pipe2, dup3, clone místo fork…); čísla dodá modul platformy cíle.
# Výsledek je surový výsledek jádra (záporné errno při chybě).
load _platform as platform

function syscall6(number, a, b, c, d, e, f):
    return __lsl_qbe_call7(__lsl_symbol("lsl_arch_syscall6"), number, a, b, c, d, e, f)
end

function syscall3(number, a, b, c):
    return __lsl_qbe_call4(__lsl_symbol("lsl_arch_syscall3"), number, a, b, c)
end

# Soubory a paměť. Výsledek je hodnota jádra, chyba je záporné errno.
function openat(directory, path, flags, mode):
    return syscall6(platform.SYS_OPENAT, directory, path, flags, mode, 0, 0)
end

function lseek(descriptor, offset, whence):
    return syscall3(platform.SYS_LSEEK, descriptor, offset, whence)
end

function read(descriptor, buffer, count):
    return syscall3(platform.SYS_READ, descriptor, buffer, count)
end

function close(descriptor):
    return syscall3(platform.SYS_CLOSE, descriptor, 0, 0)
end

function mmap(address, length, protection, flags, descriptor, offset):
    return syscall6(platform.SYS_MMAP, address, length, protection, flags, descriptor, offset)
end

function mprotect(address, length, protection):
    return syscall3(platform.SYS_MPROTECT, address, length, protection)
end

function munmap(address, length):
    return syscall3(platform.SYS_MUNMAP, address, length, 0)
end

# Procesy a deskriptory.
function pipe2(fds, flags):
    return syscall3(platform.SYS_PIPE2, fds, flags, 0)
end

# fork přes clone (arm64 ani rv64 fork nemají): v dítěti 0, v rodiči pid.
function fork():
    return syscall6(platform.SYS_CLONE, platform.SIGCHLD, 0, 0, 0, 0, 0)
end

function dup3(old, new, flags):
    return syscall3(platform.SYS_DUP3, old, new, flags)
end

function close_range(first, last, flags):
    return syscall3(platform.SYS_CLOSE_RANGE, first, last, flags)
end

function wait4(pid, status, options):
    return syscall6(platform.SYS_WAIT4, pid, status, options, 0, 0, 0)
end

function prctl(option, argument):
    return syscall6(platform.SYS_PRCTL, option, argument, 0, 0, 0, 0)
end

# Ukončí volající vlákno (exit, ne exit_group: povolí ho i strict seccomp).
function exit_thread(status):
    return syscall3(platform.SYS_EXIT, status, 0, 0)
end

# SIGALRM za seconds sekund (alarm přes setitimer, arm64 ani rv64 alarm nemají).
function alarm(seconds):
    timer = __lsl_qbe_alloc(platform.ITIMERVAL_BYTES)
    __lsl_qbe_zero(timer, 32)
    __lsl_qbe_store64(timer + platform.ITIMERVAL_VALUE_SECONDS, seconds)
    return syscall3(platform.SYS_SETITIMER, platform.ITIMER_REAL, timer, 0)
end

function syscall4(number, a, b, c, d):
    return __lsl_qbe_call7(__lsl_symbol("lsl_arch_syscall6"), number, a, b, c, d, 0, 0)
end

# Soubory: cesta je C řetězec (adresa bajtů zakončených nulou).
function open(path, flags, mode):
    return syscall4(platform.SYS_OPENAT, platform.AT_FDCWD, path, flags, mode)
end

function write(fd, buffer, count):
    return syscall3(platform.SYS_WRITE, fd, buffer, count)
end

function pread(fd, buffer, count, offset):
    return syscall4(platform.SYS_PREAD64, fd, buffer, count, offset)
end

function ioctl(fd, request, argument):
    return syscall3(platform.SYS_IOCTL, fd, request, argument)
end

# Druh souboru deskriptoru (S_IFMT >> 12: 8 soubor, 1 roura, 2 znakové
# zařízení), nebo záporné errno. fstat jako newfstatat(fd, "", AT_EMPTY_PATH).
function file_kind(fd):
    status = __lsl_qbe_alloc(platform.STAT_BYTES + 8)
    # Prázdná cesta: nulový bajt za strukturou.
    empty = status + platform.STAT_BYTES
    __lsl_qbe_store64(empty, 0)
    result = syscall4(platform.SYS_NEWFSTATAT, fd, empty, status, platform.AT_EMPTY_PATH)
    if result < 0:
        return result
    end
    return __lsl_qbe_lshr(__lsl_qbe_load32(status + platform.STAT_MODE), 12) & 15
end

# Úspěch ioctl(TCGETS) pozná terminál bez libc.
function is_terminal(fd):
    termios = __lsl_qbe_alloc(64)
    return syscall3(platform.SYS_IOCTL, fd, platform.TCGETS, termios) >= 0
end

function make_directory(path, mode):
    return syscall3(platform.SYS_MKDIRAT, platform.AT_FDCWD, path, mode)
end

function remove_file(path):
    return syscall3(platform.SYS_UNLINKAT, platform.AT_FDCWD, path, 0)
end

function remove_directory(path):
    return syscall3(platform.SYS_UNLINKAT, platform.AT_FDCWD, path, platform.AT_REMOVEDIR)
end

# 0, když cesta existuje (F_OK).
function access(path):
    return syscall4(platform.SYS_FACCESSAT, platform.AT_FDCWD, path, 0, 0)
end

function socket(domain, kind, protocol):
    return syscall3(platform.SYS_SOCKET, domain, kind, protocol)
end

function connect(fd, address, length):
    return syscall3(platform.SYS_CONNECT, fd, address, length)
end

# Paměť: adresa, nebo záporné errno.
function map_shared(fd, length, offset):
    return syscall6(platform.SYS_MMAP, 0, length, platform.PROT_READ | platform.PROT_WRITE, platform.MAP_SHARED, fd, offset)
end

function unmap(address, length):
    return syscall3(platform.SYS_MUNMAP, address, length, 0)
end

# Ukončí celý proces (všechna vlákna).
function exit_process(status):
    return syscall3(platform.SYS_EXIT_GROUP, status, 0, 0)
end

# Konec haldy brk; brk(0) vrátí současný konec.
function brk(address):
    return syscall3(platform.SYS_BRK, address, 0, 0)
end

# Anonymní soukromé mapování paměti (čtení a zápis); záporné = chyba.
function map_anonymous(size, extra_flags):
    return syscall6(platform.SYS_MMAP, 0, size, platform.PROT_READ | platform.PROT_WRITE, platform.MAP_PRIVATE | platform.MAP_ANONYMOUS | extra_flags, -1, 0)
end

function futex_wait(address, expected):
    return syscall6(platform.SYS_FUTEX, address, platform.FUTEX_WAIT, expected, 0, 0, 0)
end

function futex_wake(address, count):
    return syscall6(platform.SYS_FUTEX, address, platform.FUTEX_WAKE, count, 0, 0, 0)
end

function getpid():
    return syscall3(platform.SYS_GETPID, 0, 0, 0)
end

function tgkill(process, thread, signal):
    return syscall3(platform.SYS_TGKILL, process, thread, signal)
end

function sched_yield():
    return syscall3(platform.SYS_SCHED_YIELD, 0, 0, 0)
end

function syscall1(number, a):
    return __lsl_qbe_call7(__lsl_symbol("lsl_arch_syscall6"), number, a, 0, 0, 0, 0, 0)
end

function os_read(fd, buffer, count):
    return syscall3(platform.SYS_READ, fd, buffer, count)
end

function os_close(fd):
    return syscall1(platform.SYS_CLOSE, fd)
end

function os_lseek(fd, offset, whence):
    return syscall3(platform.SYS_LSEEK, fd, offset, whence)
end

# Zapíše všechny bajty (částečné zápisy, EINTR znovu); 0, nebo -1 při chybě.
function os_write_all(fd, buffer, count):
    while count > 0:
        written = write(fd, buffer, count)
        if written > 0:
            buffer += written
            count -= written
        elif written != -platform.EINTR:
            return -1
        end
    end
    return 0
end

# Anonymní soubor v paměti s O_CLOEXEC (stderr a stdin pro capture).
function os_memfd(name):
    return syscall3(platform.SYS_MEMFD_CREATE, name + 16, platform.MFD_CLOEXEC, 0)
end

# Roura s O_CLOEXEC: fds dostane dvě 32bitová čísla (čtení, zápis).
function os_pipe(fds):
    return syscall3(platform.SYS_PIPE2, fds, platform.O_CLOEXEC, 0)
end

# timespec (sekundy, nanosekundy) hodin CLOCK_MONOTONIC nebo CLOCK_REALTIME.
function os_clock_gettime(clock, timespec):
    return syscall3(platform.SYS_CLOCK_GETTIME, clock, timespec, 0)
end

function os_nanosleep(request, remaining):
    return syscall3(platform.SYS_NANOSLEEP, request, remaining, 0)
end

# Cesta ke spuštěnému programu (bez NUL), délka nebo záporná chyba.
function os_executable_path(buffer, size):
    name = __lsl_address("/proc/self/exe") + 16
    return __lsl_qbe_call7(__lsl_symbol("lsl_arch_syscall6"), platform.SYS_READLINKAT, platform.AT_FDCWD, name, buffer, size, 0, 0)
end

# Prostředí procesu: pole ukazatelů na "JMÉNO=hodnota" zakončené nulou. Leží
# na původním zásobníku procesu (stav +120) za argc a argv s nulou.
function os_environment():
    stack = __lsl_qbe_load64(__lsl_qbe_load64(__lsl_symbol("lsl_state")) + 120)
    return stack + __lsl_qbe_shl(__lsl_qbe_load64(stack) + 2, 3)
end

# RLIMIT_NOFILE na limit (test vyčerpání deskriptorů).
function os_limit_descriptors(limit):
    rlimit = __lsl_qbe_alloc(16)
    __lsl_qbe_store64(rlimit, limit)
    __lsl_qbe_store64(rlimit + 8, limit)
    return __lsl_qbe_call7(__lsl_symbol("lsl_arch_syscall6"), platform.SYS_PRLIMIT64, 0, platform.RLIMIT_NOFILE, rlimit, 0, 0, 0)
end

# Výsledek čekání na potomka: kód ukončení, nebo 128 + číslo signálu;
# záporná chyba wait4 (EINTR se opakuje).
function os_wait(pid):
    status = __lsl_qbe_alloc(8)
    while True:
        __lsl_qbe_store64(status, 0)
        result = __lsl_qbe_call7(__lsl_symbol("lsl_arch_syscall6"), platform.SYS_WAIT4, pid, status, 0, 0, 0, 0)
        if result != -platform.EINTR:
            break
        end
    end
    if result < 0:
        return result
    end
    return os_exit_code(__lsl_qbe_load64(status))
end

function os_exit_code(status):
    signal = status & 127
    if signal != 0:
        return signal + 128
    end
    return __lsl_qbe_ashr(status, 8) & 255
end

function os_kill(pid):
    return syscall3(platform.SYS_KILL, pid, platform.SIGKILL, 0)
end

# Spustí program bez shellu (clone se SIGCHLD = fork). argv je pole
# ukazatelů na C řetězce zakončené nulou, clean vybere prázdné prostředí.
# output < 0: potomek zdědí standardní deskriptory (run), jinak dostane
# input (< 0 zdědí stdin), output a error jako 0, 1, 2 a zavře parent_end
# (capture). Potomek zavře ostatní deskriptory a zakáže core dumpy. Vrací
# pid, nebo zápornou chybu clone.
function os_spawn(path, argv, clean, input, output, error, parent_end):
    rlimit = __lsl_qbe_alloc(16)
    pid = syscall6(platform.SYS_CLONE, platform.SIGCHLD, 0, 0, 0, 0, 0)
    if pid != 0:
        return pid
    end
    # Potomek: chyba přípravy končí 127 (run) nebo 126 (capture).
    failure = 127
    if output >= 0:
        failure = 126
        if not child_redirect(input, output, error, parent_end):
            call syscall1(platform.SYS_EXIT, failure)
        end
    end
    # Potomek nesmí zdědit sockety supervisoru, tajné memfd ani jiné
    # deskriptory rodiče.
    if syscall3(platform.SYS_CLOSE_RANGE, 3, 4294967295, 0) < 0:
        call syscall1(platform.SYS_EXIT, failure)
    end
    if output >= 0:
        # Omezí velikost zapisovaných souborů (i stderr memfd) na 128 MiB;
        # přísnější zděděný limit zůstane.
        if child_limit(rlimit, platform.RLIMIT_FSIZE, -1) < 0:
            call syscall1(platform.SYS_EXIT, failure)
        end
    end
    # Bez core dumpů: argv ani prostředí nesmí skončit na disku.
    if child_limit(rlimit, platform.RLIMIT_CORE, 0) < 0:
        call syscall1(platform.SYS_EXIT, failure)
    end
    environment = 0
    if clean:
        if __lsl_qbe_call7(__lsl_symbol("lsl_arch_syscall6"), platform.SYS_PRCTL, platform.PR_SET_NO_NEW_PRIVS, 1, 0, 0, 0, 0) < 0:
            call syscall1(platform.SYS_EXIT, failure)
        end
    else:
        environment = os_environment()
    end
    call syscall3(platform.SYS_EXECVE, path, argv, environment)
    call syscall1(platform.SYS_EXIT, 127)
    return 0
end

# Limit zdroje v potomkovi: value >= 0 nastaví oba limity, -1 jen sníží oba
# na nejvýš 128 MiB.
function child_limit(rlimit, resource, value):
    if value >= 0:
        __lsl_qbe_store64(rlimit, value)
        __lsl_qbe_store64(rlimit + 8, value)
    else:
        if __lsl_qbe_call7(__lsl_symbol("lsl_arch_syscall6"), platform.SYS_PRLIMIT64, 0, resource, 0, rlimit, 0, 0) < 0:
            return -1
        end
        if __lsl_qbe_ult(134217728, __lsl_qbe_load64(rlimit)):
            __lsl_qbe_store64(rlimit, 134217728)
        end
        if __lsl_qbe_ult(134217728, __lsl_qbe_load64(rlimit + 8)):
            __lsl_qbe_store64(rlimit + 8, 134217728)
        end
    end
    return __lsl_qbe_call7(__lsl_symbol("lsl_arch_syscall6"), platform.SYS_PRLIMIT64, 0, resource, rlimit, 0, 0, 0)
end

# Přesměrování v potomkovi capture. Nejdřív zavře rodičovský konec roury,
# aby dup3 nepřepsal stejné číslo (rodič mohl mít 0/1 zavřené).
function child_redirect(input, output, error, parent_end):
    call os_close(parent_end)
    if input > 0:
        if not child_move(input, 0):
            return 0
        end
    end
    if output != 1:
        if not child_move(output, 1):
            return 0
        end
    end
    if error != 2:
        if not child_move(error, 2):
            return 0
        end
    end
    # pipe2 a memfd mají CLOEXEC. dup3 ho na cíli ruší, ale deskriptor, který
    # už měl cílové číslo, se nepřesouvá: CLOEXEC se proto ruší výslovně.
    if input >= 0:
        if syscall3(platform.SYS_FCNTL, 0, platform.F_SETFD, 0) < 0:
            return 0
        end
    end
    if syscall3(platform.SYS_FCNTL, 1, platform.F_SETFD, 0) < 0:
        return 0
    end
    if syscall3(platform.SYS_FCNTL, 2, platform.F_SETFD, 0) < 0:
        return 0
    end
    return 1
end

function child_move(fd, target):
    if syscall3(platform.SYS_DUP3, fd, target, 0) < 0:
        return 0
    end
    call os_close(fd)
    return 1
end
