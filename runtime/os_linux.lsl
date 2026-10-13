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
    return __lsl_qbe_call7(__lsl_symbol("lsl_arch_syscall6"), number, a, b, c, 0, 0, 0)
end

function syscall4(number, a, b, c, d):
    return __lsl_qbe_call7(__lsl_symbol("lsl_arch_syscall6"), number, a, b, c, d, 0, 0)
end

# Soubory: cesta je C řetězec (adresa bajtů zakončených nulou).
function open(path, flags, mode):
    return syscall4(platform.SYS_OPENAT, platform.AT_FDCWD, path, flags, mode)
end

function read(fd, buffer, count):
    return syscall3(platform.SYS_READ, fd, buffer, count)
end

function write(fd, buffer, count):
    return syscall3(platform.SYS_WRITE, fd, buffer, count)
end

function pread(fd, buffer, count, offset):
    return syscall4(platform.SYS_PREAD64, fd, buffer, count, offset)
end

function close(fd):
    return syscall3(platform.SYS_CLOSE, fd, 0, 0)
end

function lseek(fd, offset, whence):
    return syscall3(platform.SYS_LSEEK, fd, offset, whence)
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
function map_anonymous(length):
    return syscall6(platform.SYS_MMAP, 0, length, platform.PROT_READ | platform.PROT_WRITE, platform.MAP_PRIVATE | platform.MAP_ANONYMOUS, -1, 0)
end

function map_shared(fd, length, offset):
    return syscall6(platform.SYS_MMAP, 0, length, platform.PROT_READ | platform.PROT_WRITE, platform.MAP_SHARED, fd, offset)
end

function unmap(address, length):
    return syscall3(platform.SYS_MUNMAP, address, length, 0)
end
