unsafe:
    print __lsl_syscall(39, 0, 0, 0, 0) > 0
end
print "unsafe block explicit"
