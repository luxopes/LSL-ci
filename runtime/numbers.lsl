# lsl: runtime
# Převody čísel a textu: Int a Float na String a výstup, chr/ord, hodiny
# a spánek. Výstupy jsou bajt po bajtu stejné jako u dřívějších x86 rutin.
load _platform as platform
load core
load os_linux

# Exponent binary64 samých jedniček: nekonečno, nad ním NaN.
FLOAT_EXPONENT = 9218868437227405312

# Počet desítkových číslic čísla bez znaménka (1 až 20).
function unsigned_digits(value):
    count = 1
    power = 10
    while count < 20 and __lsl_qbe_ule(power, value):
        count += 1
        power = power * 10
    end
    return count
end

# Zapíše číslice čísla bez znaménka pozpátku tak, aby končily před end.
# Dělení deseti pod 2^32 je násobení (x * 0xCCCCCCCD) >> 35; větší čísla
# nejdřív po devíti číslicích skutečným dělením.
function write_unsigned(end, value):
    position = end
    while not __lsl_qbe_ult(value, 4294967296):
        high = __lsl_qbe_udiv(value, 1000000000)
        low = value - high * 1000000000
        count = 0
        while count < 9:
            quotient = __lsl_qbe_lshr(low * 3435973837, 35)
            position -= 1
            __lsl_qbe_store8(position, 48 + low - quotient * 10)
            low = quotient
            count += 1
        end
        value = high
    end
    while True:
        quotient = __lsl_qbe_lshr(value * 3435973837, 35)
        position -= 1
        __lsl_qbe_store8(position, 48 + value - quotient * 10)
        value = quotient
        if value == 0:
            break
        end
    end
    return 0
end

# Desítkový zápis Int se znaménkem od adresy buffer; vrací délku.
# Int minimum vychází z čísla bez znaménka 2^63.
function write_int(buffer, value):
    magnitude = value
    sign = 0
    if value < 0:
        magnitude = 0 - value
        sign = 1
        __lsl_qbe_store8(buffer, 45)
    end
    length = sign + unsigned_digits(magnitude)
    call write_unsigned(buffer + length, magnitude)
    return length
end

# Šest číslic zlomku (nižších řádů čísla bez znaménka) od adresy buffer.
function write_fraction6(buffer, value):
    value = __lsl_qbe_urem(value, 1000000)
    position = buffer + 6
    while position != buffer:
        quotient = __lsl_qbe_lshr(value * 3435973837, 35)
        position -= 1
        __lsl_qbe_store8(position, 48 + value - quotient * 10)
        value = quotient
    end
    return 6
end

# Nový String o length bajtech (zakončený nulou), data od +16.
function new_string(length):
    text = __lsl_qbe_call1(__lsl_symbol("rt_runtime_alloc"), length + 17)
    __lsl_qbe_store64(text, core.TAG_STRING)
    __lsl_qbe_store64(text + 8, length)
    __lsl_qbe_store8(text + 16 + length, 0)
    return text
end

function stdout_write(buffer, length):
    return __lsl_qbe_call2(__lsl_symbol("rt_runtime_stdout_write"), buffer, length)
end

function rt_runtime_print_string(text):
    call stdout_write(text + 16, __lsl_qbe_load64(text + 8))
    return 0
end

function rt_runtime_print_int(value):
    buffer = __lsl_qbe_alloc(32)
    call stdout_write(buffer, write_int(buffer, value))
    return 0
end

function rt_runtime_int_to_string(value):
    magnitude = value
    sign = 0
    if value < 0:
        magnitude = 0 - value
        sign = 1
    end
    length = sign + unsigned_digits(magnitude)
    text = new_string(length)
    call write_unsigned(text + 16 + length, magnitude)
    if sign:
        __lsl_qbe_store8(text + 16, 45)
    end
    return text
end

