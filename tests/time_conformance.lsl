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
# 0.9.1: UTC kalendář, ISO-8601, strftime a parse_iso8601.
for t in [0, 951782400, 1700000000, -1, 1784592000, 1700000000.833305, 1700000000.9999996, -0.5, 253402300799]:
    print t, time.iso8601(t), time.iso8601(t, 0), time.strftime("%a %A %b %B %d %e %j %u %w %y %I %p %F %T %s %z %Z %%", t)
end
print time.utc(951782400)
print time.parse_iso8601("2026-10-09T04:01:53.833305+00:00"), time.parse_iso8601("2000-02-29T00:00:00Z"), time.parse_iso8601("2026-10-09T06:01:53+02:00"), time.parse_iso8601("1969-12-31T23:59:59Z")
now = time.time()
print time.parse_iso8601(time.iso8601(now)) - now < 0.000002
for bad in ["2026-02-29T00:00:00Z", "2026-10-09T04:01:53", "2026-10-09 04:01:53Z", "2026-13-01T00:00:00Z", "2026-10-09T04:01:53.Z", "2026-10-09T04:01:53+0200", "x", "2026-10-09T24:00:00Z", "2026-10-09T04:01:53Zjunk"]:
    try:
        print time.parse_iso8601(bad)
    else:
        print "error", last_error()
    end
end
for call_case in [0, 1, 2, 3, 4]:
    try:
        if call_case == 0:
            print time.strftime("%Q", 0)
        elif call_case == 1:
            print time.strftime("50%", 0)
        elif call_case == 2:
            print time.iso8601(0, 7)
        elif call_case == 3:
            print time.iso8601("now")
        else:
            print time.iso8601(1e15)
        end
    else:
        print "error", last_error()
    end
end
