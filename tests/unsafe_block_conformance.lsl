load _platform as platform
unsafe:
    print __lsl_syscall(platform.SYS_GETPID, 0, 0, 0, 0) > 0
end
print "unsafe block explicit"
