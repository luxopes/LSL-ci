# lsl: runtime
# Vrstva OS pro Windows x86_64: jediné místo runtime s voláními Win32
# (kernel32, api-ms-win-core-synch). Rozhraní je stejné jako os_linux.lsl:
# - "deskriptor" je HANDLE; 0, 1 a 2 jsou standardní vstup, výstup a chyby
#   (GetStdHandle),
# - chyba je záporné errno s hodnotami Linuxu (GetLastError -> errno),
# - cesty a text jsou UTF-8, funkcím ...W se předávají v UTF-16,
# - příznaky open a hodiny mají hodnoty Linuxu (modul platformy).
# BOOL, DWORD a UINT vrací Win32 jen ve spodních 32 bitech rax: výsledky se
# maskují (dword) před porovnáním.
load _platform as platform

# Krok procházení kořenů GC (zásobníky, registry): 64bitová slova.
ROOT_WORD_BYTES = 8
# Značka adres haldy (jen 32bitový Linux, viz os_linux.lsl).
HEAP_ADDRESS_TAG = 0
load core

function thread_self_publish():
    return 1
end
THREAD_RESUME = 1
# Jména proměnných prostředí bez ohledu na velikost písmen (Path = PATH).
ENV_IGNORE_CASE = 1

THREAD_TABLE = 112
MAIN_STACK_TOP = 120
# Údaje vlákna pro GC: HANDLE a registry z CONTEXT (platforma cíle).
WIN_THREAD_BYTES = 8 + platform.CONTEXT_REGISTER_COUNT * 8
THREAD_REGISTER_BYTES = platform.CONTEXT_REGISTER_COUNT * 8
STACK_BYTES = 8392704

INVALID_HANDLE = -1
INFINITE = 4294967295
CP_UTF8 = 65001
MB_ERR_INVALID_CHARS = 8
# Cesta v UTF-16 nejvýš 32767 znaků (dlouhé cesty Win32) + NUL.
WIDE_PATH_BYTES = 65536
WIDE_PATH_CHARS = 32768

GENERIC_READ = 2147483648
GENERIC_WRITE = 1073741824
FILE_APPEND_DATA = 4
FILE_SHARE_ALL = 7
CREATE_NEW = 1
CREATE_ALWAYS = 2
OPEN_EXISTING = 3
OPEN_ALWAYS = 4
TRUNCATE_EXISTING = 5
FILE_ATTRIBUTE_NORMAL = 128
FILE_ATTRIBUTE_TEMPORARY = 256
FILE_ATTRIBUTE_REPARSE_POINT = 1024
FILE_FLAG_OPEN_REPARSE_POINT = 2097152
FILE_FLAG_DELETE_ON_CLOSE = 67108864
INVALID_ATTRIBUTES = 4294967295
FILE_TYPE_DISK = 1
FILE_TYPE_CHAR = 2
FILE_TYPE_PIPE = 3

MEM_COMMIT_RESERVE = 12288
MEM_RELEASE = 32768
PAGE_READWRITE = 4
FILE_MAP_READ_WRITE = 6


HANDLE_FLAG_INHERIT = 1
STARTF_USESTDHANDLES = 256
EXTENDED_STARTUPINFO_PRESENT = 524288
CREATE_UNICODE_ENVIRONMENT = 1024
PROC_THREAD_ATTRIBUTE_HANDLE_LIST = 131074
# os_spawn: CreateProcessW selhal (program nejde spustit). Není to platný
# HANDLE (ty jsou násobky 4); os_wait vrátí 127 jako potomek po execve.
SPAWN_FAILED = 1
# Délka příkazové řádky CreateProcessW (znaků UTF-16 včetně NUL).
COMMAND_LINE_CHARS = 32767
COMMAND_LINE_BYTES = 98304

ERROR_HANDLE_EOF = 38
ERROR_BROKEN_PIPE = 109

function dword(value):
    return value & 4294967295
end

# errno podle GetLastError.
function last_errno():
    code = dword(__lsl_qbe_call0(__lsl_symbol("GetLastError")))
    return 0 - errno_of(code)
end

function errno_of(code):
    if code == 2 or code == 3 or code == 15 or code == 123 or code == 161:
        return platform.ENOENT
    elif code == 5 or code == 32 or code == 33:
        return platform.EACCES
    elif code == 6:
        return platform.EBADF
    elif code == 8 or code == 14:
        return platform.ENOMEM
    elif code == 80 or code == 183:
        return platform.EEXIST
    elif code == 87 or code == 131:
        return platform.EINVAL
    elif code == 109 or code == 232:
        return platform.EPIPE
    elif code == 112:
        return platform.ENOSPC
    elif code == 145:
        return platform.ENOTEMPTY
    elif code == 206:
        return platform.ENAMETOOLONG
    elif code == 267:
        return platform.ENOTDIR
    end
    return platform.EIO
end

# HANDLE deskriptoru: 0, 1, 2 jsou standardní proudy procesu.
function handle(fd):
    if fd == 0:
        return __lsl_qbe_call1(__lsl_symbol("GetStdHandle"), -10)
    elif fd == 1:
        return __lsl_qbe_call1(__lsl_symbol("GetStdHandle"), -11)
    elif fd == 2:
        return __lsl_qbe_call1(__lsl_symbol("GetStdHandle"), -12)
    end
    return fd
end

# UTF-8 C řetězec -> UTF-16 s NUL do bufferu WIDE_PATH_BYTES; 1, nebo 0.
function wide_path(path, buffer):
    count = dword(__lsl_qbe_call6(__lsl_symbol("MultiByteToWideChar"), CP_UTF8, MB_ERR_INVALID_CHARS, path, -1, buffer, WIDE_PATH_CHARS))
    return count != 0
end

# Systémová volání Linuxu (__lsl_syscall) Windows nemá.
function syscall6(number, a, b, c, d, e, f):
    return 0 - platform.ENOSYS
end

# Paměť: anonymní mapování čtení a zápis (VirtualAlloc po 64 KiB).
function map_anonymous(size, extra_flags):
    address = __lsl_qbe_call4(__lsl_symbol("VirtualAlloc"), 0, size, MEM_COMMIT_RESERVE, PAGE_READWRITE)
    if address == 0:
        return 0 - platform.ENOMEM
    end
    return address
end

# Stránky volného bloku se zde jádru nevracejí.
function release_pages(address, length):
    return 0
end

# Řídce zapisovaná oblast; zde bez zvláštního zacházení.
function map_sparse(size):
    return map_anonymous(size, 0)
end

# Paměť přesně na adrese: 1 = hotovo, 0 = místo je obsazené.
function map_at(address, size):
    result = __lsl_qbe_call4(__lsl_symbol("VirtualAlloc"), address, size, MEM_COMMIT_RESERVE, PAGE_READWRITE)
    if result == address:
        return 1
    end
    if result != 0:
        call __lsl_qbe_call3(__lsl_symbol("VirtualFree"), result, 0, MEM_RELEASE)
    end
    return 0
end

# Uvolní celé mapování (VirtualAlloc nebo pohled na soubor z map_shared).
function unmap(address, length):
    if dword(__lsl_qbe_call3(__lsl_symbol("VirtualFree"), address, 0, MEM_RELEASE)) != 0:
        return 0
    end
    if dword(__lsl_qbe_call1(__lsl_symbol("UnmapViewOfFile"), address)) != 0:
        return 0
    end
    return 0 - platform.EINVAL
end

