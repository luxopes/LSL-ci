# lsl: runtime
# Vstup a výstup: bufferovaný stdin a stdout, input, celé soubory
# (readfile, writefile…), surové deskriptory pro stdlib fd, cesty.
# Systémová volání dělá vrstva OS (os_linux, os_windows); tady je logika nad nimi.
load core
load text
load _runtime_os as os
load _platform as platform

# Rozložení stavu (lsl_state, viz runtime_linux_x86_64.emit_entry).
STDIN_EOF = 88
THREADS = 136
STDIN_MODE = 1280
STDIN_BUFFER = 1288
STDOUT_MODE = 1312
STDOUT_BUFFER = 1320
# Buffer: 64 KiB mmap, slovo 0 počet bajtů (stdin: naplněno), slovo 1
# pozice čtení (stdin), data od bajtu 16.
BUFFER_BYTES = 65536
BUFFER_DATA = 65520
# Režim bufferu: 0 neznámý, 1 bufferovaný, 2 přímý.
MODE_BUFFERED = 1
MODE_DIRECT = 2

EINTR = 4
EINVAL = 22
SEEK_SET = 0
SEEK_CUR = 1
SEEK_END = 2
# Pohodlné čtení celého souboru je omezené (větší přes stdlib fd).
WHOLE_FILE_LIMIT = 67108864
STRING_LIMIT = 1073741824

function file_error(message):
    call __lsl_qbe_call1(__lsl_symbol("qbe_error_set"), message)
    return 0
end

# --- Validace argumentů ---

# Cesta pro jádro: String 1..4095 bajtů bez vnořené nuly (nula by tiše
# zkrátila cestu na prefix).
function rt_runtime_path_valid(path):
    if not text.rt_runtime_heap_type_valid(path, core.TAG_STRING):
        return 0
    end
    length = __lsl_qbe_load64(path + 8)
    if length <= 0 or length > 4095:
        return 0
    end
    index = 0
    while index < length:
        if __lsl_qbe_load8(path + 16 + index) == 0:
            return 0
        end
        index += 1
    end
    return 1
end

# Obsah souboru: String nejvýš 1 GiB (prázdný i s nulami je platný).
function rt_runtime_string_valid(value):
    if text.rt_runtime_heap_type_valid(value, core.TAG_STRING) and __lsl_qbe_load64(value + 8) <= STRING_LIMIT:
        return 1
    end
    return 0
end

# --- stdout ---
# Bufferuje se soubor, roura i znakové zařízení, které není terminál
# (/dev/null); terminál zůstává přímý. Všechny blokující nebo na pořadí
# citlivé vstupy runtime nejdřív vyprázdní buffer; s druhým vláknem se
# buffer obchází.

function stdout_detect(base):
    __lsl_qbe_store64(base + STDOUT_MODE, MODE_DIRECT)
    kind = os.file_kind(1)
    if kind == 2:
        if os.is_terminal(1):
            return 0
        end
    elif kind != 8 and kind != 1:
        return 0
    end
    buffer = os.map_anonymous(BUFFER_BYTES, 0)
    if buffer < 0:
        return 0
    end
    __lsl_qbe_store64(base + STDOUT_BUFFER, buffer)
    __lsl_qbe_store64(buffer, 0)
    __lsl_qbe_store64(base + STDOUT_MODE, MODE_BUFFERED)
    return 0
end

# Zapíše čekající bajty (částečné zápisy a EINTR znovu; jiná chyba zahodí
# zbytek jako přímý zápis).
function rt_runtime_stdout_flush():
    base = core.state()
    if __lsl_qbe_load64(base + STDOUT_MODE) != MODE_BUFFERED:
        return 0
    end
    buffer = __lsl_qbe_load64(base + STDOUT_BUFFER)
    remaining = __lsl_qbe_load64(buffer)
    position = buffer + 16
    while remaining > 0:
        written = os.write(1, position, remaining)
        if written > 0:
            position += written
            remaining -= written
        elif written != -EINTR:
            remaining = 0
        end
    end
    __lsl_qbe_store64(buffer, 0)
    return 0
