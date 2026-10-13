load _platform as platform

function thread_id():
    return __lsl_syscall(platform.SYS_GETTID, 0, 0, 0, 0)
end