# Sdílené mapování souboru pro čtení a zápis.
function map_shared(fd, length, offset):
    mapping = __lsl_qbe_call6(__lsl_symbol("CreateFileMappingW"), handle(fd), 0, PAGE_READWRITE, 0, 0, 0)
    if mapping == 0:
        return last_errno()
    end
    view = __lsl_qbe_call5(__lsl_symbol("MapViewOfFile"), mapping, FILE_MAP_READ_WRITE, __lsl_qbe_lshr(offset, 32), dword(offset), length)
    error = 0
    if view == 0:
        error = last_errno()
    end
    call __lsl_qbe_call1(__lsl_symbol("CloseHandle"), mapping)
    if view == 0:
        return error
    end
    return view
end

# Soubory a proudy.
function write(fd, buffer, count):
    target = handle(fd)
    mode = __lsl_qbe_alloc(8)
    if dword(__lsl_qbe_call2(__lsl_symbol("GetConsoleMode"), target, mode)) != 0:
        return console_write(target, buffer, count)
    end
    if __lsl_qbe_ult(1073741824, count):
        count = 1073741824
    end
    written = __lsl_qbe_alloc(8)
    __lsl_qbe_store64(written, 0)
    if dword(__lsl_qbe_call5(__lsl_symbol("WriteFile"), target, buffer, count, written, 0)) == 0:
        return last_errno()
    end
    return dword(__lsl_qbe_load64(written))
end

# Konzole: UTF-8 -> UTF-16 po kusech celých znaků, WriteConsoleW.
# Neplatné sekvence nahradí MultiByteToWideChar znakem U+FFFD.
function console_write(target, buffer, count):
    wide = __lsl_qbe_alloc(16384)
    written = __lsl_qbe_alloc(8)
    done = 0
    while done < count:
        part = count - done
        if part > 4096:
            part = 4096
            # Nedělit vícebajtový znak: konec před bajtem 10xxxxxx.
            while part > 4093 and __lsl_qbe_load8(buffer + done + part) & 192 == 128:
                part -= 1
            end
        end
        chars = dword(__lsl_qbe_call6(__lsl_symbol("MultiByteToWideChar"), CP_UTF8, 0, buffer + done, part, wide, 8192))
        if chars == 0:
            return last_errno()
        end
        if dword(__lsl_qbe_call5(__lsl_symbol("WriteConsoleW"), target, wide, chars, written, 0)) == 0:
            return last_errno()
        end
        done += part
    end
    return count
end

function read(fd, buffer, count):
    if __lsl_qbe_ult(1073741824, count):
        count = 1073741824
    end
    target = handle(fd)
    mode = __lsl_qbe_alloc(8)
    if dword(__lsl_qbe_call2(__lsl_symbol("GetConsoleMode"), target, mode)) != 0:
        return console_read(target, buffer, count)
    end
    got = __lsl_qbe_alloc(8)
    __lsl_qbe_store64(got, 0)
    if dword(__lsl_qbe_call5(__lsl_symbol("ReadFile"), target, buffer, count, got, 0)) == 0:
        code = dword(__lsl_qbe_call0(__lsl_symbol("GetLastError")))
        # Zavřený zapisovací konec roury a konec souboru jsou EOF.
        if code == ERROR_BROKEN_PIPE or code == ERROR_HANDLE_EOF:
            return 0
        end
        return 0 - errno_of(code)
    end
    return dword(__lsl_qbe_load64(got))
end

# Konzole: ReadConsoleW (UTF-16) -> UTF-8, konec řádku \r\n -> \n jako na
# Linuxu, Ctrl+Z na začátku čtení = konec vstupu. Bajty, které se do count
# nevešly, čekají v lsl_win_console (+0 počet, +8 bajty) na další čtení.
function console_read(target, buffer, count):
    pending = __lsl_symbol("lsl_win_console")
    if __lsl_qbe_load64(pending) == 0:
        wide = __lsl_qbe_alloc(2048)
        got = __lsl_qbe_alloc(8)
        __lsl_qbe_store64(got, 0)
        if dword(__lsl_qbe_call5(__lsl_symbol("ReadConsoleW"), target, wide, 1024, got, 0)) == 0:
            return last_errno()
        end
        chars = dword(__lsl_qbe_load64(got))
        if chars == 0 or __lsl_qbe_load16(wide) == 26:
            return 0
        end
        bytes = dword(__lsl_qbe_call8(__lsl_symbol("WideCharToMultiByte"), CP_UTF8, 0, wide, chars, pending + 8, 4096, 0, 0))
        # \r před \n vypustit.
        kept = 0
        index = 0
        while index < bytes:
            byte = __lsl_qbe_load8(pending + 8 + index)
            if not (byte == 13 and index + 1 < bytes and __lsl_qbe_load8(pending + 9 + index) == 10):
                __lsl_qbe_store8(pending + 8 + kept, byte)
                kept += 1
            end
            index += 1
        end
        __lsl_qbe_store64(pending, kept)
        if kept == 0:
            return 0
        end
    end
    available = __lsl_qbe_load64(pending)
    part = count
    if part > available:
        part = available
    end
    index = 0
    while index < part:
        __lsl_qbe_store8(buffer + index, __lsl_qbe_load8(pending + 8 + index))
        index += 1
    end
    # Zbytek posunout na začátek.
    index = part
    while index < available:
        __lsl_qbe_store8(pending + 8 + index - part, __lsl_qbe_load8(pending + 8 + index))
        index += 1
    end
    __lsl_qbe_store64(pending, available - part)
    return part
end

function pread(fd, buffer, count, offset):
    if __lsl_qbe_ult(1073741824, count):
        count = 1073741824
    end
    got = __lsl_qbe_alloc(8)
    __lsl_qbe_store64(got, 0)
    # OVERLAPPED: +16 Offset, +20 OffsetHigh, +24 hEvent.
    overlapped = __lsl_qbe_alloc(32)
    __lsl_qbe_zero(overlapped, 32)
    __lsl_qbe_store64(overlapped + 16, offset)
    if dword(__lsl_qbe_call5(__lsl_symbol("ReadFile"), handle(fd), buffer, count, got, overlapped)) == 0:
        code = dword(__lsl_qbe_call0(__lsl_symbol("GetLastError")))
        if code == ERROR_HANDLE_EOF:
            return 0
        end
        return 0 - errno_of(code)
    end
    return dword(__lsl_qbe_load64(got))
end

function close(fd):
    if dword(__lsl_qbe_call1(__lsl_symbol("CloseHandle"), handle(fd))) == 0:
        return 0 - platform.EBADF
    end
    return 0
end

# Pozice v souboru; roura ani konzole nemají pozici (ESPIPE).
function lseek(fd, offset, whence):
    target = handle(fd)
    if dword(__lsl_qbe_call1(__lsl_symbol("GetFileType"), target)) != FILE_TYPE_DISK:
        return 0 - platform.ESPIPE
    end
    position = __lsl_qbe_alloc(8)
    if dword(__lsl_qbe_call4(__lsl_symbol("SetFilePointerEx"), target, offset, position, whence)) == 0:
        return last_errno()
    end
    return __lsl_qbe_load64(position)
end

