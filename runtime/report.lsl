# lsl: runtime
# Nezachycená chyba ve formátu diagnostiky LSL:
#   error[Druh]: zpráva / --> cesta:řádek:sloupec / zdrojový řádek se šipkou
#   / help. Nic se nealokuje na haldě (jen buffery na zásobníku), takže
# hlášení funguje i při vyčerpané paměti. Zdrojový řádek se čte jen ze
# souborů .lsl (chyba může ukazovat do .env s tajnými hodnotami). Výstup je
# bajt po bajtu stejný jako u dřívější x86 rutiny.
load _platform as platform
load _runtime_os as os
load io
load entry

TLS_ERROR = 0
# Zdrojový řádek se ukáže nejvýš z prvních 4096 bajtů, cesta má méně než
# 4000 bajtů, čte se po 4096 bajtech.
LINE_LIMIT = 4096
PATH_LIMIT = 4000
READ_CHUNK = 4096
EINTR = 4
# Barvy: 0 bez barvy, jinak escape sekvence ANSI.
COLOR_RED = 1
COLOR_BLUE = 2
COLOR_CYAN = 3
COLOR_RESET = 4
# Pozice v zprávě (záznam na zásobníku).
LOC_PSTART = 0
LOC_PEND = 8
LOC_LSTART = 16
LOC_LEND = 24
LOC_COL = 32
LOC_TEND = 40

# --- Barvy podle prostředí ---

# 1, když řetězec C začíná bajty literálu.
function env_starts(entry, text):
    length = __lsl_qbe_load64(text + 8)
    index = 0
    while index < length:
        if __lsl_qbe_load8(entry + index) != __lsl_qbe_load8(text + 16 + index):
            return 0
        end
        index += 1
    end
    return 1
end

# Barvy se vyhodnocují až na chybové cestě: NO_COLOR= kdekoli vypíná,
# FORCE_COLOR=0 vypíná, jiná neprázdná hodnota FORCE_COLOR zapíná, TERM=dumb
# vypíná; jinak barvy jen na terminálu (stderr).
function rt_runtime_error_color():
    slot = os.os_environment()
    flags = 0
    while __lsl_qbe_load64(slot) != 0:
        entry = __lsl_qbe_load64(slot)
        if env_starts(entry, "NO_COLOR="):
            return 0
        end
        if env_starts(entry, "FORCE_COLOR="):
            value = __lsl_qbe_load8(entry + 12)
            if value != 0:
                if value == 48 and __lsl_qbe_load8(entry + 13) == 0:
                    return 0
                end
                flags = flags | 1
            end
        elif env_starts(entry, "TERM=dumb"):
            if __lsl_qbe_load8(entry + 9) == 0:
                flags = flags | 2
            end
        end
        slot += 8
    end
    if flags & 1 != 0:
        return 1
    end
    if flags != 0:
        return 0
    end
    if os.is_terminal(2):
        return 1
    end
    return 0
end

# --- Výstup na stderr (jedno write jako dříve, bez opakování) ---
# cold_*: nevkládají se, hlášení je chladná cesta a nemá zvětšovat binárky.

function cold_report_write(pointer, count):
    if count > 0:
        call os.write(2, pointer, count)
    end
    return 0
end

function cold_report_text(text):
    call os.write(2, text + 16, __lsl_qbe_load64(text + 8))
    return 0
end

function report_color(color, which):
    if color == 0:
        return 0
    end
    if which == COLOR_RED:
        code = "[1;31m"
    elif which == COLOR_BLUE:
        code = "[1;34m"
    elif which == COLOR_CYAN:
        code = "[36m"
    else:
        code = "[0m"
    end
    # ESC + kód jedním zápisem.
    buffer = __lsl_qbe_alloc(16)
    length = __lsl_qbe_load64(code + 8)
    __lsl_qbe_store8(buffer, 27)
    index = 0
    while index < length:
        __lsl_qbe_store8(buffer + 1 + index, __lsl_qbe_load8(code + 16 + index))
        index += 1
    end
    call os.write(2, buffer, length + 1)
    return 0
