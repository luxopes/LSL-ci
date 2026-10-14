# Windows x86_64: konstanty platformy pro runtime a knihovny. Windows nemá
# stabilní systémová volání; runtime volá Win32 (runtime/os_windows.lsl).
# Příznaky souborů, errno a hodiny mají hodnoty Linuxu: jsou to jen hodnoty
# rozhraní vrstvy OS, která je převádí na Win32.

NAME = "windows-x86_64"
RUNTIME = "lsl-runtime-windows-x86_64-v1"

# Formát nativních obrazů (stdlib native): Windows je zatím nenačítá.
ELF_MACHINE = 62

# Soubory (open) a pozice (lseek).
O_RDONLY = 0
O_WRONLY = 1
O_RDWR = 2
O_CREAT = 64
O_EXCL = 128
O_TRUNC = 512
O_APPEND = 1024
O_NOFOLLOW = 131072
O_CLOEXEC = 524288
SOCK_CLOEXEC = 524288
SEEK_SET = 0
SEEK_CUR = 1
SEEK_END = 2

# Paměť: příznak bez významu na Windows (VirtualAlloc).
MAP_NORESERVE = 16384

# Hodiny (os_clock_gettime).
CLOCK_REALTIME = 0
CLOCK_MONOTONIC = 1

# errno (záporný výsledek vrstvy OS).
EPERM = 1
ENOENT = 2
EINTR = 4
EIO = 5
EBADF = 9
ENOMEM = 12
EACCES = 13
EEXIST = 17
ENOTDIR = 20
EISDIR = 21
EINVAL = 22
ENOTTY = 25
ENOSPC = 28
ESPIPE = 29
EPIPE = 32
ENAMETOOLONG = 36
ENOSYS = 38
ENOTEMPTY = 39
ELOOP = 40
E2BIG = 7
EAGAIN = 11

# Deskriptory a sockety (stdlib fd): hodnoty Linuxu pro rozhraní runtime.
O_NONBLOCK = 2048
AF_UNIX = 1
SOCK_STREAM = 1
UNIX_PATH_MAX = 107
EINPROGRESS = 115

# CONTEXT (GetThreadContext) pro zastavení vláken GC: příznaky, první
# obecný registr, počet registrů a ukazatel zásobníku. AMD64: CONTEXT_AMD64
# | CONTROL | INTEGER, Rax..R15 od 0x78, Rsp na 0x98.
CONTEXT_FLAGS_OFFSET = 48
CONTEXT_FLAGS_VALUE = 1048579
CONTEXT_REGISTERS = 120
CONTEXT_REGISTER_COUNT = 16
CONTEXT_STACK_POINTER = 152
