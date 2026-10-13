# lsl: runtime
# Řetězce: String objekt má +0 tag 1, +8 délku v bajtech a od +16 bajty UTF-8
# zakončené nulou.
load core

# Rovnost: stejný ukazatel, stejná délka a stejné bajty (po 8 bajtech).
function rt_runtime_string_equal(left, right):
    if left == right:
        return 1
    end
    remaining = __lsl_qbe_load64(left + 8)
    if remaining != __lsl_qbe_load64(right + 8):
        return 0
    end
    a = left + 16
    b = right + 16
    while remaining >= 8:
        if __lsl_qbe_load64(a) != __lsl_qbe_load64(b):
            return 0
        end
        a += 8
        b += 8
        remaining -= 8
    end
    while remaining > 0:
        if __lsl_qbe_load8(a) != __lsl_qbe_load8(b):
            return 0
        end
        a += 1
        b += 1
        remaining -= 1
    end
    return 1
end

# Finalizér SplitMix64 (stejný jako x86 runtime_hash_mix).
function hash_mix(value):
    x = value ~ __lsl_qbe_lshr(value, 30)
    x = x * -4658895280553007687
    x = x ~ __lsl_qbe_lshr(x, 27)
    x = x * -7723592293110705685
    return x ~ __lsl_qbe_lshr(x, 31)
end

# FNV-1a nad bajty se seedem procesu (stav +120), pak SplitMix64.
function string_hash(text):
    h = __lsl_qbe_load64(core.state() + 120)
    position = text + 16
    finish = position + __lsl_qbe_load64(text + 8)
    while __lsl_qbe_ult(position, finish):
        h = (h ~ __lsl_qbe_load8(position)) * 1099511628211
        position += 1
    end
    return hash_mix(h)
end
