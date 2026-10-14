# Bare metal: entropie z CSR seed (RISC-V Zkr), jinak z /dev/urandom
# hostitele přes semihosting (runtime, os_baremetal); bez obojího random bez
# seed hlásí chybu (deterministický generátor se zadaným seed funguje).
# Argumenty surových volání musí být Int.

function _entropy(n):
    count = Int(n)
    data = __lsl_byte_zeros(count)
    if count > 0:
        status = Int(__lsl_qbe_call2(__lsl_symbol("lsl_baremetal_entropy"), Int(__lsl_data_address(data)), count))
        if status != 0:
            Error(OSError: "random: no entropy source on bare metal (no Zkr seed CSR, no semihosting host)")
        end
    end
    return data
end
