# lsl: runtime
# Jádra FloatArray (+8 počet, +24 surové bity binary64). Pořadí operací je
# stejné jako u dřívějších x86 rutin s dvojicemi SSE2, takže bity výsledků
# se neliší: sum a dot sčítají sudé a liché prvky zvlášť (lichý konec patří
# k sudým) a nakonec sudé + liché; axpy, fill a matmul počítají po prvcích.
load core
load heap
load floats

TAG_FLOAT_ARRAY = 14

# Bity jako String (8 bajtů na prvek, little-endian, zakončený nulou).
function rt_runtime_float_array_bytes(array):
    count = __lsl_qbe_load64(array + 8)
    source = __lsl_qbe_load64(array + 24)
    size = __lsl_qbe_shl(count, 3)
    text = heap.rt_runtime_alloc(size + 17)
    __lsl_qbe_store64(text, core.TAG_STRING)
    __lsl_qbe_store64(text + 8, size)
    target = text + 16
    offset = 0
    while offset < size:
        __lsl_qbe_store64(target + offset, __lsl_qbe_load64(source + offset))
        offset += 8
    end
    __lsl_qbe_store8(target + size, 0)
    return text
end

# Opak float_array_bytes; přebytečné bajty (délka mod 8) se ignorují.
function rt_runtime_float_array_from_bytes(text):
    array = __lsl_qbe_call2(__lsl_symbol("rt_runtime_list_new"), __lsl_qbe_lshr(__lsl_qbe_load64(text + 8), 3), text + 16)
    __lsl_qbe_store64(array, TAG_FLOAT_ARRAY)
    return array
end

function rt_runtime_float_array_sum(array):
    count = __lsl_qbe_load64(array + 8)
    data = __lsl_qbe_load64(array + 24)
    even = 0
    odd = 0
    pairs_end = data + __lsl_qbe_shl(count & -2, 3)
    position = data
    while position != pairs_end:
        even = __lsl_raw_fadd(even, __lsl_qbe_load64(position))
        odd = __lsl_raw_fadd(odd, __lsl_qbe_load64(position + 8))
        position += 16
    end
    if count & 1:
        even = __lsl_raw_fadd(even, __lsl_qbe_load64(position))
    end
    return floats.rt_runtime_float_new(__lsl_raw_fadd(even, odd))
end

# Délka podle prvního pole (jako dřív).
function rt_runtime_float_array_dot(left, right):
    count = __lsl_qbe_load64(left + 8)
    a = __lsl_qbe_load64(left + 24)
    b = __lsl_qbe_load64(right + 24)
    even = 0
    odd = 0
    pairs_end = a + __lsl_qbe_shl(count & -2, 3)
    while a != pairs_end:
        even = __lsl_raw_fadd(even, __lsl_raw_fmul(__lsl_qbe_load64(a), __lsl_qbe_load64(b)))
        odd = __lsl_raw_fadd(odd, __lsl_raw_fmul(__lsl_qbe_load64(a + 8), __lsl_qbe_load64(b + 8)))
        a += 16
        b += 16
    end
    if count & 1:
        even = __lsl_raw_fadd(even, __lsl_raw_fmul(__lsl_qbe_load64(a), __lsl_qbe_load64(b)))
    end
    return floats.rt_runtime_float_new(__lsl_raw_fadd(even, odd))
end

# y += alpha * x po prvcích; počet podle x.
function rt_runtime_float_array_axpy(alpha, x, y):
    count = __lsl_qbe_load64(x + 8)
    source = __lsl_qbe_load64(x + 24)
    target = __lsl_qbe_load64(y + 24)
    finish = source + __lsl_qbe_shl(count, 3)
    while source != finish:
        __lsl_qbe_store64(target, __lsl_raw_fadd(__lsl_qbe_load64(target), __lsl_raw_fmul(__lsl_qbe_load64(source), alpha)))
        source += 8
        target += 8
    end
    return 0
end

function rt_runtime_float_array_fill(array, bits):
    position = __lsl_qbe_load64(array + 24)
    finish = position + __lsl_qbe_shl(__lsl_qbe_load64(array + 8), 3)
    while position != finish:
        __lsl_qbe_store64(position, bits)
        position += 8
    end
    return 0
end

# C[m,n] = A[m,k] · B[k,n], pořadí i-k-j: C[i,j] += B[k,j] · A[i,k] ve stejném
# pořadí k jako skalární součin. list_new výsledek vynuluje.
function rt_runtime_float_array_matmul(left, right, m, k, n):
    a = __lsl_qbe_load64(left + 24)
    b = __lsl_qbe_load64(right + 24)
    result = __lsl_qbe_call2(__lsl_symbol("rt_runtime_list_new"), m * n, 0)
    __lsl_qbe_store64(result, TAG_FLOAT_ARRAY)
    c = __lsl_qbe_load64(result + 24)
    row_bytes = __lsl_qbe_shl(n, 3)
    i = 0
    while i < m:
        row = c + i * row_bytes
        row_end = row + row_bytes
        a_row = a + __lsl_qbe_shl(i * k, 3)
        inner = 0
        while inner < k:
            factor = __lsl_qbe_load64(a_row + __lsl_qbe_shl(inner, 3))
            source = b + inner * row_bytes
            target = row
            while target != row_end:
                __lsl_qbe_store64(target, __lsl_raw_fadd(__lsl_qbe_load64(target), __lsl_raw_fmul(__lsl_qbe_load64(source), factor)))
                source += 8
                target += 8
            end
            inner += 1
        end
        i += 1
    end
    return result
end
