# lsl: runtime
# Vrstva OS pro Linux: jediné místo runtime se systémovými voláními Linuxu.
# Používá jen volání, která mají x86_64, arm64 i rv64 (openat místo open,
# pipe2, dup3, clone místo fork…); čísla dodá modul platformy cíle.
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

function write(fd, buffer, count):
    return syscall3(platform.SYS_WRITE, fd, buffer, count)
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
