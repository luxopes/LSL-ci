load _platform as platform
load x11
load fd
load time

function require(value, message):
    if not value:
        Error(TestFailure: message)
    end
end

function pair():
    unsafe:
        handles = __lsl_byte_zeros(8)
        call require(__lsl_syscall(platform.SYS_SOCKETPAIR, 1, 526337, 0, __lsl_data_address(handles)) == 0, "socketpair")
        writer = x11.get32(handles, 0)
        reader = x11.get32(handles, 4)
        size = __lsl_byte_zeros(4)
        size[1] = 16
        call require(__lsl_syscall6(platform.SYS_SETSOCKOPT, writer, 1, 7, __lsl_data_address(size), 4, 0) == 0, "small send buffer")
    end
    return (writer, reader)
end

reader_state = IntArray()
for value in [0, 0, 1]:
    call reader_state.append(Int(value))
end
expected = ByteArray()

function slow_reader():
    call time.sleep(0.05)
    unsafe:
        chunk = __lsl_byte_zeros(4096)
    end
    offset = 0
    deadline = monotonic() + 5.0
    while offset < len(expected) and monotonic() < deadline:
        count = fd.read(reader_state[0], chunk, len(chunk))
        if count == fd.again:
            call time.sleep(0.001)
        elif count == 0:
            break
        else:
            for index in rang(count):
                if offset + index >= len(expected) or chunk[index] != expected[offset + index]:
                    reader_state[2] = 0
                end
            end
            offset += count
        end
    end
    reader_state[1] = offset
end

for image_mode in [False, True]:
    handles = pair()
    reader_state[0] = Int(handles[1])
    reader_state[1] = 0
    reader_state[2] = 1
    expected = ByteArray()
    unsafe:
        packed = __lsl_byte_zeros(65536)
        request = __lsl_byte_zeros(65560)
    end
    for index in rang(len(packed)):
        packed[index] = index % 251
    end
    if image_mode:
        call expected.append(72)
        call expected.append(2)
        call x11.put16(expected, 16390)
        call x11.put32(expected, 7)
        call x11.put32(expected, 9)
        call x11.put16(expected, 32)
        call x11.put16(expected, 512)
        call x11.put16(expected, 0)
        call x11.put16(expected, 0)
        for value in [0, 24, 0, 0]:
            call expected.append(Int(value))
        end
    end
    for value in packed:
        call expected.append(Int(value))
    end
    unsafe:
        worker = thread_spawn(slow_reader)
    end
    failure = None
    try:
        if image_mode:
            call x11.put_image(handles[0], 7, 9, 24, 32, 512, packed, request)
        else:
            call x11.send_bytes(handles[0], packed)
        end
    else:
        failure = last_error()
    end
    call fd.close(handles[0])
    unsafe:
        call thread_join(worker)
    end
    call fd.close(handles[1])
    call require(failure == None, "partial X11 send: " + String(failure))
    call require(reader_state[1] == len(expected) and reader_state[2] == 1, "X11 bytes lost, duplicated or reordered")
end

handles = pair()
unsafe:
    packed = __lsl_byte_zeros(65536)
end
failure = None
started = monotonic()
try:
    call x11.write_bytes(handles[0], packed, len(packed), 0.05)
else:
    failure = last_error()
end
call require(failure != None and "timed out sending graphics" in String(failure), "bounded stalled receiver")
call require(monotonic() - started < 1.0, "X11 timeout ignored")
call fd.close(handles[0])
call fd.close(handles[1])

handles = pair()
call fd.close(handles[1])
failure = None
try:
    call x11.send_bytes(handles[0], packed)
else:
    failure = last_error()
end
call require(failure != None and "X11Error:" in String(failure), "closed peer did not produce a catchable error")
call fd.close(handles[0])
print "X11 partial writes, backpressure, PutImage bytes, timeout and peer closure passed"
