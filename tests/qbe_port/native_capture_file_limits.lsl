# Captured tools must retain stricter inherited regular-file output limits.
function file_limits():
    data = __lsl_byte_zeros(16)
    check(__lsl_syscall(97, 1, __lsl_data_address(data), 0, 0) == 0, "getrlimit")
    result = []
    for start in [0, 8]:
        value = 0
        for index in rang(8):
            value |= data[start + index] << (index * 8)
        end
        result.append(value)
    end
    return result
end
if arg(1) == "child":
    limits = file_limits()
    print limits[0], limits[1]
else:
    before = file_limits()
    output = capture_clean(executable_path(), ["child"])
    status = capture_status()
    after = file_limits()
    check(status == 0, "capture child failed")
    check(before == after, "capture changed caller limits")
    print "before", before[0], before[1]
    print "captured", output.strip()
    print "after", after[0], after[1]
end
