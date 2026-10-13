# lsl: runtime
# Vrstva OS pro Linux: jediné místo runtime se systémovými voláními Linuxu.
# Používá jen volání, která mají x86_64, arm64 i rv64 (openat místo open,
# pipe2, dup3, clone místo fork…); čísla dodá modul platformy cíle.
load _platform as platform

function syscall6(number, a, b, c, d, e, f):
    return __lsl_qbe_call7(__lsl_symbol("lsl_arch_syscall6"), number, a, b, c, d, e, f)
end

function syscall3(number, a, b, c):
    return __lsl_qbe_call7(__lsl_symbol("lsl_arch_syscall6"), number, a, b, c, 0, 0, 0)
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
