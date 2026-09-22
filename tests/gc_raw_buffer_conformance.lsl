# A raw backing pointer is not a language object. Its leading 2/11 must
# not become a fake List or NativeLibrary header during conservative GC.
# This is a deliberate internal-ABI boundary test.
function collect_with_pointer(a, b, c, d, e, f, g, pointer):
    # Arguments 7/8 must be stack roots even if the callee keeps an Int local
    # in a register.
    call gc()
    return pointer + 0
end

for tag in [2, 3, 7, 8, 11, 12, 13, 14, 15, 16]:
    buffer = ByteArray()
    for value in [tag, 1, 1, 0, 123, 456, 789, 42]:
        for byte in rang(8):
            buffer.append((Int(value) >> (byte * 8)) & 255)
        end
    end
    unsafe:
        address = __lsl_data_address(buffer)
    end
    check(address != 0, "expected a real backing pointer")
    unsafe:
        check(__lsl_type_code(address) == 0, "raw buffer classified as an object")
    end
    check(collect_with_pointer(address, address, address, address, address, address, address, address) == address, "raw pointer changed")
    check(buffer[0] == tag and buffer[56] == 42, "raw data changed")
end
print "raw backing pointers are not traced or finalized as objects"
