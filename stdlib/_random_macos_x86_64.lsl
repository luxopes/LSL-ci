# macOS: entropie ze systémového generátoru (arc4random_buf, libSystem).
# Argumenty surových volání musí být Int.

function _entropy(n):
    count = Int(n)
    data = __lsl_byte_zeros(count)
    if count > 0:
        call __lsl_qbe_call2(__lsl_symbol("arc4random_buf"), Int(__lsl_data_address(data)), count)
    end
    return data
end