end

# Výsledek jako write(2) při přímém zápisu.
function rt_runtime_stdout_write(bytes, count):
    if count <= 0:
        return 0
    end
    base = core.state()
    if __lsl_qbe_load64(base + THREADS) != 0:
        call rt_runtime_stdout_flush()
        return os.write(1, bytes, count)
    end
    if __lsl_qbe_load64(base + STDOUT_MODE) == 0:
        call stdout_detect(base)
    end
    if __lsl_qbe_load64(base + STDOUT_MODE) != MODE_BUFFERED:
        return os.write(1, bytes, count)
    end
    buffer = __lsl_qbe_load64(base + STDOUT_BUFFER)
    pending = __lsl_qbe_load64(buffer)
    if pending + count > BUFFER_DATA:
        call rt_runtime_stdout_flush()
        if count > BUFFER_DATA:
            return os.write(1, bytes, count)
        end
        pending = 0
    end
    call text.copy_bytes(buffer + 16 + pending, bytes, count)
    __lsl_qbe_store64(buffer, pending + count)
    return count
end

# --- stdin ---
# Bufferuje se jen obyčejný soubor: nepřečtené bajty se před předáním stdin
# potomkovi a při konci vrátí lseek, takže programy sdílející soubor vidí
# přesně to, co přečetl input(). Roura a terminál čtou po bajtu.

function stdin_detect(base):
    __lsl_qbe_store64(base + STDIN_MODE, MODE_DIRECT)
    if os.file_kind(0) != 8:
        return 0
    end
    buffer = os.map_anonymous(BUFFER_BYTES, 0)
    if buffer < 0:
        return 0
    end
    __lsl_qbe_store64(base + STDIN_BUFFER, buffer)
    __lsl_qbe_store64(buffer, 0)
    __lsl_qbe_store64(buffer + 8, 0)
    __lsl_qbe_store64(base + STDIN_MODE, MODE_BUFFERED)
    return 0
end

# Jeden bajt do destination; výsledek jako read(2): 1, 0 na konci, -errno.
function stdin_read_one(destination):
    base = core.state()
    if __lsl_qbe_load64(base + STDIN_MODE) == 0:
        call stdin_detect(base)
    end
    if __lsl_qbe_load64(base + STDIN_MODE) != MODE_BUFFERED:
        return os.read(0, destination, 1)
    end
    buffer = __lsl_qbe_load64(base + STDIN_BUFFER)
    position = __lsl_qbe_load64(buffer + 8)
    if not __lsl_qbe_ult(position, __lsl_qbe_load64(buffer)):
        filled = os.read(0, buffer + 16, BUFFER_DATA)
        while filled == -EINTR:
            filled = os.read(0, buffer + 16, BUFFER_DATA)
        end
        if filled <= 0:
            return filled
        end
        __lsl_qbe_store64(buffer, filled)
        position = 0
    end
    __lsl_qbe_store8(destination, __lsl_qbe_load8(buffer + 16 + position))
    __lsl_qbe_store64(buffer + 8, position + 1)
    return 1
end

# Vyprázdní stdout a vrátí nepřečtené bajty stdin do pozice souboru, aby
# potomek nebo další čtenář pokračoval tam, kde input() logicky skončil.
function stdin_release():
    call rt_runtime_stdout_flush()
    base = core.state()
    if __lsl_qbe_load64(base + STDIN_MODE) != MODE_BUFFERED:
        return 0
    end
    buffer = __lsl_qbe_load64(base + STDIN_BUFFER)
    position = __lsl_qbe_load64(buffer + 8)
    filled = __lsl_qbe_load64(buffer)
    if not __lsl_qbe_ult(position, filled):
        return 0
    end
    __lsl_qbe_store64(buffer + 8, filled)
    call os.lseek(0, position - filled, SEEK_CUR)
    return 0
end