# open(cesta, příznaky Linuxu, mód): HANDLE, nebo záporné errno. O_NOFOLLOW
# odmítne existující reparse point (symbolický odkaz) a odkaz nenásleduje.
function open(path, flags, mode):
    wide = __lsl_qbe_alloc(WIDE_PATH_BYTES)
    if not wide_path(path, wide):
        return 0 - platform.ENOENT
    end
    access = GENERIC_READ
    if flags & 3 == platform.O_WRONLY:
        access = GENERIC_WRITE
    elif flags & 3 == platform.O_RDWR:
        access = GENERIC_READ | GENERIC_WRITE
    end
    if flags & platform.O_APPEND != 0:
        access = (access & GENERIC_READ) | FILE_APPEND_DATA
    end
    disposition = OPEN_EXISTING
    if flags & platform.O_CREAT != 0:
        if flags & platform.O_EXCL != 0:
            disposition = CREATE_NEW
        elif flags & platform.O_TRUNC != 0:
            disposition = CREATE_ALWAYS
        else:
            disposition = OPEN_ALWAYS
        end
    elif flags & platform.O_TRUNC != 0:
        disposition = TRUNCATE_EXISTING
    end
    attributes = FILE_ATTRIBUTE_NORMAL
    if flags & platform.O_NOFOLLOW != 0:
        existing = dword(__lsl_qbe_call1(__lsl_symbol("GetFileAttributesW"), wide))
        if existing != INVALID_ATTRIBUTES and existing & FILE_ATTRIBUTE_REPARSE_POINT != 0:
            return 0 - platform.ELOOP
        end
        attributes = attributes | FILE_FLAG_OPEN_REPARSE_POINT
    end
    result = __lsl_qbe_call7(__lsl_symbol("CreateFileW"), wide, access, FILE_SHARE_ALL, 0, disposition, attributes, 0)
    if result == INVALID_HANDLE:
        return last_errno()
    end
    return result
end

# Druh souboru jako S_IFMT >> 12 Linuxu: 8 soubor, 1 roura, 2 znakové zařízení.
function file_kind(fd):
    kind = dword(__lsl_qbe_call1(__lsl_symbol("GetFileType"), handle(fd)))
    if kind == FILE_TYPE_DISK:
        return 8
    elif kind == FILE_TYPE_PIPE:
        return 1
    elif kind == FILE_TYPE_CHAR:
        return 2
    end
    return 0 - platform.EBADF
end

function is_terminal(fd):
    mode = __lsl_qbe_alloc(8)
    return dword(__lsl_qbe_call2(__lsl_symbol("GetConsoleMode"), handle(fd), mode)) != 0
end

function ioctl(fd, request, argument):
    return 0 - platform.ENOTTY
end

# Adresáře a mazání: BOOL funkce s cestou; 0, nebo záporné errno.
function make_directory(path, mode):
    wide = __lsl_qbe_alloc(WIDE_PATH_BYTES)
    if not wide_path(path, wide):
        return 0 - platform.ENOENT
    end
    if dword(__lsl_qbe_call2(__lsl_symbol("CreateDirectoryW"), wide, 0)) == 0:
        return last_errno()
    end
    return 0
end

function remove_file(path):
    wide = __lsl_qbe_alloc(WIDE_PATH_BYTES)
    if not wide_path(path, wide):
        return 0 - platform.ENOENT
    end
    if dword(__lsl_qbe_call1(__lsl_symbol("DeleteFileW"), wide)) == 0:
        return last_errno()
    end
    return 0
end

function remove_directory(path):
    wide = __lsl_qbe_alloc(WIDE_PATH_BYTES)
    if not wide_path(path, wide):
        return 0 - platform.ENOENT
    end
    if dword(__lsl_qbe_call1(__lsl_symbol("RemoveDirectoryW"), wide)) == 0:
        return last_errno()
    end
    return 0
end

# Pracovní adresář jako UTF-8 do buffer: délka, nebo záporné errno. Znak
# UTF-16 dá nejvýš tři bajty UTF-8, proto se čte nejvýš size / 3 znaků.
function current_directory(buffer, size):
    wide = __lsl_qbe_alloc(WIDE_PATH_BYTES)
    limit = __lsl_qbe_udiv(size - 1, 3)
    count = dword(__lsl_qbe_call2(__lsl_symbol("GetCurrentDirectoryW"), limit, wide))
    if count == 0:
        return last_errno()
    end
    if count >= limit:
        return 0 - platform.ENAMETOOLONG
    end
    return utf8_from_wide(wide, count, buffer)
end

function change_directory(path):
    wide = __lsl_qbe_alloc(WIDE_PATH_BYTES)
    if not wide_path(path, wide):
        return 0 - platform.ENOENT
    end
    if dword(__lsl_qbe_call1(__lsl_symbol("SetCurrentDirectoryW"), wide)) == 0:
        return last_errno()
    end
    return 0
end

# Přejmenování bez přepsání cíle (MoveFileExW bez MOVEFILE_REPLACE_EXISTING,
# s MOVEFILE_WRITE_THROUGH). Přesune i spuštěný .exe v rámci svazku.
function rename_path(source, destination):
    first = __lsl_qbe_alloc(WIDE_PATH_BYTES)
    second = __lsl_qbe_alloc(WIDE_PATH_BYTES)
    if not wide_path(source, first) or not wide_path(destination, second):
        return 0 - platform.ENOENT
    end
    if dword(__lsl_qbe_call3(__lsl_symbol("MoveFileExW"), first, second, 8)) == 0:
        return last_errno()
    end
    return 0
end

# 0, když cesta existuje.
function access(path):
    wide = __lsl_qbe_alloc(WIDE_PATH_BYTES)
    if not wide_path(path, wide):
        return 0 - platform.ENOENT
    end
    if dword(__lsl_qbe_call1(__lsl_symbol("GetFileAttributesW"), wide)) == INVALID_ATTRIBUTES:
        return last_errno()
    end
    return 0
end

# Sockety (Winsock) patří poskytovatelům knihoven, runtime je nemá.
function socket(domain, kind, protocol):
    return 0 - platform.ENOSYS
end

function connect(fd, address, length):
    return 0 - platform.ENOSYS
end

# Ukončí celý proces (všechna vlákna).
function exit_process(status):
    call __lsl_qbe_call1(__lsl_symbol("ExitProcess"), status)
    return 0
end

# Čekání na slovo (futex Linuxu): porovnává spodních 32 bitů jako FUTEX_WAIT.
function futex_wait(address, expected):
    compare = __lsl_qbe_alloc(8)
    __lsl_qbe_store64(compare, expected)
    call __lsl_qbe_call4(__lsl_symbol("WaitOnAddress"), address, compare, 4, INFINITE)
    return 0
end

# Jako futex_wait nejvýš po dobu timespec (relativně, zaokrouhleno na ms nahoru).
function futex_wait_timeout(address, expected, timespec):
    compare = __lsl_qbe_alloc(8)
    __lsl_qbe_store64(compare, expected)
    milliseconds = __lsl_qbe_load64(timespec) * 1000 + __lsl_qbe_udiv(__lsl_qbe_load64(timespec + 8) + 999999, 1000000)
    if __lsl_qbe_ult(INFINITE - 1, milliseconds):
        milliseconds = INFINITE - 1
    end
    call __lsl_qbe_call4(__lsl_symbol("WaitOnAddress"), address, compare, 4, milliseconds)
    return 0
end

function futex_wake(address, count):
    if count == 1:
        call __lsl_qbe_call1(__lsl_symbol("WakeByAddressSingle"), address)
    else:
        call __lsl_qbe_call1(__lsl_symbol("WakeByAddressAll"), address)
    end
    return 0
end

function getpid():
    return dword(__lsl_qbe_call0(__lsl_symbol("GetCurrentProcessId")))
end

