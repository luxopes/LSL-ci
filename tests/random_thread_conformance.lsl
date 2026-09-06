load random

r = random.Random(123)
function worker():
    for i in rang(500):
        call r.random()
    end
end

threads = [thread_spawn(worker) for i in rang(4)]
for thread in threads:
    check(thread_join(thread) == 0, "random worker")
end
serial = random.Random(123)
for i in rang(2000):
    call serial.random()
end
check(r.getstate() == serial.getstate(), "shared random state serialized")
print "random thread conformance passed"
