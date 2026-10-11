load _platform_linux_x86_64 as platform

function thread_id():
    return __lsl_syscall(platform.SYS_GETTID, 0, 0, 0, 0)
end