function gettid():
    return dword(__lsl_qbe_call0(__lsl_symbol("GetCurrentThreadId")))
end

function sched_yield():
    call __lsl_qbe_call0(__lsl_symbol("SwitchToThread"))
    return 0
end

# Maska afinity procesu (64 bitů) do mask; počet bajtů, nebo -EINVAL.
function sched_getaffinity(size, mask):
    system_mask = __lsl_qbe_alloc(8)
    if size < 8 or dword(__lsl_qbe_call3(__lsl_symbol("GetProcessAffinityMask"), __lsl_qbe_call0(__lsl_symbol("GetCurrentProcess")), mask, system_mask)) == 0:
        return 0 - platform.EINVAL
    end
    return 8
end

# Hodiny: timespec (sekundy, nanosekundy). CLOCK_MONOTONIC z čítače výkonu,
# CLOCK_REALTIME ze systémového času (100 ns od roku 1601).
function os_clock_gettime(clock, timespec):
    if clock == platform.CLOCK_MONOTONIC:
        counter = performance_counter()
        frequency = performance_frequency()
        __lsl_qbe_store64(timespec, __lsl_qbe_udiv(counter, frequency))
        __lsl_qbe_store64(timespec + 8, __lsl_qbe_udiv(__lsl_qbe_urem(counter, frequency) * 1000000000, frequency))
        return 0
    end
    time = __lsl_qbe_alloc(8)
    call __lsl_qbe_call1(__lsl_symbol("GetSystemTimePreciseAsFileTime"), time)
    units = __lsl_qbe_load64(time) - 116444736000000000
    __lsl_qbe_store64(timespec, __lsl_qbe_idiv(units, 10000000))
    __lsl_qbe_store64(timespec + 8, __lsl_qbe_irem(units, 10000000) * 100)
    return 0
end

function performance_counter():
    value = __lsl_qbe_alloc(8)
    call __lsl_qbe_call1(__lsl_symbol("QueryPerformanceCounter"), value)
    return __lsl_qbe_load64(value)
end

function performance_frequency():
    value = __lsl_qbe_alloc(8)
    call __lsl_qbe_call1(__lsl_symbol("QueryPerformanceFrequency"), value)
    return __lsl_qbe_load64(value)
end

# Spánek aspoň po dobu request (Sleep může skončit o tik dřív, proto se
# čeká do termínu podle čítače výkonu). Neplatná doba -EINVAL.
function os_nanosleep(request, remaining):
    seconds = __lsl_qbe_load64(request)
    nanoseconds = __lsl_qbe_load64(request + 8)
    if seconds < 0 or nanoseconds < 0 or nanoseconds >= 1000000000:
        return 0 - platform.EINVAL
    end
    if remaining != 0:
        __lsl_qbe_store64(remaining, 0)
        __lsl_qbe_store64(remaining + 8, 0)
    end
    if seconds >= 1000000:
        # Dlouhý spánek po kusech v milisekundách (bez přetečení čítače).
        milliseconds = seconds * 1000 + __lsl_qbe_udiv(nanoseconds + 999999, 1000000)
        while milliseconds > 0:
            part = milliseconds
            if part > 2147483647:
                part = 2147483647
            end
            call __lsl_qbe_call1(__lsl_symbol("Sleep"), part)
            milliseconds -= part
        end
        return 0
    end
    frequency = performance_frequency()
    deadline = performance_counter() + seconds * frequency + __lsl_qbe_udiv(nanoseconds * frequency, 1000000000)
    while True:
        left = deadline - performance_counter()
        if left <= 0:
            break
        end
        call __lsl_qbe_call1(__lsl_symbol("Sleep"), __lsl_qbe_udiv(left * 1000 + frequency - 1, frequency))
    end
    return 0
end

# Start procesu: TLS slot bloku vlákna a blok argumentů jako na zásobníku
# Linuxu: argc, argv[0..argc-1], 0, prostředí "JMÉNO=hodnota", 0, za nimi
# řetězce UTF-8. Argumenty podle pravidel CommandLineToArgvW, proměnné
# prostředí začínající "=" (aktuální adresáře disků) se vynechají. Blok,
# nebo 0 při chybě.
function process_arguments(stack):
    slot = dword(__lsl_qbe_call0(__lsl_symbol("TlsAlloc")))
    # TlsSlots v TEB mají 64 míst (arch vrstva čte gs:0x1480 + 8 * slot).
    if slot >= 64:
        return 0
    end
    __lsl_qbe_store64(__lsl_symbol("lsl_tls_slot"), slot)
    # Pád (přístup do paměti, přetečení zásobníku…) ukončí proces s kódem
    # výjimky jako signál na Linuxu, bez dialogu chyby ani debuggeru.
    call __lsl_qbe_call1(__lsl_symbol("SetUnhandledExceptionFilter"), __lsl_symbol("lsl_unhandled_exception"))
    line = __lsl_qbe_call0(__lsl_symbol("GetCommandLineW"))
    line_chars = wide_length(line)
    environment = __lsl_qbe_call0(__lsl_symbol("GetEnvironmentStringsW"))
    environment_chars = 0
    if environment != 0:
        while __lsl_qbe_load16(environment + __lsl_qbe_shl(environment_chars, 1)) != 0:
            environment_chars += wide_length(environment + __lsl_qbe_shl(environment_chars, 1)) + 1
        end
    end
    # Horní odhad: každý argument aspoň znak a oddělovač, UTF-8 nejvýš 3 B
    # na znak UTF-16, pomocný UTF-16 buffer pro jeden argument.
    pointers = __lsl_qbe_shl(line_chars + environment_chars + 8, 3)
    text = (line_chars + environment_chars + 8) * 4
    scratch = __lsl_qbe_shl(line_chars + 2, 1)
    block = map_anonymous(pointers + text + scratch, 0)
    if block < 0:
        return 0
    end
    strings = block + pointers
    scratch_buffer = strings + text
    slot_pointer = block + 8
    position = line
    count = 0
    first = 1
    while True:
        # Mezery a tabulátory mezi argumenty.
        while __lsl_qbe_load16(position) == 32 or __lsl_qbe_load16(position) == 9:
            position += 2
        end
        if __lsl_qbe_load16(position) == 0:
            break
        end
        length = 0
        if first:
            position = program_name(position, scratch_buffer, block)
        else:
            position = command_argument(position, scratch_buffer, block)
        end
        length = __lsl_qbe_load64(block)
        bytes = utf8_from_wide(scratch_buffer, length, strings)
        __lsl_qbe_store64(slot_pointer, strings)
        slot_pointer += 8
        strings += bytes + 1
        count += 1
        first = 0
    end
    __lsl_qbe_store64(block, count)
    __lsl_qbe_store64(slot_pointer, 0)
    slot_pointer += 8
    if environment != 0:
        entry = environment
        while __lsl_qbe_load16(entry) != 0:
            length = wide_length(entry)
            if __lsl_qbe_load16(entry) != 61:
                bytes = utf8_from_wide(entry, length, strings)
                __lsl_qbe_store64(slot_pointer, strings)
                slot_pointer += 8
                strings += bytes + 1
            end
            entry += __lsl_qbe_shl(length + 1, 1)
        end
        call __lsl_qbe_call1(__lsl_symbol("FreeEnvironmentStringsW"), environment)
    end
    __lsl_qbe_store64(slot_pointer, 0)
    return block
end

