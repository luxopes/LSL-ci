# lsl: runtime
# Procesy bez shellu (run, capture), prostředí a cesta programu. Obecná
# logika; spuštění, čekání a deskriptory dodává vrstva OS.
load _platform as platform
load core
load _runtime_os as os

# Stav: výsledek posledního capture() a jeho stderr (String, kořen GC).
CAPTURE_STATUS = 64
CAPTURE_STDERR = 72
# Bufferovaný stdin pro input(): +1280 režim (1 = bufferovaný soubor),
# +1288 buffer (slovo 0 naplněno, slovo 1 pozice čtení).
STDIN_MODE = 1280
STDIN_BUFFER = 1288

# Limity: argv položek, bajtů argumentu (MAX_ARG_STRLEN s nulou), vstupu,
# zachyceného stdout a stderr.
MAX_ARGUMENTS = 4096
MAX_ARGUMENT_BYTES = 131071
MAX_INPUT_BYTES = 67108864
MAX_STDOUT_BYTES = 67108864
MAX_STDERR_BYTES = 16777216

function error_pending():
    return __lsl_qbe_call0(__lsl_symbol("qbe_error_flag"))
end

function set_error(message):
    call __lsl_qbe_call1(__lsl_symbol("qbe_error_set"), message)
    return 0
end

# Před potomkem: vyprázdní stdout a vrátí předčtená data stdin do pozice
# souboru, aby potomek četl tam, kde input() logicky skončil.
function stdio_release():
    call __lsl_qbe_call0(__lsl_symbol("rt_runtime_stdout_flush"))
    state = core.state()
    if __lsl_qbe_load64(state + STDIN_MODE) != 1:
        return 0
    end
    buffer = __lsl_qbe_load64(state + STDIN_BUFFER)
    filled = __lsl_qbe_load64(buffer)
    position = __lsl_qbe_load64(buffer + 8)
    if not __lsl_qbe_ult(position, filled):
        return 0
    end
    __lsl_qbe_store64(buffer + 8, filled)
    call os.os_lseek(0, position - filled, platform.SEEK_CUR)
    return 0
end

# Živý String bez vnitřní nuly a v limitu Linuxu MAX_ARG_STRLEN.
function rt_runtime_process_string_valid(value):
    if not core.rt_runtime_is_heap_object(value):
        return 0
    elif __lsl_qbe_load64(value) != core.TAG_STRING:
        return 0
    end
    length = __lsl_qbe_load64(value + 8)
    if length > MAX_ARGUMENT_BYTES:
        return 0
    end
    data = value + 16
    index = 0
    while index < length:
        if __lsl_qbe_load8(data + index) == 0:
            return 0
        end
        index += 1
    end
    return 1
end

# Program a seznam argumentů (List, nejvýš MAX_ARGUMENTS položek).
function process_call_valid(executable, arguments):
    if not rt_runtime_process_string_valid(executable):
        return 0
    elif not core.rt_runtime_is_heap_object(arguments):
        return 0
    elif __lsl_qbe_load64(arguments) != 2:
        return 0
    end
    return __lsl_qbe_load64(arguments + 8) <= MAX_ARGUMENTS
end

# argv pro execve: program, argumenty a nula; 0 pro neplatný argument.
function build_argv(executable, arguments):
    count = __lsl_qbe_load64(arguments + 8)
    argv = __lsl_qbe_call1(__lsl_symbol("rt_runtime_alloc_raw"), __lsl_qbe_shl(count + 2, 3))
    __lsl_qbe_store64(argv, executable + 16)
    items = __lsl_qbe_load64(arguments + 24)
    index = 0
    while index < count:
        item = __lsl_qbe_load64(items + __lsl_qbe_shl(index, 3))
        if not rt_runtime_process_string_valid(item):
            return 0
        end
        __lsl_qbe_store64(argv + __lsl_qbe_shl(index + 1, 3), item + 16)
        index += 1
    end
    __lsl_qbe_store64(argv + __lsl_qbe_shl(count + 1, 3), 0)
    return argv
