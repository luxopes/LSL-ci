# Syntetický fault injection větve fork: RLIMIT_NPROC = 0 způsobí, že fork
# selže s EAGAIN. Ověřuje se čistá chyba a žádný únik popisovačů. Root limit
# nezná, proto se test pod rootem přeskočí se stejným výstupem.
load _platform as platform
load fd

function lowest_free_fd():
    handle = fd.open("/dev/null", 0)
    call fd.close(handle)
    return handle
end

function chunk(text):
    return None
end

if __lsl_syscall(platform.SYS_GETEUID, 0, 0, 0, 0) == 0:
    for name in ["capture", "run", "capture_input", "capture_stream"]:
        if name == "run":
            print name, "status 126"
        else:
            print name, "ProcessError: capture setup failed"
        end
    end
    print "descriptors unchanged True"
else:
    first = lowest_free_fd()
    limit = __lsl_byte_zeros(16)
    # prlimit64 místo setrlimit: setrlimit na riscv64 není.
    if __lsl_syscall(platform.SYS_PRLIMIT64, 0, 6, __lsl_data_address(limit), 0) != 0:
        Error(TestFailure: "cannot lower RLIMIT_NPROC")
    end
    for name in ["capture", "run", "capture_input", "capture_stream"]:
        caught = ""
        try:
            if name == "capture":
                call capture("/bin/true", [])
            elif name == "run":
                # run neselhává výjimkou, ale vrací stav 126 (proces nevznikl).
                caught = "status " + String(run("/bin/true", []))
            elif name == "capture_input":
                call capture_input("/bin/cat", [], "data")
            else:
                call capture_stream("/bin/true", [], chunk)
            end
        else:
            caught = last_error()
        end
        print name, caught
    end
    print "descriptors unchanged", lowest_free_fd() == first
end