# Přímé syscally, nativní kód a další vlákna mohou standardní deskriptory
# číst nebo přesměrovat: předčtená data se vrátí a dál se čte i píše přímo.
function rt_runtime_stdio_direct():
    call stdin_release()
    # Čekající výstup ven dřív, než se vyrovnávací paměť přestane používat.
    call rt_runtime_stdout_flush()
    base = core.state()
    __lsl_qbe_store64(base + STDIN_MODE, MODE_DIRECT)
    __lsl_qbe_store64(base + STDOUT_MODE, MODE_DIRECT)
    return 0
end

# Řádek ze stdin bez LF a pak CR; konec bez ukončení řádku se zachová.
function rt_runtime_input(prompt):
    base = core.state()
    # Stav +88: konec vstupu pro frontend se zdrojem na stdin.
    __lsl_qbe_store64(base + STDIN_EOF, 0)
    call rt_runtime_stdout_write(prompt + 16, __lsl_qbe_load64(prompt + 8))
    call rt_runtime_stdout_flush()
    line = __lsl_qbe_call1(__lsl_symbol("rt_runtime_alloc"), 273)
    __lsl_qbe_store64(line, core.TAG_STRING)
    length = 0
    capacity = 256
    reading = 1
    while reading:
        if length == capacity:
            if capacity >= 1048576:
                return file_error("FileError: cannot read stdin")
            end
            capacity = __lsl_qbe_shl(capacity, 1)
            grown = __lsl_qbe_call1(__lsl_symbol("rt_runtime_alloc"), capacity + 17)
            __lsl_qbe_store64(grown, core.TAG_STRING)
            call text.copy_bytes(grown + 16, line + 16, length)
            line = grown
        end
        result = stdin_read_one(line + 16 + length)
        if result < 0:
            return file_error("FileError: cannot read stdin")
        elif result == 0:
            __lsl_qbe_store64(base + STDIN_EOF, 1)
            reading = 0
        else:
            byte = __lsl_qbe_load8(line + 16 + length)
            length += 1
            if byte == 10:
                reading = 0
            end
        end
    end
    if length > 0 and __lsl_qbe_load8(line + 15 + length) == 10:
        length -= 1
    end
    if length > 0 and __lsl_qbe_load8(line + 15 + length) == 13:
        length -= 1
    end
    __lsl_qbe_store64(line + 8, length)
    __lsl_qbe_store8(line + 16 + length, 0)
    return line
end

function rt_runtime_stdin_eof():
    return __lsl_qbe_load64(core.state() + STDIN_EOF)
end

function rt_runtime_isatty(fd):
    return os.is_terminal(fd)
end

# eprint: text na stderr; čekající stdout jde ven dřív, aby pořadí zpráv
# na terminálu odpovídalo programu.
function rt_runtime_write_stderr(text):
    call rt_runtime_stdout_flush()
    call rt_runtime_write_all(2, text + 16, __lsl_qbe_load64(text + 8))
    newline = __lsl_qbe_alloc(8)
    __lsl_qbe_store8(newline, 10)
    call rt_runtime_write_all(2, newline, 1)
    return 0
end

# --- Celé soubory ---

# Zavře deskriptor po chybě čtení.
function read_failed(fd):
    call os.close(fd)
    return file_error("FileError: cannot read file")
end

# Velikost souboru (lseek na konec a zpět), nebo -1 nad limitem. Soubor bez
# známé velikosti (procfs, sysfs, roura: lseek selže nebo hlásí 0) dá 0 a
# čte se po blocích až do konce.
function whole_file_size(fd):
    size = os.lseek(fd, 0, SEEK_END)
    if size < 0:
        return 0
    end
    if size > WHOLE_FILE_LIMIT:
        return -1
    end
    if os.lseek(fd, 0, SEEK_SET) < 0:
        return 0
    end
    return size
end

# Čte až size bajtů do buffer; přečtený počet, nebo -1 při chybě.
function read_up_to(fd, buffer, size):
    total = 0
    while total < size:
        got = os.read(fd, buffer + total, size - total)
        if got < 0:
            return -1
        elif got == 0:
            return total
        end
        total += got
    end
    return total
end