# Volitelné '-' a číslice bez kontroly (překladač ověřil text předem).
function rt_runtime_string_to_int(text):
    length = __lsl_qbe_load64(text + 8)
    data = text + 16
    if length == 0:
        return 0
    end
    index = 0
    negative = 0
    if __lsl_qbe_load8(data) == 45:
        negative = 1
        index = 1
    end
    value = 0
    while index < length:
        value = value * 10 + __lsl_qbe_load8(data + index) - 48
        index += 1
    end
    if negative:
        return 0 - value
    end
    return value
end

# UTF-8 kódového bodu; rozsah ověřuje volající.
function rt_runtime_chr(code):
    text = __lsl_qbe_call1(__lsl_symbol("rt_runtime_alloc"), 21)
    __lsl_qbe_store64(text, core.TAG_STRING)
    data = text + 16
    if __lsl_qbe_ult(code, 128):
        __lsl_qbe_store8(data, code)
        length = 1
    elif __lsl_qbe_ult(code, 2048):
        __lsl_qbe_store8(data, __lsl_qbe_ashr(code, 6) | 192)
        __lsl_qbe_store8(data + 1, (code & 63) | 128)
        length = 2
    elif __lsl_qbe_ult(code, 65536):
        __lsl_qbe_store8(data, __lsl_qbe_ashr(code, 12) | 224)
        __lsl_qbe_store8(data + 1, (__lsl_qbe_ashr(code, 6) & 63) | 128)
        __lsl_qbe_store8(data + 2, (code & 63) | 128)
        length = 3
    else:
        __lsl_qbe_store8(data, __lsl_qbe_ashr(code, 18) | 240)
        __lsl_qbe_store8(data + 1, (__lsl_qbe_ashr(code, 12) & 63) | 128)
        __lsl_qbe_store8(data + 2, (__lsl_qbe_ashr(code, 6) & 63) | 128)
        __lsl_qbe_store8(data + 3, (code & 63) | 128)
        length = 4
    end
    __lsl_qbe_store64(text + 8, length)
    __lsl_qbe_store8(data + length, 0)
    return text
end

# Kódový bod prvního znaku podle úvodního bajtu (bez kontroly UTF-8).
function rt_runtime_ord(text):
    first = __lsl_qbe_load8(text + 16)
    if first < 128:
        return first
    elif first < 224:
        return __lsl_qbe_shl(first & 31, 6) | (__lsl_qbe_load8(text + 17) & 63)
    elif first < 240:
        return __lsl_qbe_shl(first & 15, 12) | __lsl_qbe_shl(__lsl_qbe_load8(text + 17) & 63, 6) | (__lsl_qbe_load8(text + 18) & 63)
    end
    return __lsl_qbe_shl(first & 7, 18) | __lsl_qbe_shl(__lsl_qbe_load8(text + 17) & 63, 12) | __lsl_qbe_shl(__lsl_qbe_load8(text + 18) & 63, 6) | (__lsl_qbe_load8(text + 19) & 63)
end

function rt_runtime_print_fraction6(value):
    buffer = __lsl_qbe_alloc(8)
    call stdout_write(buffer, write_fraction6(buffer, value))
    return 0
end

function rt_runtime_fraction_string(value):
    text = new_string(6)
    call write_fraction6(text + 16, value)
    return text
end

# Pevný zápis Float: celá část (core.truncate_float), tečka a šest číslic zlomku,
# obojí useknuté k nule; mimo rozsah Int dává převod Int minimum jako
# dřív. Vrací délku; nekonečna a NaN řeší special_float_text.
function write_fixed_float(buffer, bits):
    length = 0
    if bits < 0:
        __lsl_qbe_store8(buffer, 45)
        length = 1
        bits = bits & 9223372036854775807
    end
    whole = core.truncate_float(bits)
    length += write_int(buffer + length, whole)
    __lsl_qbe_store8(buffer + length, 46)
    length += 1
    fraction = core.truncate_float(__lsl_raw_fmul(__lsl_raw_fsub(bits, __lsl_raw_fitof(whole)), 1000000.0))
    return length + write_fraction6(buffer + length, fraction)
