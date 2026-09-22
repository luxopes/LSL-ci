# No heap allocation in the measured loop. Log the checksum with the time.
load time

limit = Int(arg(1))
checksum = 0
index = 0
started = time.monotonic()
while index < limit:
    checksum += index % 97
    index += 1
end
elapsed = time.monotonic() - started
call writefile(arg(2), "iterations=" + String(limit) + "\nseconds=" + String(elapsed) + "\nchecksum=" + String(checksum) + "\n")
