load _platform as platform
function pid():
    return __lsl_syscall(platform.SYS_GETPID, 0, 0, 0, 0)
end