# Filtr neošetřené výjimky (Win32 volá s EXCEPTION_POINTERS): vypíše kód
# výjimky a adresu vůči začátku obrazu programu a EXCEPTION_EXECUTE_HANDLER
# ukončí proces s kódem výjimky (os_wait ho převede na 139, 132…).
function lsl_unhandled_exception(information):
    record = __lsl_qbe_load64(information)
    text = __lsl_qbe_alloc(128)
    used = copy_text(text, 0, __lsl_address("LSL runtime crash: exception 0x") + 16)
    used = put_hex(text, used, dword(__lsl_qbe_load32(record)), 8)
    used = copy_text(text, used, __lsl_address(" at image+0x") + 16)
    image = __lsl_qbe_call1(__lsl_symbol("GetModuleHandleW"), 0)
    used = put_hex(text, used, __lsl_qbe_load64(record + 16) - image, 8)
    __lsl_qbe_store8(text + used, 10)
    call write(2, text, used + 1)
    return 1
end

# Zkopíruje C řetězec do bufferu od pozice used; nová pozice.
function copy_text(buffer, used, source):
    while __lsl_qbe_load8(source) != 0:
        __lsl_qbe_store8(buffer + used, __lsl_qbe_load8(source))
        used += 1
        source += 1
    end
    return used
end

# Číslo šestnáctkově, aspoň digits číslic; nová pozice.
function put_hex(buffer, used, value, digits):
    count = 1
    probe = __lsl_qbe_lshr(value, 4)
    while probe != 0:
        count += 1
        probe = __lsl_qbe_lshr(probe, 4)
    end
    if count < digits:
        count = digits
    end
    index = count
    while index > 0:
        index -= 1
        digit = value & 15
        if digit < 10:
            __lsl_qbe_store8(buffer + used + index, 48 + digit)
        else:
            __lsl_qbe_store8(buffer + used + index, 87 + digit)
        end
        value = __lsl_qbe_lshr(value, 4)
    end
    return used + count
end

# Počet znaků UTF-16 do NUL.
function wide_length(text):
    length = 0
    while __lsl_qbe_load16(text + __lsl_qbe_shl(length, 1)) != 0:
        length += 1
    end
    return length
end

# UTF-16 (length znaků) -> UTF-8 s NUL na output; počet bajtů bez NUL.
function utf8_from_wide(text, length, output):
    bytes = 0
    if length > 0:
        bytes = dword(__lsl_qbe_call8(__lsl_symbol("WideCharToMultiByte"), CP_UTF8, 0, text, length, output, length * 3, 0, 0))
    end
    __lsl_qbe_store8(output + bytes, 0)
    return bytes
end

# argv[0]: v uvozovkách až po další uvozovku, jinak po mezeru (bez escapování).
# Znaky do output, délku do length_out; vrací pozici za jménem.
function program_name(position, output, length_out):
    length = 0
    if __lsl_qbe_load16(position) == 34:
        position += 2
        while __lsl_qbe_load16(position) != 0 and __lsl_qbe_load16(position) != 34:
            __lsl_qbe_store16(output + __lsl_qbe_shl(length, 1), __lsl_qbe_load16(position))
            length += 1
            position += 2
        end
        if __lsl_qbe_load16(position) == 34:
            position += 2
        end
    else:
        while __lsl_qbe_load16(position) != 0 and __lsl_qbe_load16(position) != 32 and __lsl_qbe_load16(position) != 9:
            __lsl_qbe_store16(output + __lsl_qbe_shl(length, 1), __lsl_qbe_load16(position))
            length += 1
            position += 2
        end
    end
    __lsl_qbe_store64(length_out, length)
    return position
end

# Další argument: 2n zpětných lomítek + " = n lomítek a přepnutí uvozovek,
# 2n+1 + " = n lomítek a znak ", "" uvnitř uvozovek = znak ", jinak lomítka
# doslova.
function command_argument(position, output, length_out):
    length = 0
    quoted = 0
    while True:
        character = __lsl_qbe_load16(position)
        if character == 0:
            break
        end
        if not quoted and (character == 32 or character == 9):
            break
        end
        if character == 92:
            slashes = 0
            while __lsl_qbe_load16(position) == 92:
                slashes += 1
                position += 2
            end
            if __lsl_qbe_load16(position) == 34:
                index = 0
                while index < __lsl_qbe_lshr(slashes, 1):
                    __lsl_qbe_store16(output + __lsl_qbe_shl(length, 1), 92)
                    length += 1
                    index += 1
                end
                if slashes & 1 != 0:
                    __lsl_qbe_store16(output + __lsl_qbe_shl(length, 1), 34)
                    length += 1
                    position += 2
                end
            else:
                index = 0
                while index < slashes:
                    __lsl_qbe_store16(output + __lsl_qbe_shl(length, 1), 92)
                    length += 1
                    index += 1
                end
            end
        elif character == 34:
            if quoted and __lsl_qbe_load16(position + 2) == 34:
                __lsl_qbe_store16(output + __lsl_qbe_shl(length, 1), 34)
                length += 1
                position += 4
            else:
                quoted = not quoted
                position += 2
            end
        else:
            __lsl_qbe_store16(output + __lsl_qbe_shl(length, 1), character)
            length += 1
            position += 2
        end
    end
    __lsl_qbe_store64(length_out, length)
    return position
end

# Prostředí procesu: pole ukazatelů na "JMÉNO=hodnota" zakončené nulou za
# argv v bloku argumentů (stav +120).
function os_environment():
    block = __lsl_qbe_load64(__lsl_qbe_load64(__lsl_symbol("lsl_state")) + MAIN_STACK_TOP)
    return block + __lsl_qbe_shl(__lsl_qbe_load64(block) + 2, 3)
end

# Cesta ke spuštěnému programu v UTF-8 (bez NUL): délka, nebo záporná chyba.
function os_executable_path(buffer, size):
    wide = __lsl_qbe_alloc(WIDE_PATH_BYTES)
    length = dword(__lsl_qbe_call3(__lsl_symbol("GetModuleFileNameW"), 0, wide, WIDE_PATH_CHARS))
    if length == 0 or length >= WIDE_PATH_CHARS:
        return 0 - platform.ENAMETOOLONG
    end
    bytes = dword(__lsl_qbe_call8(__lsl_symbol("WideCharToMultiByte"), CP_UTF8, 0, wide, length, buffer, size, 0, 0))
    if bytes == 0:
        return 0 - platform.ENAMETOOLONG
    end
    return bytes
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

# Zapíše všechny bajty; 0, nebo -1 při chybě.
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

# Anonymní soubor (memfd Linuxu): dočasný soubor smazaný po zavření
# posledního handle (i zděděného potomkem).
function os_memfd(name):
    directory = __lsl_qbe_alloc(WIDE_PATH_BYTES)
    path = __lsl_qbe_alloc(WIDE_PATH_BYTES)
    prefix = __lsl_qbe_alloc(8)
    # Předpona L"lsl".
    __lsl_qbe_store64(prefix, 463864004716)
    length = dword(__lsl_qbe_call2(__lsl_symbol("GetTempPathW"), WIDE_PATH_CHARS - 16, directory))
    if length == 0 or length >= WIDE_PATH_CHARS - 16:
        return 0 - platform.ENOENT
    end
    if dword(__lsl_qbe_call4(__lsl_symbol("GetTempFileNameW"), directory, prefix, 0, path)) == 0:
        return last_errno()
    end
    result = __lsl_qbe_call7(__lsl_symbol("CreateFileW"), path, GENERIC_READ | GENERIC_WRITE, FILE_SHARE_ALL, 0, OPEN_EXISTING, FILE_ATTRIBUTE_TEMPORARY | FILE_FLAG_DELETE_ON_CLOSE, 0)
    if result == INVALID_HANDLE:
        error = last_errno()
        call __lsl_qbe_call1(__lsl_symbol("DeleteFileW"), path)
        return error
    end
    return result
