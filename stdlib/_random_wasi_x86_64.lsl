# WebAssembly (WASI): entropie z random_get hostitele. Argumenty surových
# volání musí být Int.

function _entropy(n):
    count = Int(n)
    data = __lsl_byte_zeros(count)
    if count > 0:
        status = Int(__lsl_qbe_call2(__lsl_symbol("lsl_wasi_random_get"), Int(__lsl_data_address(data)), count))
        if status != 0:
            Error(OSError: "random: random_get failed")
        end
    end
    return data
end