end

# run(program, argumenty): kód ukončení, 128 + signál, nebo 126 při chybě.
# callback a input generovaný kód předává jen kvůli stejné signatuře.
function rt_runtime_run(executable, arguments, callback, input, clean):
    if not process_call_valid(executable, arguments):
        return 126
    end
    argv = build_argv(executable, arguments)
    if argv == 0:
        return 126
    end
    call stdio_release()
    pid = os.os_spawn(executable + 16, argv, clean, -1, -1, -1, -1)
    if pid < 0:
        return 126
    end
    code = os.os_wait(pid)
    if code < 0:
        return 126
    end
    return code
end

# run_clean s časovým limitem (interní builtin pro knihovny na Windows
# a macOS): po seconds sekundách vrstva OS potomka ukončí a výsledek je 124
# jako u timeout; 126 při chybě spuštění.
function rt_runtime_run_timeout(executable, arguments, seconds):
    if seconds < 1 or seconds > 3600 or not process_call_valid(executable, arguments):
        return 126
    end
    argv = build_argv(executable, arguments)
    if argv == 0:
        return 126
    end
    call stdio_release()
    pid = os.os_spawn(executable + 16, argv, 1, -1, -1, -1, -1)
    if pid < 0:
        return 126
    end
    watch = os.process_deadline(pid, seconds * 1000)
    if watch == 0:
        call os.os_kill(pid)
        call os.os_wait(pid)
        return 126
    end
    call os.os_wait_exit(pid)
    expired = os.process_deadline_cancel(watch)
    code = os.os_wait(pid)
    if code < 0:
        return 126
    elif expired:
        return 124
    end
    return code
end

# Předá přečtený kus stdout funkci capture_stream jako nový String; po
# chybě (i z dřívějšího volání) už nevolá nic.
function rt_runtime_capture_callback(callback, data, length):
    if callback == 0 or error_pending():
        return 0
    end
    text = __lsl_qbe_call1(__lsl_symbol("rt_runtime_alloc"), length + 17)
    __lsl_qbe_store64(text, core.TAG_STRING)
    __lsl_qbe_store64(text + 8, length)
    index = 0
    while index < length:
        __lsl_qbe_store8(text + 16 + index, __lsl_qbe_load8(data + index))
        index += 1
    end
    __lsl_qbe_store8(text + 16 + length, 0)
    function_address = core.rt_runtime_unbox_dynamic_function(callback)
    call __lsl_qbe_call1(function_address, text)
    return 0
end

# Přečte deskriptor do konce do nového Stringu (zdvojnásobuje kapacitu od
# 4 KiB). Nad limit nebo při chybě čtení nastaví chybu a skončí. stream:
# každý kus jde do capture_callback a chyba z něj čtení ukončí.
function read_all(fd, limit, stream, callback):
    capacity = 4096
    buffer = __lsl_qbe_call1(__lsl_symbol("rt_runtime_alloc"), capacity + 17)
    __lsl_qbe_store64(buffer, core.TAG_STRING)
    filled = 0
    while True:
        if filled == capacity:
            if capacity >= limit:
                call set_error("ProcessError: captured process output exceeds the secure limit")
                break
            end
            capacity = capacity * 2
            grown = __lsl_qbe_call1(__lsl_symbol("rt_runtime_alloc"), capacity + 17)
            __lsl_qbe_store64(grown, core.TAG_STRING)
            # Plný buffer má délku násobek 8: kopie po slovech.
            offset = 0
            while offset < filled:
                __lsl_qbe_store64(grown + 16 + offset, __lsl_qbe_load64(buffer + 16 + offset))
                offset += 8
            end
            buffer = grown
        end
        count = os.os_read(fd, buffer + 16 + filled, capacity - filled)
        if count < 0:
            call set_error("ProcessError: capture I/O failed")
            break
        elif count == 0:
            break
        end
        if stream:
            call rt_runtime_capture_callback(callback, buffer + 16 + filled, count)
        end
        filled += count
        if stream and error_pending():
            break
        end
    end
    __lsl_qbe_store64(buffer + 8, filled)
    __lsl_qbe_store8(buffer + 16 + filled, 0)
    return buffer