end

# Roura: fds dostane dvě 32bitová čísla (čtení, zápis). HANDLE se do 32 bitů
# vejde (Win32 je tak definuje kvůli 32bitovým procesům).
function os_pipe(fds):
    ends = __lsl_qbe_alloc(16)
    if dword(__lsl_qbe_call4(__lsl_symbol("CreatePipe"), ends, ends + 8, 0, 65536)) == 0:
        return last_errno()
    end
    __lsl_qbe_store32(fds, __lsl_qbe_load64(ends))
    __lsl_qbe_store32(fds + 4, __lsl_qbe_load64(ends + 8))
    return 0
end

# Test vyčerpání deskriptorů: Windows nemá RLIMIT_NOFILE.
function os_limit_descriptors(limit):
    return 0 - platform.ENOSYS
end

# Kód ukončení potomka (pid je HANDLE procesu, který se tu zavře). Výjimky
# Windows jako signály Linuxu: přístup do paměti a přetečení zásobníku 139
# (SIGSEGV), neplatná instrukce 132, Ctrl+C 130, jiné kódy nad 255 jako 255.
function os_wait(pid):
    if pid == SPAWN_FAILED:
        return 127
    end
    if dword(__lsl_qbe_call2(__lsl_symbol("WaitForSingleObject"), pid, INFINITE)) != 0:
        return last_errno()
    end
    status = __lsl_qbe_alloc(8)
    __lsl_qbe_store64(status, 0)
    if dword(__lsl_qbe_call2(__lsl_symbol("GetExitCodeProcess"), pid, status)) == 0:
        error = last_errno()
        call __lsl_qbe_call1(__lsl_symbol("CloseHandle"), pid)
        return error
    end
    call __lsl_qbe_call1(__lsl_symbol("CloseHandle"), pid)
    code = dword(__lsl_qbe_load64(status))
    if code <= 255:
        return code
    elif code == 3221225477 or code == 3221225725:
        return 139
    elif code == 3221225501:
        return 132
    elif code == 3221225786:
        return 130
    end
    return 255
end

# Ukončí potomka (jako SIGKILL: kód 137).
function os_kill(pid):
    if pid == SPAWN_FAILED:
        return 0
    end
    if dword(__lsl_qbe_call2(__lsl_symbol("TerminateProcess"), pid, 137)) == 0:
        return last_errno()
    end
    return 0
end

# Znak "SystemRoot=" na pozici index (UTF-16, malými písmeny), jinak -1.
function system_root_char(index):
    if index == 0:
        return 115
    elif index == 1:
        return 121
    elif index == 2:
        return 115
    elif index == 3:
        return 116
    elif index == 4:
        return 101
    elif index == 5:
        return 109
    elif index == 6:
        return 114
    elif index == 7:
        return 111
    elif index == 8:
        return 111
    elif index == 9:
        return 116
    elif index == 10:
        return 61
    end
    return -1
end

# Čisté prostředí potomka: jen SystemRoot z rodiče. Bez něj Winsock
# v potomkovi nenaběhne (curl.exe a jiné síťové nástroje selžou s
# WSAEPROVIDERFAILEDINIT). Blok UTF-16 "SystemRoot=...", NUL, NUL.
function clean_environment():
    block = __lsl_qbe_alloc(WIDE_PATH_BYTES)
    __lsl_qbe_store64(block, 0)
    environment = __lsl_qbe_call0(__lsl_symbol("GetEnvironmentStringsW"))
    if environment == 0:
        return block
    end
    entry = environment
    while __lsl_qbe_load16(entry) != 0:
        length = wide_length(entry)
        matches = length > 11 and length < WIDE_PATH_CHARS - 2
        index = 0
        while matches and index < 11:
            character = __lsl_qbe_load16(entry + __lsl_qbe_shl(index, 1))
            if character >= 65 and character <= 90:
                character += 32
            end
            if character != system_root_char(index):
                matches = 0
            end
            index += 1
        end
        if matches:
            index = 0
            while index < length:
                __lsl_qbe_store16(block + __lsl_qbe_shl(index, 1), __lsl_qbe_load16(entry + __lsl_qbe_shl(index, 1)))
                index += 1
            end
            __lsl_qbe_store16(block + __lsl_qbe_shl(length, 1), 0)
            __lsl_qbe_store16(block + __lsl_qbe_shl(length + 1, 1), 0)
            break
        end
        entry += __lsl_qbe_shl(length + 1, 1)
    end
    call __lsl_qbe_call1(__lsl_symbol("FreeEnvironmentStringsW"), environment)
    return block
end