# Soubor s hlášenou velikostí 0 (procfs, sysfs, roury): čte po blocích až
# do konce a text roste zdvojnásobením kapacity.
function read_unsized_text(fd):
    capacity = 4096
    content = __lsl_qbe_call1(__lsl_symbol("rt_runtime_alloc"), capacity + 17)
    __lsl_qbe_store64(content, core.TAG_STRING)
    length = 0
    reading = 1
    while reading != 0:
        if length == capacity:
            if capacity >= WHOLE_FILE_LIMIT:
                return read_failed(fd)
            end
            capacity = __lsl_qbe_shl(capacity, 1)
            grown = __lsl_qbe_call1(__lsl_symbol("rt_runtime_alloc"), capacity + 17)
            __lsl_qbe_store64(grown, core.TAG_STRING)
            call text.copy_bytes(grown + 16, content + 16, length)
            content = grown
        end
        got = os.read(fd, content + 16 + length, capacity - length)
        if got < 0:
            return read_failed(fd)
        elif got == 0:
            reading = 0
        else:
            length += got
        end
    end
    __lsl_qbe_store64(content + 8, length)
    __lsl_qbe_store8(content + 16 + length, 0)
    call os.close(fd)
    return content
end

# Totéž pro ByteArray: data v samostatném bloku, který při růstu nahradí větší.
function read_unsized_bytes(fd):
    capacity = 4096
    array = __lsl_qbe_call0(__lsl_symbol("rt_runtime_byte_array_new"))
    __lsl_qbe_store64(array + text.ARRAY_DATA, __lsl_qbe_call1(__lsl_symbol("rt_runtime_alloc_raw"), capacity))
    __lsl_qbe_store64(array + 16, capacity)
    length = 0
    reading = 1
    while reading != 0:
        if length == capacity:
            if capacity >= WHOLE_FILE_LIMIT:
                return read_failed(fd)
            end
            capacity = __lsl_qbe_shl(capacity, 1)
            grown = __lsl_qbe_call1(__lsl_symbol("rt_runtime_alloc_raw"), capacity)
            call text.copy_bytes(grown, __lsl_qbe_load64(array + text.ARRAY_DATA), length)
            __lsl_qbe_store64(array + text.ARRAY_DATA, grown)
            __lsl_qbe_store64(array + 16, capacity)
        end
        got = os.read(fd, __lsl_qbe_load64(array + text.ARRAY_DATA) + length, capacity - length)
        if got < 0:
            return read_failed(fd)
        elif got == 0:
            reading = 0
        else:
            length += got
        end
    end
    __lsl_qbe_store64(array + text.ARRAY_LENGTH, length)
    call os.close(fd)
    return array
end

function rt_runtime_readfile(path):
    if not rt_runtime_path_valid(path):
        return file_error("FileError: cannot open file")
    end
    fd = os.open(path + 16, platform.O_RDONLY | platform.O_CLOEXEC, 0)
    if fd < 0:
        return file_error("FileError: cannot open file")
    end
    size = whole_file_size(fd)
    if size < 0:
        return read_failed(fd)
    end
    if size == 0:
        return read_unsized_text(fd)
    end
    content = __lsl_qbe_call1(__lsl_symbol("rt_runtime_alloc"), size + 17)
    __lsl_qbe_store64(content, core.TAG_STRING)
    total = read_up_to(fd, content + 16, size)
    if total < 0:
        return read_failed(fd)
    end
    __lsl_qbe_store64(content + 8, total)
    __lsl_qbe_store8(content + 16 + total, 0)
    call os.close(fd)
    return content
end

function rt_runtime_readbytes(path):
    if not rt_runtime_path_valid(path):
        return file_error("FileError: cannot open file")
    end
    fd = os.open(path + 16, platform.O_RDONLY | platform.O_CLOEXEC, 0)
    if fd < 0:
        return file_error("FileError: cannot open file")
    end
    size = whole_file_size(fd)
    if size < 0:
        return read_failed(fd)
    end
    if size == 0:
        return read_unsized_bytes(fd)
    end
    array = __lsl_qbe_call0(__lsl_symbol("rt_runtime_byte_array_new"))
    # Nové pole má 64 B dat; větší soubor dostane vlastní blok.
    if size > 64:
        __lsl_qbe_store64(array + text.ARRAY_DATA, __lsl_qbe_call1(__lsl_symbol("rt_runtime_alloc_raw"), size))
        __lsl_qbe_store64(array + 16, size)
    end
    total = read_up_to(fd, __lsl_qbe_load64(array + text.ARRAY_DATA), size)
    if total < 0:
        return read_failed(fd)
    end
    __lsl_qbe_store64(array + text.ARRAY_LENGTH, total)
    call os.close(fd)
    return array
