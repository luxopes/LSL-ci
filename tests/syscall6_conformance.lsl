load _platform as platform
address = __lsl_syscall6(platform.SYS_MMAP, 0, 4096, platform.PROT_READ | platform.PROT_WRITE, platform.MAP_PRIVATE | platform.MAP_ANONYMOUS, -1, 0)
if address <= 0:
    Error(TestFailure: "six-argument mmap syscall failed")
end
if __lsl_syscall(platform.SYS_MUNMAP, address, 4096, 0, 0) != 0:
    Error(TestFailure: "munmap after six-argument syscall failed")
end
print "syscall6 conformance ok"