# Spustí program bez shellu (CreateProcessW, bez hledání v PATH). argv je
# pole ukazatelů na C řetězce zakončené nulou, clean vybere čisté
# prostředí (jen SystemRoot, viz clean_environment). output < 0: potomek
# dostane standardní proudy rodiče (run),
# jinak input (< 0 stdin rodiče), output a error (capture). Potomek zdědí
# jen tyto tři handle (PROC_THREAD_ATTRIBUTE_HANDLE_LIST), ne ostatní
# handle rodiče. Vrací HANDLE procesu, SPAWN_FAILED (program nejde spustit),
# nebo zápornou chybu.
function os_spawn(path, argv, clean, input, output, error, parent_end):
    application = __lsl_qbe_alloc(WIDE_PATH_BYTES)
    if not wide_path(path, application):
        return SPAWN_FAILED
    end
    line = __lsl_qbe_alloc(COMMAND_LINE_BYTES)
    if not command_line(argv, line, COMMAND_LINE_BYTES):
        return 0 - platform.E2BIG
    end
    wide_line = __lsl_qbe_alloc(COMMAND_LINE_CHARS * 2 + 2)
    if dword(__lsl_qbe_call6(__lsl_symbol("MultiByteToWideChar"), CP_UTF8, 0, line, -1, wide_line, COMMAND_LINE_CHARS)) == 0:
        return 0 - platform.E2BIG
    end
    streams = __lsl_qbe_alloc(24)
    if output >= 0:
        if input >= 0:
            __lsl_qbe_store64(streams, input)
        else:
            __lsl_qbe_store64(streams, handle(0))
        end
        __lsl_qbe_store64(streams + 8, output)
        __lsl_qbe_store64(streams + 16, error)
    else:
        __lsl_qbe_store64(streams, handle(0))
        __lsl_qbe_store64(streams + 8, handle(1))
        __lsl_qbe_store64(streams + 16, handle(2))
    end
    # Seznam zděděných handle bez opakování a bez neplatných; původní příznak
    # dědění se po spuštění vrátí.
    inherited = __lsl_qbe_alloc(24)
    saved = __lsl_qbe_alloc(24)
    flags = __lsl_qbe_alloc(8)
    count = 0
    index = 0
    while index < 3:
        stream = __lsl_qbe_load64(streams + __lsl_qbe_shl(index, 3))
        duplicate = stream == 0 or stream == INVALID_HANDLE
        other = 0
        while other < count:
            if __lsl_qbe_load64(inherited + __lsl_qbe_shl(other, 3)) == stream:
                duplicate = 1
            end
            other += 1
        end
        if not duplicate:
            __lsl_qbe_store64(flags, 0)
            if dword(__lsl_qbe_call2(__lsl_symbol("GetHandleInformation"), stream, flags)) != 0 and dword(__lsl_qbe_call3(__lsl_symbol("SetHandleInformation"), stream, HANDLE_FLAG_INHERIT, HANDLE_FLAG_INHERIT)) != 0:
                __lsl_qbe_store64(inherited + __lsl_qbe_shl(count, 3), stream)
                __lsl_qbe_store64(saved + __lsl_qbe_shl(count, 3), __lsl_qbe_load64(flags) & HANDLE_FLAG_INHERIT)
                count += 1
            end
        end
        index += 1
    end
    attributes = __lsl_qbe_alloc(256)
    size = __lsl_qbe_alloc(8)
    __lsl_qbe_store64(size, 256)
    listed = 0
    if count > 0 and dword(__lsl_qbe_call4(__lsl_symbol("InitializeProcThreadAttributeList"), attributes, 1, 0, size)) != 0:
        listed = 1
        if dword(__lsl_qbe_call7(__lsl_symbol("UpdateProcThreadAttribute"), attributes, 0, PROC_THREAD_ATTRIBUTE_HANDLE_LIST, inherited, __lsl_qbe_shl(count, 3), 0, 0)) == 0:
            call __lsl_qbe_call1(__lsl_symbol("DeleteProcThreadAttributeList"), attributes)
            listed = 0
        end
    end
    # STARTUPINFOEXW: +0 cb, +60 dwFlags, +80/+88/+96 standardní proudy,
    # +104 seznam atributů. PROCESS_INFORMATION: +0 proces, +8 vlákno.
    startup = __lsl_qbe_alloc(112)
    __lsl_qbe_zero(startup, 112)
    __lsl_qbe_store32(startup, 112)
    __lsl_qbe_store32(startup + 60, STARTF_USESTDHANDLES)
    __lsl_qbe_store64(startup + 80, __lsl_qbe_load64(streams))
    __lsl_qbe_store64(startup + 88, __lsl_qbe_load64(streams + 8))
    __lsl_qbe_store64(startup + 96, __lsl_qbe_load64(streams + 16))
    creation = 0
    inherit = 0
    if listed:
        __lsl_qbe_store64(startup + 104, attributes)
        creation = EXTENDED_STARTUPINFO_PRESENT
        inherit = 1
    end
    environment = 0
    if clean:
        environment = clean_environment()
        creation = creation | CREATE_UNICODE_ENVIRONMENT
    end
    information = __lsl_qbe_alloc(24)
    __lsl_qbe_zero(information, 24)
    started = dword(__lsl_qbe_call10(__lsl_symbol("CreateProcessW"), application, wide_line, 0, 0, inherit, creation, environment, 0, startup, information))
    if listed:
        call __lsl_qbe_call1(__lsl_symbol("DeleteProcThreadAttributeList"), attributes)
    end
    index = 0
    while index < count:
        call __lsl_qbe_call3(__lsl_symbol("SetHandleInformation"), __lsl_qbe_load64(inherited + __lsl_qbe_shl(index, 3)), HANDLE_FLAG_INHERIT, __lsl_qbe_load64(saved + __lsl_qbe_shl(index, 3)))
        index += 1
    end
    if started == 0:
        return SPAWN_FAILED
    end
    call __lsl_qbe_call1(__lsl_symbol("CloseHandle"), __lsl_qbe_load64(information + 8))
    return __lsl_qbe_load64(information)
end

# Příkazová řádka z argv v UTF-8 s NUL (pravidla CommandLineToArgvW):
# argument s mezerou, tabulátorem, uvozovkou nebo prázdný v uvozovkách,
# lomítka před uvozovkou zdvojená. 1, nebo 0, když se nevejde.
function command_line(argv, output, capacity):
    used = 0
    index = 0
    while __lsl_qbe_load64(argv + __lsl_qbe_shl(index, 3)) != 0:
        argument = __lsl_qbe_load64(argv + __lsl_qbe_shl(index, 3))
        if index > 0:
            if used + 1 >= capacity:
                return 0
            end
            __lsl_qbe_store8(output + used, 32)
            used += 1
        end
        plain = __lsl_qbe_load8(argument) != 0
        scan = argument
        while __lsl_qbe_load8(scan) != 0:
            character = __lsl_qbe_load8(scan)
            if character == 32 or character == 9 or character == 10 or character == 11 or character == 34:
                plain = 0
            end
            scan += 1
        end
        # Nejhorší případ argumentu: každý bajt zdvojený + uvozovky.
        if used + __lsl_qbe_shl(scan - argument, 1) + 3 >= capacity:
            return 0
        end
        if plain:
            while __lsl_qbe_load8(argument) != 0:
                __lsl_qbe_store8(output + used, __lsl_qbe_load8(argument))
                used += 1
                argument += 1
            end
        else:
            __lsl_qbe_store8(output + used, 34)
            used += 1
            slashes = 0
            while __lsl_qbe_load8(argument) != 0:
                character = __lsl_qbe_load8(argument)
                if character == 92:
                    slashes += 1
                elif character == 34:
                    used = put_slashes(output, used, slashes * 2 + 1)
                    slashes = 0
                else:
                    used = put_slashes(output, used, slashes)
                    slashes = 0
                end
                if character != 92:
                    __lsl_qbe_store8(output + used, character)
                    used += 1
                end
                argument += 1
            end
            used = put_slashes(output, used, slashes * 2)
            __lsl_qbe_store8(output + used, 34)
            used += 1
        end
        index += 1
    end
    __lsl_qbe_store8(output + used, 0)
    return 1
end

function put_slashes(output, used, count):
    while count > 0:
        __lsl_qbe_store8(output + used, 92)
        used += 1
        count -= 1
    end
    return used
end

# Vlákna. Zásobník vytvoří systém s vláknem (CreateThread, celý zpřístupněný:
# LuxIR na Windows nesonduje zásobník po stránkách). Vlákno se zveřejní
# samo v lsl_thread_begin (vrchol zásobníku z TEB).
function thread_stack(top, size, guard):
    return 0
end

# Údaje vlákna pro GC v lsl_win_threads: +0 HANDLE, +8 registry.
function thread_data(entry):
    index = __lsl_qbe_lshr(entry - __lsl_qbe_load64(core.state() + THREAD_TABLE) - 8, 6)
    return __lsl_symbol("lsl_win_threads") + index * WIN_THREAD_BYTES
end

# Volá se pod zámkem tabulky vláken: vlákno se zveřejní až po uložení handle.
function thread_start(entry, top, function):
    identifier = __lsl_qbe_alloc(8)
    __lsl_qbe_store64(identifier, 0)
    thread = __lsl_qbe_call6(__lsl_symbol("CreateThread"), 0, STACK_BYTES, __lsl_symbol("lsl_arch_thread_start"), entry, 0, identifier)
    if thread == 0:
        return -1
    end
    __lsl_qbe_store64(thread_data(entry), thread)
    return dword(__lsl_qbe_load64(identifier))
end

# Konec vlákna: stav 1 -> 0 a probudit čekající join. Když GC vlákno právě
# zastavuje (stav 4 nebo 2), počká se na jeho spuštění. Handle se přečte
# předem: po vynulování stavu může položku obsadit nové vlákno.
function thread_exit(entry):
    thread = __lsl_qbe_load64(thread_data(entry))
    while __lsl_qbe_call3(__lsl_symbol("lsl_arch_cas64"), entry + 16, 1, 0) != 1:
        call __lsl_qbe_call0(__lsl_symbol("SwitchToThread"))
    end
    call __lsl_qbe_call1(__lsl_symbol("WakeByAddressAll"), entry + 16)
    call __lsl_qbe_call1(__lsl_symbol("CloseHandle"), thread)
    call __lsl_qbe_call1(__lsl_symbol("ExitThread"), 0)
    return 0