end

# Text nekonečna nebo NaN (statický String), nebo 0 pro konečné číslo.
function special_float_text(bits):
    magnitude = bits & 9223372036854775807
    if __lsl_qbe_ult(magnitude, FLOAT_EXPONENT):
        return 0
    elif magnitude != FLOAT_EXPONENT:
        return "nan"
    elif bits < 0:
        return "-inf"
    end
    return "inf"
end

function rt_runtime_print_float(number):
    bits = __lsl_qbe_load64(number + 8)
    buffer = __lsl_qbe_alloc(48)
    special = special_float_text(bits)
    if special != 0:
        return rt_runtime_print_string(special)
    end
    call stdout_write(buffer, write_fixed_float(buffer, bits))
    return 0
end

function rt_runtime_float_to_string(number):
    bits = __lsl_qbe_load64(number + 8)
    buffer = __lsl_qbe_alloc(48)
    special = special_float_text(bits)
    if special != 0:
        return __lsl_qbe_call1(__lsl_symbol("rt_runtime_string_clone"), special)
    end
    length = write_fixed_float(buffer, bits)
    text = new_string(length)
    index = 0
    while index < length:
        __lsl_qbe_store8(text + 16 + index, __lsl_qbe_load8(buffer + index))
        index += 1
    end
    return text
end

function rt_runtime_print_true():
    return rt_runtime_print_string("True")
end

function rt_runtime_print_false():
    return rt_runtime_print_string("False")
end

function rt_runtime_print_none():
    return rt_runtime_print_string("None")
end

# Sekundy hodin jako Float: sekundy + nanosekundy / 1e9.
function clock_seconds(clock):
    timespec = __lsl_qbe_alloc(16)
    call os_linux.os_clock_gettime(clock, timespec)
    seconds = __lsl_raw_fitof(__lsl_qbe_load64(timespec))
    fraction = __lsl_raw_fdiv(__lsl_raw_fitof(__lsl_qbe_load64(timespec + 8)), 1000000000.0)
    return __lsl_qbe_call1(__lsl_symbol("rt_runtime_float_new"), __lsl_raw_fadd(seconds, fraction))
end

function rt_runtime_clock():
    return clock_seconds(platform.CLOCK_MONOTONIC)
end

function rt_runtime_wall_time():
    return clock_seconds(platform.CLOCK_REALTIME)
end

# Spánek na Float sekund (useknuto k nule); přerušení signálem pokračuje
# zbývající dobou, záporná nebo neplatná doba je chyba.
function rt_runtime_sleep(number):
    request = __lsl_qbe_alloc(16)
    remaining = __lsl_qbe_alloc(16)
    call __lsl_qbe_call0(__lsl_symbol("rt_runtime_stdout_flush"))
    bits = __lsl_qbe_load64(number + 8)
    seconds = core.truncate_float(bits)
    nanoseconds = core.truncate_float(__lsl_raw_fmul(__lsl_raw_fsub(bits, __lsl_raw_fitof(seconds)), 1000000000.0))
    __lsl_qbe_store64(request, seconds)
    __lsl_qbe_store64(request + 8, nanoseconds)
    __lsl_qbe_store64(remaining, 0)
    __lsl_qbe_store64(remaining + 8, 0)
    result = os_linux.os_nanosleep(request, remaining)
    while result == -platform.EINTR:
        __lsl_qbe_store64(request, __lsl_qbe_load64(remaining))
        __lsl_qbe_store64(request + 8, __lsl_qbe_load64(remaining + 8))
        result = os_linux.os_nanosleep(request, remaining)
    end
    if result < 0:
        call __lsl_qbe_call1(__lsl_symbol("qbe_error_set"), "ValueError: invalid sleep duration")
    end
    return 0
end