end

# count mezer.
function report_spaces(count):
    while count > 0:
        call cold_report_text(" ")
        count -= 1
    end
    return 0
end

# Modře okraj široký jako číslo řádku + 1.
function report_gutter(color, loc):
    call report_color(color, COLOR_BLUE)
    call report_spaces(__lsl_qbe_load64(loc + LOC_LEND) - __lsl_qbe_load64(loc + LOC_LSTART) + 1)
    return 0
end

# --- Rozbor zprávy ---

function report_digit(byte):
    if byte >= 48 and byte <= 57:
        return 1
    end
    return 0
end

# Číslo z bajtů [start, stop), nejvýš 9 číslic; -1 pokud nejde o číslo.
function report_number(text, start, stop):
    count = stop - start
    if count <= 0 or count > 9:
        return -1
    end
    value = 0
    while start < stop:
        byte = __lsl_qbe_load8(text + start)
        if not report_digit(byte):
            return -1
        end
        value = value * 10 + byte - 48
        start += 1
    end
    return value
end

# Druh chyby: text před první ": ", pokud před ním není mezera; jinak -1.
function report_kind(text, length):
    index = 0
    while index + 1 < length:
        byte = __lsl_qbe_load8(text + index)
        if byte == 32:
            return -1
        end
        if byte == 58 and __lsl_qbe_load8(text + index + 1) == 32:
            return index
        end
        index += 1
    end
    return -1
end

# Bajty " at " na adrese.
function report_at(pointer):
    if __lsl_qbe_load8(pointer) == 32 and __lsl_qbe_load8(pointer + 1) == 97 and __lsl_qbe_load8(pointer + 2) == 116 and __lsl_qbe_load8(pointer + 3) == 32:
        return 1
    end
    return 0
end

# Pozice: poslední " at CESTA:ŘÁDEK[:SLOUPEC]" na konci zprávy (za začátkem
# textu). Vyplní záznam loc; 0 když pozice chybí.
function report_locate(text, length, start, loc):
    at = length - 4
    found = 0
    while found == 0 and at >= start:
        if report_at(text + at):
            found = 1
        else:
            at -= 1
        end
    end
    if found == 0:
        return 0
    end
    path = at + 4
    # Číslice na konci zprávy.
    last = length - 1
    scanning = 1
    while scanning and last > path:
        if report_digit(__lsl_qbe_load8(text + last)):
            last -= 1
        else:
            scanning = 0
        end
    end
    if last + 1 >= length or __lsl_qbe_load8(text + last) != 58:
        return 0
    end
    colon = last
    middle = last - 1
    scanning = 1
    while scanning and middle > path:
        if report_digit(__lsl_qbe_load8(text + middle)):
            middle -= 1
        else:
            scanning = 0
        end
    end
    __lsl_qbe_store64(loc + LOC_COL, 0)
    if middle < colon - 1 and __lsl_qbe_load8(text + middle) == 58:
        # cesta:řádek:sloupec
        path_end = middle
        __lsl_qbe_store64(loc + LOC_LSTART, middle + 1)
        __lsl_qbe_store64(loc + LOC_LEND, colon)
        column = report_number(text, colon + 1, length)
        if column >= 0:
            __lsl_qbe_store64(loc + LOC_COL, column)
        end
    else:
        path_end = colon
        __lsl_qbe_store64(loc + LOC_LSTART, colon + 1)
        __lsl_qbe_store64(loc + LOC_LEND, length)
    end
    if path_end <= path:
        return 0
    end
    __lsl_qbe_store64(loc + LOC_PSTART, path)
    __lsl_qbe_store64(loc + LOC_PEND, path_end)
    __lsl_qbe_store64(loc + LOC_TEND, at)
    return 1
