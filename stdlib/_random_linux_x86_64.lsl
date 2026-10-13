load _platform as platform

function _entropy(n):
    data = __lsl_byte_zeros(n)
    offset = 0
    while offset < n:
        count = __lsl_syscall(platform.SYS_GETRANDOM, __lsl_data_address(data) + offset, n - offset, 0, 0)
        if count == -4:
            continue
        elif count <= 0 or count > n - offset:
            Error(OSError: "random: getrandom failed")
        end
        offset += count
    end
    return data
end