end

# Zapíše všechny bajty (EINTR znovu); 0, nebo -1 při chybě zápisu.
function rt_runtime_write_all(fd, bytes, count):
    while count > 0:
        written = os.write(fd, bytes, count)
        if written > 0:
            bytes += written
            count -= written
        elif written != -EINTR:
            return -1
        end
    end
    return 0
end

# Otevře, zapíše a zavře; 0, nebo záporné číslo při chybě.
function write_path(path, bytes, count, flags, mode):
    fd = os.open(path + 16, flags, mode)
    if fd < 0:
        return fd
    end
    written = rt_runtime_write_all(fd, bytes, count)
    closed = os.close(fd)
    if written < 0:
        return written
    end
    return closed
end

# Textové soubory jsou data, ne programy (0644, umask může víc); poslední
# složka cesty nesmí být symlink a deskriptor neprojde přes execve.
TEXT_MODE = 420
BINARY_MODE = 493
WRITE_FLAGS = platform.O_WRONLY | platform.O_CREAT | platform.O_TRUNC | platform.O_NOFOLLOW | platform.O_CLOEXEC
APPEND_FLAGS = platform.O_WRONLY | platform.O_CREAT | platform.O_APPEND | platform.O_NOFOLLOW | platform.O_CLOEXEC

function rt_runtime_writefile(path, content):
    if not rt_runtime_path_valid(path) or not rt_runtime_string_valid(content):
        return file_error("FileError: cannot write file")
    end
    if write_path(path, content + 16, __lsl_qbe_load64(content + 8), WRITE_FLAGS, TEXT_MODE) < 0:
        return file_error("FileError: cannot write file")
    end
    return 0
end

function rt_runtime_appendfile(path, content):
    if not rt_runtime_path_valid(path) or not rt_runtime_string_valid(content):
        return file_error("FileError: cannot append file")
    end
    if write_path(path, content + 16, __lsl_qbe_load64(content + 8), APPEND_FLAGS, TEXT_MODE) < 0:
        return file_error("FileError: cannot append file")
    end
    return 0
end

# ByteArray, nebo List bajtů (Int/Bool 0..255; raw: surová slova).
# Binární výstup zůstává spustitelný (artefakty překladače).
function write_bytes(path, data, raw):
    if not rt_runtime_path_valid(path) or not core.rt_runtime_is_heap_object(data):
        return file_error("FileError: cannot write file")
    end
    tag = __lsl_qbe_load64(data)
    if tag != text.TAG_BYTE_ARRAY and tag != text.TAG_LIST:
        return file_error("FileError: cannot write file")
    end
    count = __lsl_qbe_load64(data + text.ARRAY_LENGTH)
    if count < 0 or count > STRING_LIMIT:
        return file_error("FileError: cannot write file")
    end
    bytes = __lsl_qbe_load64(data + text.ARRAY_DATA)
    if tag == text.TAG_LIST:
        items = bytes
        bytes = __lsl_qbe_call1(__lsl_symbol("rt_runtime_alloc_raw"), count + 1)
        index = 0
        while index < count:
            value = __lsl_qbe_load64(items + __lsl_qbe_shl(index, 3))
            if not raw:
                kind = core.rt_runtime_type_code(value)
                if kind != core.TAG_INT and kind != core.TAG_BOOL:
                    return file_error("FileError: cannot write file")
                end
                value = core.rt_runtime_unbox_dynamic_int(value)
            end
            if value < 0 or value > 255:
                return file_error("FileError: cannot write file")
            end
            __lsl_qbe_store8(bytes + index, value)
            index += 1
        end
    end
    if write_path(path, bytes, count, WRITE_FLAGS, BINARY_MODE) < 0:
        return file_error("FileError: cannot write file")
    end
    return 0
