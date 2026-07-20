try:
    print readfile("/definitely/missing/lsl-conformance-file")
else:
    print last_error()
end
try:
    call writefile("/definitely/missing/lsl-dir/file", "x")
else:
    print last_error()
end
try:
    call writebytes("/definitely/missing/lsl-dir/file", [1, 2])
else:
    print last_error()
end
try:
    call appendfile("/definitely/missing/lsl-dir/file", "x")
else:
    print last_error()
end