end

# --- Zdrojový řádek ---

# Délka řádku line (bajty nad LINE_LIMIT se zahodí) do line_buffer; -1
# když soubor tolik řádků nemá.
function report_read_line(fd, line, buffer, line_buffer):
    current = 1
    length = 0
    while True:
        count = os.read(fd, buffer, READ_CHUNK)
        if count != 0 - EINTR:
            if count <= 0:
                if current == line:
                    return length
                end
                return -1
            end
            index = 0
            while index < count:
                byte = __lsl_qbe_load8(buffer + index)
                if current == line:
                    if byte == 10:
                        return length
                    end
                    if length < LINE_LIMIT:
                        __lsl_qbe_store8(line_buffer + length, byte)
                        length += 1
                    end
                elif byte == 10:
                    current += 1
                end
                index += 1
            end
        end
    end
    return -1
end

# Řádek ze souboru .lsl s rozumně dlouhou cestou a šipka pod sloupcem.
function report_source(text, color, loc):
    start = __lsl_qbe_load64(loc + LOC_PSTART)
    stop = __lsl_qbe_load64(loc + LOC_PEND)
    size = stop - start
    if size <= 4 or size >= PATH_LIMIT:
        return 0
    end
    if not env_starts(text + stop - 4, ".lsl"):
        return 0
    end
    path = __lsl_qbe_alloc(PATH_LIMIT + 8)
    index = 0
    while index < size:
        __lsl_qbe_store8(path + index, __lsl_qbe_load8(text + start + index))
        index += 1
    end
    __lsl_qbe_store8(path + size, 0)
    line = report_number(text, __lsl_qbe_load64(loc + LOC_LSTART), __lsl_qbe_load64(loc + LOC_LEND))
    if line < 1:
        return 0
    end
    fd = os.open(path, platform.O_RDONLY + platform.O_CLOEXEC, 0)
    if fd < 0:
        return 0
    end
    buffer = __lsl_qbe_alloc(READ_CHUNK)
    line_buffer = __lsl_qbe_alloc(LINE_LIMIT)
    length = report_read_line(fd, line, buffer, line_buffer)
    call os.close(fd)
    if length <= 0:
        return 0
    end
    call report_gutter(color, loc)
    call cold_report_text("|")
    call report_color(color, COLOR_RESET)
    call cold_report_text("\n")
    call report_color(color, COLOR_BLUE)
    call cold_report_write(text + __lsl_qbe_load64(loc + LOC_LSTART), __lsl_qbe_load64(loc + LOC_LEND) - __lsl_qbe_load64(loc + LOC_LSTART))
    call cold_report_text(" | ")
    call report_color(color, COLOR_RESET)
    call cold_report_write(line_buffer, length)
    call cold_report_text("\n")
    # Šipka jen při známém sloupci.
    column = __lsl_qbe_load64(loc + LOC_COL)
    if column <= 0:
        return 0
    end
    call report_gutter(color, loc)
    call cold_report_text("| ")
    call report_color(color, COLOR_RESET)
    pad = column - 1
    if pad > length:
        pad = length
    end
    call report_spaces(pad)
    call report_color(color, COLOR_RED)
    call cold_report_text("^")
    index = column
    while index < length and report_word_byte(__lsl_qbe_load8(line_buffer + index)):
        call cold_report_text("~")
        index += 1
    end
    call report_color(color, COLOR_RESET)
    call cold_report_text("\n")
    return 0
end

# Bajt identifikátoru: _ 0-9 A-Z a-z.
function report_word_byte(byte):
    if byte == 95 or report_digit(byte):
        return 1
    end
    if (byte >= 65 and byte <= 90) or (byte >= 97 and byte <= 122):
        return 1
    end
    return 0
end

# --- help ---