end

function close_if_open(fd):
    if fd >= 0:
        call os.os_close(fd)
    end
    return 0
end

# capture(program, argumenty, callback, input, clean): stdout jako String,
# kód do capture_status(), stderr do capture_stderr(). Volitelný stdin je
# memfd (žádné uváznutí ani u velkého vstupu), stderr také memfd.
function rt_runtime_capture(executable, arguments, callback, input, clean):
    return capture_core(executable, arguments, callback, input, clean, 0)
end

# capture_input_clean s časovým limitem (interní builtin pro knihovny na
# Windows a macOS, kde není coreutils timeout): po seconds sekundách vrstva
# OS potomka ukončí a stav je 124 jako u timeout.
function rt_runtime_capture_timeout(executable, arguments, input, seconds):
    if seconds < 1 or seconds > 3600:
        return set_error("ProcessError: timeout must be between 1 and 3600 seconds")
    end
    return capture_core(executable, arguments, 0, input, 1, seconds * 1000)
end

function capture_core(executable, arguments, callback, input, clean, milliseconds):
    fds = __lsl_qbe_alloc(8)
    state = core.state()
    # Chybové cesty nesmí ukázat výsledek předchozího capture.
    __lsl_qbe_store64(state + CAPTURE_STATUS, 126)
    __lsl_qbe_store64(state + CAPTURE_STDERR, 0)
    valid = process_call_valid(executable, arguments)
    if valid and input != 0:
        if not core.rt_runtime_is_heap_object(input) or __lsl_qbe_load64(input) != core.TAG_STRING:
            valid = 0
        elif __lsl_qbe_load64(input + 8) > MAX_INPUT_BYTES:
            valid = 0
        end
    end
    argv = 0
    if valid:
        argv = build_argv(executable, arguments)
    end
    if argv == 0:
        return set_error("ProcessError: invalid executable, argument or input")
    end
    __lsl_qbe_store64(fds, 0)
    if os.os_pipe(fds) < 0:
        return set_error("ProcessError: capture setup failed")
    end
    read_end = __lsl_qbe_s32(__lsl_qbe_load32(fds))
    write_end = __lsl_qbe_s32(__lsl_qbe_load32(fds + 4))
    error_fd = os.os_memfd("lsl-stderr")
    input_fd = -1
    ready = error_fd >= 0
    if ready and input != 0:
        input_fd = os.os_memfd("lsl-stdin")
        if input_fd < 0:
            ready = 0
        elif os.os_write_all(input_fd, input + 16, __lsl_qbe_load64(input + 8)) < 0:
            ready = 0
        elif os.os_lseek(input_fd, 0, platform.SEEK_SET) < 0:
            ready = 0
        end
    end
    pid = -1
    if ready:
        call stdio_release()
        pid = os.os_spawn(executable + 16, argv, clean, input_fd, write_end, error_fd, read_end)
    end
    if pid < 0:
        call close_if_open(input_fd)
        call close_if_open(error_fd)
        call os.os_close(read_end)
        call os.os_close(write_end)
        return set_error("ProcessError: capture setup failed")
    end
    call os.os_close(write_end)
    call close_if_open(input_fd)
    watch = 0
    if milliseconds > 0:
        watch = os.process_deadline(pid, milliseconds)
        if watch == 0:
            call os.os_kill(pid)
            call os.os_close(read_end)
            call os.os_wait(pid)
            call os.os_close(error_fd)
            return set_error("ProcessError: process timeout is unavailable")
        end
    end
    output = read_all(read_end, MAX_STDOUT_BYTES, 1, callback)
    # Po chybě (callback, čtení, limit) potomka ukončí před čekáním, jinak
    # by potomek ignorující SIGPIPE mohl běžet navždy.
    if error_pending():
        call os.os_kill(pid)
    end
    call os.os_close(read_end)
    # Hlídání limitu skončí před úklidem potomka: signál ani TerminateProcess
    # pak nemůže zasáhnout jiný proces se stejným pid.
    expired = 0
    if watch != 0:
        # Limit platí až do konce potomka, i když už zavřel výstup.
        call os.os_wait_exit(pid)
        expired = os.process_deadline_cancel(watch)
    end
    code = os.os_wait(pid)
    if expired and code >= 0:
        code = 124
    end
    if code < 0:
        call set_error("ProcessError: capture I/O failed")
        code = 126
    end
    __lsl_qbe_store64(state + CAPTURE_STATUS, code)
    # stderr v memfd nemůže uváznout jako druhá roura; přečte se od začátku.
    if os.os_lseek(error_fd, 0, platform.SEEK_SET) < 0:
        call set_error("ProcessError: capture I/O failed")
    end
    errors = read_all(error_fd, MAX_STDERR_BYTES, 0, 0)
    call os.os_close(error_fd)
    __lsl_qbe_store64(state + CAPTURE_STDERR, errors)
    return output
