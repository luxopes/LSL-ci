# Unprivileged test executable, never part of the shipped updater.
if arg(1) == "overflow":
    call writebytes(arg(2), __lsl_byte_zeros(1048576))
elif arg(1) == "version":
    if exists(executable_path() + ".bad"):
        print "broken"
    else:
        print "0.7.7"
    end
elif arg(1) == "compile":
    if exists(executable_path() + ".no-compile"):
        exit(0)
    end
    call writebytes(arg(3), readbytes(executable_path()))
else:
    print "{\"ok\":true}"
end