end

# Zastavení pro GC (stav 4): SuspendThread a GetThreadContext (ten počká,
# až je vlákno opravdu zastavené). Registry jdou do údajů vlákna, rsp do
# +24; stav 2 = zastavené.
function thread_suspend(process, entry):
    data = thread_data(entry)
    thread = __lsl_qbe_load64(data)
    context = __lsl_symbol("lsl_win_context")
    stopped = dword(__lsl_qbe_call1(__lsl_symbol("SuspendThread"), thread)) != INFINITE
    if stopped:
        __lsl_qbe_store32(context + platform.CONTEXT_FLAGS_OFFSET, platform.CONTEXT_FLAGS_VALUE)
        stopped = dword(__lsl_qbe_call2(__lsl_symbol("GetThreadContext"), thread, context)) != 0
    end
    if stopped:
        index = 0
        while index < platform.CONTEXT_REGISTER_COUNT:
            __lsl_qbe_store64(data + 8 + __lsl_qbe_shl(index, 3), __lsl_qbe_load64(context + platform.CONTEXT_REGISTERS + __lsl_qbe_shl(index, 3)))
            index += 1
        end
        __lsl_qbe_store64(entry + 24, __lsl_qbe_load64(context + platform.CONTEXT_STACK_POINTER))
    else:
        # Bez kontextu prázdný rozsah zásobníku; ResumeThread pak nic nemění.
        index = 0
        while index < platform.CONTEXT_REGISTER_COUNT:
            __lsl_qbe_store64(data + 8 + __lsl_qbe_shl(index, 3), 0)
            index += 1
        end
        __lsl_qbe_store64(entry + 24, __lsl_qbe_load64(entry + 8))
    end
    __lsl_qbe_store64(entry + 16, 2)
    return 0
end

function thread_resume(entry):
    __lsl_qbe_store64(entry + 16, 1)
    call __lsl_qbe_call1(__lsl_symbol("ResumeThread"), __lsl_qbe_load64(thread_data(entry)))
    return 0
end

function thread_registers(entry):
    return thread_data(entry) + 8
end

# Zastavení světa nepotřebuje obsluhu signálu.
function install_thread_suspend():
    return 0
end

function tgkill(process, thread, signal):
    return 0 - platform.ENOSYS
end

# Začátek haldy: navržená adresa (1 GiB za obrazem programu).
# Začátek haldy: od 2^44 (nad běžnými celými čísly, viz entry.lsl), posun
# z dolních bitů nápovědy (ASLR obrazu); obsazené místo -> navržená adresa
# za obrazem.
function heap_base(hint):
    return 17592186044416 + (hint & 8796093022207)
end

# Časový limit potomka capture: časovač z thread poolu (CreateTimerQueueTimer)
# po milliseconds ukončí proces s kódem 124. Hlídání (VirtualAlloc 4 KiB):
# +0 HANDLE procesu, +8 vypršelo, +16 časovač. 0 = chyba.
WT_EXECUTEONLYONCE = 8

function process_deadline(pid, milliseconds):
    watch = map_anonymous(4096, 0)
    if watch < 0:
        return 0
    end
    __lsl_qbe_store64(watch, pid)
    if pid == SPAWN_FAILED:
        return watch
    end
    if dword(__lsl_qbe_call7(__lsl_symbol("CreateTimerQueueTimer"), watch + 16, 0, __lsl_symbol("lsl_process_timer"), watch, milliseconds, 0, WT_EXECUTEONLYONCE)) == 0:
        call unmap(watch, 4096)
        return 0
    end
    return watch
end

# Obsluha časovače (vlákno thread poolu bez bloku vlákna runtime: jen Win32).
function lsl_process_timer(watch, fired):
    __lsl_qbe_store64(watch + 8, 1)
    call __lsl_qbe_call2(__lsl_symbol("TerminateProcess"), __lsl_qbe_load64(watch), 124)
    return 0
end

# Zruší časovač a počká na doběhnutí obsluhy (INVALID_HANDLE_VALUE); 1, když
# limit vypršel.
function process_deadline_cancel(watch):
    if __lsl_qbe_load64(watch) != SPAWN_FAILED:
        call __lsl_qbe_call3(__lsl_symbol("DeleteTimerQueueTimer"), 0, __lsl_qbe_load64(watch + 16), INVALID_HANDLE)
    end
    expired = __lsl_qbe_load64(watch + 8)
    call unmap(watch, 4096)
    return expired
end

# Počká na skončení potomka; HANDLE zůstává platný pro os_wait.
function os_wait_exit(pid):
    if pid != SPAWN_FAILED:
        call __lsl_qbe_call2(__lsl_symbol("WaitForSingleObject"), pid, INFINITE)
    end
    return 0
end

# Vlákno běží samo od thread_start; nic nečeká na spuštění.
function thread_run_pending(entry):
    return 0
end

# Výpis adresáře (__lsl_list_directory): FindFirstFileW("cesta\\*").
# Blok stavu: +0 HANDLE, +8 první položka ještě nevrácená, od +16
# WIN32_FIND_DATAW (cFileName na +44).
DIRECTORY_STATE = 4096
FIND_NAME = 44

function directory_open(path):
    wide = __lsl_qbe_alloc(WIDE_PATH_BYTES)
    if not wide_path(path, wide):
        return 0 - platform.ENOENT
    end
    length = wide_length(wide)
    if length + 3 >= WIDE_PATH_CHARS:
        return 0 - platform.ENAMETOOLONG
    end
    __lsl_qbe_store16(wide + __lsl_qbe_shl(length, 1), 92)
    __lsl_qbe_store16(wide + __lsl_qbe_shl(length + 1, 1), 42)
    __lsl_qbe_store16(wide + __lsl_qbe_shl(length + 2, 1), 0)
    state = map_anonymous(DIRECTORY_STATE, 0)
    if state < 0:
        return state
    end
    handle = __lsl_qbe_call2(__lsl_symbol("FindFirstFileW"), wide, state + 16)
    if handle == INVALID_HANDLE or handle == 4294967295:
        error = last_errno()
        call unmap(state, DIRECTORY_STATE)
        return error
    end
    __lsl_qbe_store64(state, handle)
    __lsl_qbe_store64(state + 8, 1)
    return state
end

function directory_next(state, buffer, size):
    if __lsl_qbe_load64(state + 8) != 0:
        __lsl_qbe_store64(state + 8, 0)
    elif dword(__lsl_qbe_call2(__lsl_symbol("FindNextFileW"), __lsl_qbe_load64(state), state + 16)) == 0:
        return 0
    end
    bytes = dword(__lsl_qbe_call8(__lsl_symbol("WideCharToMultiByte"), CP_UTF8, 0, state + 16 + FIND_NAME, -1, buffer, size, 0, 0))
    if bytes <= 1:
        return 0 - platform.ENAMETOOLONG
    end
    return bytes - 1
end

function directory_close(state):
    call __lsl_qbe_call1(__lsl_symbol("FindClose"), __lsl_qbe_load64(state))
    call unmap(state, DIRECTORY_STATE)
    return 0
end