end

function rt_runtime_capture_status():
    return __lsl_qbe_load64(core.state() + CAPTURE_STATUS)
end

function rt_runtime_capture_stderr():
    return __lsl_qbe_load64(core.state() + CAPTURE_STDERR)
end

function rt_runtime_executable_path():
    text = __lsl_qbe_call1(__lsl_symbol("rt_runtime_alloc"), 4113)
    __lsl_qbe_store64(text, core.TAG_STRING)
    length = os.os_executable_path(text + 16, 4096)
    if length < 0 or length >= 4096:
        return set_error("FileError: cannot resolve executable path")
    end
    __lsl_qbe_store64(text + 8, length)
    __lsl_qbe_store8(text + 16 + length, 0)
    return text
end

function ascii_lower(byte):
    if byte >= 65 and byte <= 90:
        return byte + 32
    end
    return byte
end

# Hodnota proměnné prostředí jako String, nebo 0 (None).
function rt_runtime_getenv(name):
    if not rt_runtime_process_string_valid(name):
        return 0
    end
    length = __lsl_qbe_load64(name + 8)
    wanted = name + 16
    entry_pointer = os.os_environment()
    while True:
        entry = __lsl_qbe_load64(entry_pointer)
        if entry == 0:
            return 0
        end
        index = 0
        while index < length:
            byte = __lsl_qbe_load8(entry + index)
            # Delší hledané jméno nesmí číst za konec položky.
            if byte == 0:
                break
            end
            other = __lsl_qbe_load8(wanted + index)
            if byte != other:
                # Windows: jména proměnných bez ohledu na velikost písmen
                # ASCII (Path i PATH).
                if not os.ENV_IGNORE_CASE or ascii_lower(byte) != ascii_lower(other):
                    break
                end
            end
            index += 1
        end
        if index == length and __lsl_qbe_load8(entry + length) == 61:
            return __lsl_qbe_call1(__lsl_symbol("rt_runtime_from_cstring"), entry + length + 1)
        end
        entry_pointer += 8
    end
    return 0
end

# Jen pro testy: RLIMIT_NOFILE 32, vyčerpání memfd deskriptory a uvolnění
# slots nejvyšších. slots=0 shodí pipe, slots=2 pustí pipe a shodí memfd.
# Vrací počet otevřených deskriptorů, nebo -1.
function rt_runtime_test_fd_fault(slots):
    if os.os_limit_descriptors(32) < 0:
        return -1
    end
    count = 0
    last = -1
    while True:
        fd = os.os_memfd("lsl-fd-fault")
        if fd < 0:
            break
        end
        last = fd
        count += 1
    end
    while slots > 0 and last >= 3:
        call os.os_close(last)
        last -= 1
        slots -= 1
    end
    return count
end
