# macOS x86_64: konstanty platformy pro runtime a knihovny. macOS nedovoluje
# přímá systémová volání; runtime volá libSystem (runtime/os_macos.lsl).
# Příznaky souborů, errno a hodiny mají hodnoty Linuxu: jsou to jen hodnoty
# rozhraní vrstvy OS, která je převádí na hodnoty macOS.

NAME = "macos-x86_64"
RUNTIME = "lsl-runtime-macos-x86_64-v1"

# Formát nativních obrazů (stdlib native): macOS je zatím nenačítá.
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

# Paměť: příznak bez významu na macOS.
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

# Adresáře (open).
O_DIRECTORY = 65536
