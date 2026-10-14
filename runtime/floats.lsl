# lsl: runtime
# Float: objekt +0 tag 6, +8 bity binary64 (16 B). Aritmetika a převody se
# zabaleným výsledkem; bity jsou stejné jako u dřívějších x86 rutin (SSE2).
load core
load heap

FLOAT_SIGN = -9223372036854775808
FLOAT_MAGNITUDE = 9223372036854775807

function rt_runtime_float_new(bits):
    number = heap.rt_runtime_alloc(16)
    __lsl_qbe_store64(number, core.TAG_FLOAT)
    __lsl_qbe_store64(number + 8, bits)
    return number
end

function rt_runtime_float_from_int(value):
    return rt_runtime_float_new(__lsl_raw_fitof(value))
end

# Převod k nule; mimo rozsah Int dává Int minimum (core.truncate_float).
function rt_runtime_float_to_int(number):
    return core.truncate_float(__lsl_qbe_load64(number + 8))
end

# Soukromý akumulátor parseru: hodnota = hodnota * 10.0 + číslice, na místě
# (parser alokuje akumulátor jednou, ne dvakrát na číslici).
function rt_runtime_float_accumulate(number, digit):
    __lsl_qbe_store64(number + 8, __lsl_raw_fadd(__lsl_raw_fmul(__lsl_qbe_load64(number + 8), 10.0), __lsl_raw_fitof(digit)))
    return number
end

function rt_runtime_float_add(left, right):
    return rt_runtime_float_new(__lsl_raw_fadd(__lsl_qbe_load64(left + 8), __lsl_qbe_load64(right + 8)))
end

function rt_runtime_float_sub(left, right):
    return rt_runtime_float_new(__lsl_raw_fsub(__lsl_qbe_load64(left + 8), __lsl_qbe_load64(right + 8)))
end

function rt_runtime_float_mul(left, right):
    return rt_runtime_float_new(__lsl_raw_fmul(__lsl_qbe_load64(left + 8), __lsl_qbe_load64(right + 8)))
end

function rt_runtime_float_div(left, right):
    return rt_runtime_float_new(__lsl_raw_fdiv(__lsl_qbe_load64(left + 8), __lsl_qbe_load64(right + 8)))
end

# Odmocnina: ±0 projde, jinak záporné znaménko (i záporné NaN) je chyba.
# LuxIR nemá instrukci odmocniny, počítá ji vrstva architektury.
function rt_runtime_float_sqrt(number):
    bits = __lsl_qbe_load64(number + 8)
    if bits & FLOAT_MAGNITUDE != 0 and bits < 0:
        call __lsl_qbe_call1(__lsl_symbol("qbe_error_set"), "ValueError: sqrt domain error")
        return 0
    end
    return rt_runtime_float_new(__lsl_qbe_call1(__lsl_symbol("lsl_arch_sqrt"), bits))
end

# Mocnina Float na Int umocňováním na druhou (nejvýš 64 kroků i pro
# libovolný exponent); záporný exponent včetně Int minima dá převrácenou
# hodnotu. Pořadí násobení je stejné jako dřív, bity výsledku také.
function rt_runtime_float_power(number, exponent):
    base = __lsl_qbe_load64(number + 8)
    result = 1.0
    negative = exponent < 0
    if negative:
        exponent = 0 - exponent
    end
    while exponent != 0:
        if exponent & 1:
            result = __lsl_raw_fmul(result, base)
        end
        exponent = __lsl_qbe_lshr(exponent, 1)
        if exponent == 0:
            break
        end
        base = __lsl_raw_fmul(base, base)
    end
    if negative:
        result = __lsl_raw_fdiv(1.0, result)
    end
    return rt_runtime_float_new(result)
end