# 1, když bajty [pointer, pointer + count) jsou rovny literálu.
function report_equal(pointer, count, key):
    if count != __lsl_qbe_load64(key + 8):
        return 0
    end
    return env_starts(pointer, key)
end

# 1, když bajty [pointer, pointer + count) začínají literálem.
function report_prefix(pointer, count, key):
    if count < __lsl_qbe_load64(key + 8):
        return 0
    end
    return env_starts(pointer, key)
end

# Rada podle textu chyby (může pokračovat upřesněním, ", got String")
# nebo druhu chyby.
function report_help(text, kind, start, stop):
    message = text + start
    count = stop - start
    if report_prefix(message, count, "sequence index must be Int"):
        return "convert the index with Int(...)"
    end
    if report_prefix(message, count, "index must be Int"):
        return "convert the index with Int(...)"
    end
    if report_equal(text, kind, "TypeError"):
        return "check the types of the values; convert explicitly, for example with Int(value) or String(value)"
    end
    if report_equal(text, kind, "ValueError"):
        return "check that the value has the expected range, length or format"
    end
    if report_equal(text, kind, "IndexError"):
        return "check the index against len(...) before using it"
    end
    if report_equal(text, kind, "KeyError"):
        return "check that the key exists, for example with key in dictionary or dictionary.get(key, default)"
    end
    if report_equal(text, kind, "ZeroDivisionError"):
        return "check that the divisor is not zero before dividing"
    end
    if report_equal(text, kind, "NameError"):
        return "assign the variable or define the function before using it"
    end
    if report_equal(text, kind, "AttributeError"):
        return "check the method or field name for this type of value"
    end
    if report_equal(text, kind, "FileError") or report_equal(text, kind, "OSError"):
        return "check the path, permissions and available resources"
    end
    if report_equal(text, kind, "MemoryError"):
        return "reduce the amount of data kept in memory"
    end
    return "handle expected errors with try: ... else: ... end or safe: ... end"
end

# Hlášení nezachycené chyby vlákna a konec procesu se stavem 1.
function rt_runtime_uncaught_error():
    call io.rt_runtime_stdout_flush()
    color = rt_runtime_error_color()
    pending = __lsl_qbe_call1(__lsl_symbol("lsl_arch_tls_load"), TLS_ERROR)
    length = __lsl_qbe_load64(pending + 8)
    text = pending + 16
    kind = report_kind(text, length)
    start = 0
    if kind > 0:
        start = kind + 2
    end
    loc = __lsl_qbe_alloc(48)
    __lsl_qbe_store64(loc + LOC_PSTART, -1)
    __lsl_qbe_store64(loc + LOC_TEND, length)
    located = report_locate(text, length, start, loc)
    stop = __lsl_qbe_load64(loc + LOC_TEND)

    # error[Druh]: zpráva
    call report_color(color, COLOR_RED)
    call cold_report_text("error[")
    if kind > 0:
        call cold_report_write(text, kind)
    else:
        call cold_report_text("Error")
    end
    call cold_report_text("]: ")
    call cold_report_write(text + start, stop - start)
    call report_color(color, COLOR_RESET)
    call cold_report_text("\n")

    if located:
        path = __lsl_qbe_load64(loc + LOC_PSTART)
        call report_color(color, COLOR_BLUE)
        call cold_report_text(" --> ")
        call cold_report_write(text + path, length - path)
        call report_color(color, COLOR_RESET)
        call cold_report_text("\n")
        call report_source(text, color, loc)
    end

    call report_color(color, COLOR_CYAN)
    call cold_report_text(" help: ")
    call cold_report_text(report_help(text, kind, start, stop))
    call report_color(color, COLOR_RESET)
    call cold_report_text("\n")
    call io.stdin_release()
    call os.exit_process(1)
    return 0
end

# Selhání nastavení procesu při startu (thread pointer, signály): text
# a stav 71 dodává entry.
function rt_runtime_fatal_setup():
    return entry.cold_fatal_setup()
end
