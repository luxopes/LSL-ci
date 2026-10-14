# Helper for stdio_buffer_conformance: exercises the buffered stdin/stdout
# runtime paths from a child that the test drives through /bin/sh.
load _platform as platform
load fd
mode = arg(1)
if mode == "handoff":
    # Two buffered lines, then /bin/cat inherits the rest of stdin: the
    # runtime must hand the unread bytes back before the fork and flush the
    # prints so the output order is preserved.
    print "start"
    first = input("")
    second = input("")
    print "read", first, second
    status = run("/bin/cat", [])
    print "cat", status
elif mode == "mixed":
    # Střídání vysokoúrovňového input a přímého čtení/seek nesmí ztratit data.
    print input("")
    buffer = ByteArray()
    for index in rang(6):
        buffer.append(0)
    end
    print "raw", fd.read(0, buffer, 6), buffer[0], buffer[5]
    print input("")
    call fd.seek(0, 0)
    print "seek", input("")
elif mode == "reopen":
    print input("")
    call fd.close(0)
    reopened = fd.open(arg(2), fd.read_only)
    print "reopen", reopened, input("")
elif mode == "redirect":
    # dup2 a opětovné otevření stdin musí zrušit dřívější buffer i detekci.
    print input("")
    other = fd.open(arg(2), fd.read_only)
    print "dup", __lsl_syscall(platform.SYS_DUP3, other, 0, 0, 0)
    print "redirect", input("")
    call fd.close(0)
    reopened = fd.open(arg(2), fd.read_only)
    print "reopen", reopened, input("")
elif mode == "error":
    print "before error"
    Error(ValueError: "boom")
elif mode == "exit":
    print "before exit"
    exit(3)
elif mode == "big":
    # Well over the 64 KiB buffer, mixed value kinds.
    for index in rang(30000):
        print index, "x", index * 2 == index + index, 1.5
    end
elif mode == "prompt":
    # The prompt must reach stdout before the read blocks.
    name = input("name? ")
    print "hello", name
elif mode == "stderr":
    print "to stdout"
    message = ByteArray()
    for ch in "to stderr" + chr(10):
        call message.append(ord(ch))
    end
    call fd.write(2, message, len(message))
    print "after stderr"
end
