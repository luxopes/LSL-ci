# Windows: entropie ze systémového generátoru (BCryptGenRandom, bcrypt.dll,
# BCRYPT_USE_SYSTEM_PREFERRED_RNG). Argumenty surových volání musí být Int
# (hodnota typu Any by se předala jako ukazatel na objekt).

function _entropy(n):
    count = Int(n)
    data = __lsl_byte_zeros(count)
    if count > 0:
        address = Int(__lsl_data_address(data))
        status = Int(__lsl_qbe_call4(__lsl_symbol("BCryptGenRandom"), 0, address, count, 2)) & 4294967295
        if status != 0:
            Error(OSError: "random: BCryptGenRandom failed")
        end
    end
    return data
end
