path = "/tmp/lsl-bytearray-conformance.bin"
bytes = ByteArray()
bytes.append(0)
bytes.append(65)
bytes.append(255)
print type(bytes), len(bytes), Bool(bytes), String(bytes), bytes[1], bytes[-1]
bytes[0] = 7
bytes[1] += 1
sum = 0
for value in bytes:
    sum += value
end
print String(bytes), List(bytes), sum
call writebytes(path, bytes)
loaded = readbytes(path)
print type(loaded), String(loaded), loaded == bytes
loaded.append(1)
call writebytes(path, loaded)
print String(readbytes(path))
print bytes == ByteArray(bytes)
try:
    bytes.append(256)
else:
    print last_error()
end
try:
    bytes[0] = -1
else:
    print last_error()
end
large = ByteArray()
for index in rang(300):
    large.append(index % 256)
end
call writebytes(path, large)
large_copy = readbytes(path)
print len(large_copy), large_copy[0], large_copy[255], large_copy[299], large_copy == large
call unlink(path)
bytes.clear()
print len(bytes), Bool(bytes), String(bytes)