end

function rt_runtime_writebytes(path, data):
    return write_bytes(path, data, 0)
end

function rt_runtime_writebytes_raw(path, data):
    return write_bytes(path, data, 1)
end

# --- Cesty ---

function rt_runtime_mkdir(path):
    if not rt_runtime_path_valid(path):
        return -EINVAL
    end
    return os.make_directory(path + 16, 493)
end

function rt_runtime_mkdir_private(path):
    if not rt_runtime_path_valid(path):
        return -EINVAL
    end
    return os.make_directory(path + 16, 448)
end

# __lsl_list_directory(cesta): List jmen položek bez "." a "..", v pořadí,
# jak je vrací systém; chyba FileError.
function rt_runtime_list_directory(path):
    if not rt_runtime_path_valid(path):
        return file_error("FileError: cannot list directory")
    end
    handle = os.directory_open(path + 16)
    if handle < 0:
        return file_error("FileError: cannot list directory")
    end
    result = __lsl_qbe_call2(__lsl_symbol("rt_runtime_list_new"), 0, 0)
    buffer = __lsl_qbe_alloc(1024)
    failed = 0
    while True:
        length = os.directory_next(handle, buffer, 1023)
        if length < 0:
            failed = 1
            break
        elif length == 0:
            break
        end
        dot = __lsl_qbe_load8(buffer) == 46
        if not (dot and (length == 1 or (length == 2 and __lsl_qbe_load8(buffer + 1) == 46))):
            call __lsl_qbe_call2(__lsl_symbol("rt_runtime_list_append"), result, text.string_from(buffer, length))
        end
    end
    call os.directory_close(handle)
    if failed:
        return file_error("FileError: cannot list directory")
    end
    return result
end

function rt_runtime_unlink(path):
    if not rt_runtime_path_valid(path):
        return -EINVAL
    end
    return os.remove_file(path + 16)
end

function rt_runtime_rmdir(path):
    if not rt_runtime_path_valid(path):
        return -EINVAL
    end
    return os.remove_directory(path + 16)
end

# cwd(): absolutní cesta pracovního adresáře; chyba FileError.
function rt_runtime_cwd():
    buffer = __lsl_qbe_alloc(4096)
    length = os.current_directory(buffer, 4096)
    if length < 0:
        return file_error("FileError: cannot read the current directory")
    end
    return text.string_from(buffer, length)
end

# chdir(cesta): změní pracovní adresář; chyba FileError.
function rt_runtime_chdir(path):
    if not rt_runtime_path_valid(path):
        return file_error("FileError: cannot change directory")
    end
    if os.change_directory(path + 16) < 0:
        return file_error("FileError: cannot change directory")
    end
    return 0
end

# __lsl_rename(zdroj, cíl): 0, nebo záporné errno; existující cíl se
# nepřepíše (atomické přejmenování v rámci jednoho svazku).
function rt_runtime_rename(source, destination):
    if not rt_runtime_path_valid(source) or not rt_runtime_path_valid(destination):
        return -EINVAL
    end
    return os.rename_path(source + 16, destination + 16)
end

function rt_runtime_exists(path):
    if not rt_runtime_path_valid(path):
        return 0
    end
    return os.access(path + 16) == 0
end

# --- Surové deskriptory (stdlib fd) ---
# Vrací surový výsledek jádra; stdlib z záporných hodnot dělá chyby.
# Přímé operace s FD musí vidět logickou pozici po posledním input().

# Deskriptory runtime nikdy nepřejdou přes execve.
function rt_runtime_fd_open(path, flags):
    if not rt_runtime_path_valid(path):
        return -EINVAL
    end
    return os.open(path + 16, flags | platform.O_CLOEXEC, 438)
end

# Počet ořezaný na délku dat ByteArray, -1 pro neplatný argument.
function byte_count(array, count):
    if not text.rt_runtime_heap_type_valid(array, text.TAG_BYTE_ARRAY) or count < 0:
        return -1
    end
    length = __lsl_qbe_load64(array + text.ARRAY_LENGTH)
    if count > length:
        return length
    end
    return count
