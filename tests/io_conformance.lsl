path = "/tmp/lsl-io-conformance.txt"
call writefile(path, "a")
call appendfile(path, "b")
print readfile(path)
print clock() > 0.0
call unlink(path)
