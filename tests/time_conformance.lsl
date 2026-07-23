load time

wall = time.time()
start = time.monotonic()
call time.sleep(0.002)
finish = time.perf_counter()
print wall > 1577836800.0, start > 0.0, finish >= start
print time.now() >= wall
print time.sleep(0) == None
try:
    call time.sleep(-0.001)
else:
    print last_error()
end
try:
    call time.sleep(Float("nan"))
else:
    print last_error()
end
