# lsl: internal-abi
load qbe_port.qbe_memory as mem
check(mem.function_alloc(0) == 0, "zero PFn allocation")
# A function consisting only of a dedicated large mapping leaves no retained
# chunk; the next allocation must still restart from valid zeroed storage.
large = mem.function_alloc(2097153)
call mem.memset(large, 91, 2097153)
call mem.function_reset()
small = mem.function_alloc(16)
check(mem.load(small, 8) == 0 and mem.load(small + 8, 8) == 0,
    "restart after dedicated mapping release")
call mem.function_reset()
for repeat in rang(8):
    pointers = []
    for size in [1, 15, 16, 17, 31, 32, 255, 4097, 65536, 1048575, 1048593]:
        address = mem.function_alloc(size)
        check(address % 16 == 0, "arena alignment")
        for offset in rang(size):
            check(__lsl_qbe_load8(address + offset) == 0, "arena zero initialization")
        end
        call mem.memset(address, 173, size)
        pointers.append([address, size])
    end
    call gc()
    for item in pointers:
        address = __lsl_qbe_raw_int(item[0])
        size = __lsl_qbe_raw_int(item[1])
        check(__lsl_qbe_load8(address) == 173 and __lsl_qbe_load8(address + size - 1) == 173, "arena distinct lifetimes")
    end
    call mem.function_reset()
end
print "PASS function arena zeroing, alignment, lifetime, reset"
