address = __lsl_syscall6(9, 0, 4096, 3, 34, -1, 0)
if address <= 0:
    Error(TestFailure: "six-argument mmap syscall failed")
end
if __lsl_syscall(11, address, 4096, 0, 0) != 0:
    Error(TestFailure: "munmap after six-argument syscall failed")
end
print "syscall6 conformance ok"
