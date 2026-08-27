link = arg(1)
target = arg(2)
data = ByteArray()
data.append(1)

write_failed = False
append_failed = False
bytes_failed = False
try:
    call writefile(link, "changed")
else:
    write_failed = True
end
try:
    call appendfile(link, "changed")
else:
    append_failed = True
end
try:
    call writebytes(link, data)
else:
    bytes_failed = True
end
print write_failed, append_failed, bytes_failed, readfile(target)
