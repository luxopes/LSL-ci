load time

if arg(1) == "child":
    call time.sleep(0.15)
    print "child done"
    exit(17)
end

finished = IntArray()
finished.append(0)

function allocating_worker():
    for index in rang(12000):
        values = [index, {"key": "x" * 128}]
        bytes = ByteArray()
        for byte in rang(20):
            bytes.append(byte)
        end
        check(values[0] == index and len(values[1]["key"]) == 128, "worker object lost")
        check(bytes[19] == 19, "worker buffer lost")
        if index % 200 == 0:
            call time.sleep(0.001)
        end
    end
    finished[0] = 1
    return None
end

function process_worker():
    status = run(executable_path(), ["child"])
    check(status == 17, "GC interrupted run/wait4")
    output = capture(executable_path(), ["child"])
    check(output == "child done\n" and capture_status() == 17, "GC interrupted capture/read/wait4")
    finished[0] = 1
    return None
end

# Join must collect even when the main program is doing no allocation itself.
worker = thread_spawn(allocating_worker)
check(thread_join(worker) == 0 and finished[0] == 1, "allocation worker failed")
finished[0] = 0
worker = thread_spawn(process_worker)
while finished[0] == 0:
    temporary = "abcdefgh" * 256
end
check(thread_join(worker) == 0, "process worker failed")
print "automatic GC while joining and during worker process IO passed"
