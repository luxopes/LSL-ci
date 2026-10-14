# Windows: terminál přes konzolové API. Surový režim = vstup bez echa,
# řádkového režimu a Ctrl+C (SetConsoleMode) s klávesami jako sekvence VT,
# výstup se sekvencemi VT (barvy, pohyb kurzoru) a vstupní kódová stránka
# UTF-8. Uložený stav je "vstup,výstup,kódová stránka" a leave ho vrátí.
# Argumenty surových volání Win32 musí být Int.
load fd

ENABLE_PROCESSED_INPUT = 1
ENABLE_LINE_INPUT = 2
ENABLE_ECHO_INPUT = 4
ENABLE_WINDOW_INPUT = 8
ENABLE_MOUSE_INPUT = 16
ENABLE_VIRTUAL_TERMINAL_INPUT = 512
ENABLE_PROCESSED_OUTPUT = 1
ENABLE_VIRTUAL_TERMINAL_PROCESSING = 4
KEY_EVENT = 1
WAIT_TIMEOUT = 258

function std_handle(kind):
    return Int(__lsl_qbe_call1(__lsl_symbol("GetStdHandle"), Int(kind)))
end

function console_mode(handle):
    mode = __lsl_byte_zeros(4)
    if Int(__lsl_qbe_call2(__lsl_symbol("GetConsoleMode"), Int(handle), Int(__lsl_data_address(mode)))) & 4294967295 == 0:
        Error(TUIError: "standard input and output must be a console")
    end
    return mode[0] + mode[1] * 256 + mode[2] * 65536 + mode[3] * 16777216
end

function set_mode(handle, mode):
    return Int(__lsl_qbe_call2(__lsl_symbol("SetConsoleMode"), Int(handle), Int(mode))) & 4294967295 != 0
end

# Konzole nemá stty; fasáda funkci zachovává kvůli kompatibilitě.
function stty_tool():
    Error(TUIError: "stty is not used on Windows (console API)")
    return ""
end

function enter_state():
    input = std_handle(-10)
    output = std_handle(-11)
    input_mode = console_mode(input)
    output_mode = console_mode(output)
    code_page = Int(__lsl_qbe_call0(__lsl_symbol("GetConsoleCP"))) & 4294967295
    saved = String(input_mode) + "," + String(output_mode) + "," + String(code_page)
    raw = (input_mode | ENABLE_VIRTUAL_TERMINAL_INPUT) & ~(ENABLE_ECHO_INPUT | ENABLE_LINE_INPUT | ENABLE_PROCESSED_INPUT | ENABLE_WINDOW_INPUT | ENABLE_MOUSE_INPUT)
    if not set_mode(input, raw) or not set_mode(output, output_mode | ENABLE_PROCESSED_OUTPUT | ENABLE_VIRTUAL_TERMINAL_PROCESSING):
        call set_mode(input, input_mode)
        Error(TUIError: "cannot enter terminal raw mode")
    end
    call __lsl_qbe_call1(__lsl_symbol("SetConsoleCP"), 65001)
    return saved
end

function restore_state(saved):
    parts = String(saved).split(",")
    if len(parts) != 3:
        Error(TUIError: "cannot restore terminal state")
    end
    restored = set_mode(std_handle(-10), Int(parts[0])) and set_mode(std_handle(-11), Int(parts[1]))
    call __lsl_qbe_call1(__lsl_symbol("SetConsoleCP"), Int(parts[2]))
    if not restored:
        Error(TUIError: "cannot restore terminal state")
    end
end

function signed16(buffer, offset):
    value = buffer[offset] + buffer[offset + 1] * 256
    if value >= 32768:
        value -= 65536
    end
    return value
end

# Viditelné okno konzole (CONSOLE_SCREEN_BUFFER_INFO.srWindow, +10..+17).
function dimensions():
    information = __lsl_byte_zeros(24)
    if Int(__lsl_qbe_call2(__lsl_symbol("GetConsoleScreenBufferInfo"), std_handle(-11), Int(__lsl_data_address(information)))) & 4294967295 == 0:
        return []
    end
    cols = signed16(information, 14) - signed16(information, 10) + 1
    rows = signed16(information, 16) - signed16(information, 12) + 1
    if rows >= 1 and rows <= 10000 and cols >= 1 and cols <= 10000:
        return [rows, cols]
    end
    return []
end

# 1, když lze číst bez čekání, 0 po timeout ms. Konzole je signalizovaná
# i událostmi bez znaku (puštění klávesy, fokus), které ReadFile přeskočí
# a čekal by: takové se tu z fronty vyřadí. Roura se kontroluje přes
# PeekNamedPipe.
function wait_readable(timeout):
    input = std_handle(-10)
    limit = Int(timeout)
    deadline = clock() + limit / 1000.0
    mode = __lsl_byte_zeros(4)
    console = Int(__lsl_qbe_call2(__lsl_symbol("GetConsoleMode"), input, Int(__lsl_data_address(mode)))) & 4294967295 != 0
    record = __lsl_byte_zeros(24)
    count = __lsl_byte_zeros(4)
    loop:
        left = Int((deadline - clock()) * 1000.0)
        if left < 0:
            left = 0
        end
        if not console:
            available = __lsl_byte_zeros(4)
            if Int(__lsl_qbe_call6(__lsl_symbol("PeekNamedPipe"), input, 0, 0, 0, Int(__lsl_data_address(available)), 0)) & 4294967295 == 0:
                # Jiný než konzole nebo roura (soubor): čtení nečeká.
                return 1
            end
            if available[0] + available[1] + available[2] + available[3] > 0:
                return 1
            end
            if left == 0:
                return 0
            end
            call __lsl_qbe_call1(__lsl_symbol("Sleep"), min(left, 10))
            continue
        end
        status = Int(__lsl_qbe_call2(__lsl_symbol("WaitForSingleObject"), input, left)) & 4294967295
        if status == WAIT_TIMEOUT:
            return 0
        elif status != 0:
            return -1
        end
        if Int(__lsl_qbe_call4(__lsl_symbol("PeekConsoleInputW"), input, Int(__lsl_data_address(record)), 1, Int(__lsl_data_address(count)))) & 4294967295 == 0:
            return -1
        end
        if count[0] == 0:
            continue
        end
        # INPUT_RECORD: +0 EventType, +4 bKeyDown.
        if record[0] == KEY_EVENT and record[4] != 0:
            return 1
        end
        call __lsl_qbe_call4(__lsl_symbol("ReadConsoleInputW"), input, Int(__lsl_data_address(record)), 1, Int(__lsl_data_address(count)))
    end
end