end

function rt_runtime_fd_read(fd, array, count):
    call stdin_release()
    count = byte_count(array, count)
    if count < 0:
        return -EINVAL
    end
    return os.read(fd, __lsl_qbe_load64(array + text.ARRAY_DATA), count)
end

# Zapisuje, dokud neodejde vše; EINTR znovu, EAGAIN a jiné chyby vrací
# (nekonečné čekání na plný neblokující deskriptor bylo DoS).
function rt_runtime_fd_write(fd, array, count):
    call stdin_release()
    count = byte_count(array, count)
    if count < 0:
        return -EINVAL
    end
    bytes = __lsl_qbe_load64(array + text.ARRAY_DATA)
    while count > 0:
        written = os.write(fd, bytes, count)
        if written > 0:
            bytes += written
            count -= written
        elif written != -EINTR:
            return written
        end
    end
    return 0
end

function rt_runtime_fd_seek(fd, offset):
    call stdin_release()
    return os.lseek(fd, offset, SEEK_SET)
end

function rt_runtime_fd_close(fd):
    call stdin_release()
    # Deskriptor 0 nebo 1 může být příště otevřený jako jiný druh souboru.
    if __lsl_qbe_ule(fd, 1):
        call rt_runtime_stdio_direct()
    end
    return os.close(fd)
end

function rt_runtime_fd_socket(domain, kind):
    return os.socket(domain, kind | platform.SOCK_CLOEXEC, 0)
end

function rt_runtime_fd_connect(fd, address, length):
    length = byte_count(address, length)
    if length < 0:
        return -EINVAL
    end
    return os.connect(fd, __lsl_qbe_load64(address + text.ARRAY_DATA), length)
end

# ioctl(fd, request, data ByteArray); prázdné pole předá NULL.
function rt_runtime_fd_ioctl(fd, array, request):
    if not text.rt_runtime_heap_type_valid(array, text.TAG_BYTE_ARRAY):
        return -1
    end
    argument = 0
    if __lsl_qbe_load64(array + text.ARRAY_LENGTH) > 0:
        argument = __lsl_qbe_load64(array + text.ARRAY_DATA)
    end
    return os.ioctl(fd, request, argument)
end

# Sdílené mapování deskriptoru pro čtení i zápis; adresa nebo -errno.
function rt_runtime_fd_mmap(fd, length, offset):
    if length <= 0 or offset < 0:
        return -EINVAL
    end
    return os.map_shared(fd, length, offset)
end

# Kopie omezeného rozsahu souboru do nového anonymního mapování (stabilní
# adresa). pread místo mapování souboru: zkrácený sdílený soubor dá chybu
# místo SIGBUS.
function rt_runtime_fd_snapshot(fd, offset, count):
    if fd < 0 or offset < 0 or count <= 0 or count > WHOLE_FILE_LIMIT or offset > 1099511627776:
        return -EINVAL
    end
    mapping = os.map_anonymous(count, 0)
    if mapping < 0:
        return mapping
    end
    total = 0
    while total < count:
        got = os.pread(fd, mapping + total, count - total, offset + total)
        if got > 0:
            total += got
        elif got != -EINTR:
            if got == 0:
                # Soubor je kratší než požadovaný rozsah: EIO.
                got = -5
            end
            call os.unmap(mapping, count)
            return got
        end
    end
    return mapping
end

# __lsl_syscall a __lsl_syscall6: obecné dveře do jádra (Wayland server:
# SCM_RIGHTS, memfd, ftruncate); stdio pak běží přímo.
function rt_runtime_syscall(number, a, b, c, d):
    call rt_runtime_stdio_direct()
    # Pátý operand je d jako dřív (x86 dveře nechávaly d i v r8).
    return os.syscall6(number, a, b, c, d, d, 0)
end

function rt_runtime_syscall6(number, a, b, c, d, e, f):
    call rt_runtime_stdio_direct()
    return os.syscall6(number, a, b, c, d, e, f)
end
