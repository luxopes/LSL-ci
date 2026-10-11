# Scalar, String, filesystem, process, and rang builtins reached through an
# escaped Function receive public boxed Any values. Invalid tags must become
# catchable errors before a pointer is interpreted as a scalar or object.

function dynamic_chr(value):
    return chr(value)
end

function dynamic_ord(value):
    return ord(value)
end

function dynamic_arg(value):
    return arg(value)
end

function dynamic_rang(stop):
    total = 0
    for value in rang(stop):
        total += value
    end
    return total
end

function dynamic_exists(path):
    return exists(path)
end

function dynamic_read(path):
    return readfile(path)
end

function dynamic_write(path, value):
    return writefile(path, value)
end

function dynamic_writebytes(path, value):
    return writebytes(path, value)
end

function dynamic_run(program, arguments):
    return run(program, arguments)
end

function dynamic_join_thread(tid):
    return thread_join(tid)
end

function dynamic_exit(status):
    exit(status)
end

function dynamic_list(value):
    return List(value)
end

function dynamic_tuple(value):
    return Tuple(value)
end

function dynamic_real_array(value):
    return RealArray(value)
end

function dynamic_dictionary(value):
    return Dictionary(value)
end

escaped = [dynamic_chr, dynamic_ord, dynamic_arg, dynamic_rang, dynamic_exists, dynamic_read, dynamic_write, dynamic_writebytes, dynamic_run, dynamic_join_thread, dynamic_exit, dynamic_list, dynamic_tuple, dynamic_real_array, dynamic_dictionary]

# A missing argument is None. The old arg:String inference incorrectly
# reported String here without inspecting the missing runtime value.
print dynamic_chr(65), dynamic_ord("A"), type(dynamic_arg(999)), dynamic_rang(4)
print dynamic_exists("/definitely/missing/lsl-boundary-file")
integers = IntArray()
integers.append(1)
integers.append(-2)
floats = FloatArray()
floats.append(1.5)
bytes = ByteArray()
bytes.append(65)
print dynamic_list(integers), dynamic_list(floats), dynamic_list(bytes), dynamic_tuple("ab")
print dynamic_real_array(integers), dynamic_real_array(floats), dynamic_dictionary([("a", 1)])

try:
    print dynamic_chr("65")
else:
    print last_error()
end
try:
    print dynamic_ord(65)
else:
    print last_error()
end
try:
    print dynamic_arg("0")
else:
    print last_error()
end
try:
    print dynamic_rang("4")
else:
    print last_error()
end
try:
    print dynamic_exists(1)
else:
    print last_error()
end
try:
    print dynamic_read(1)
else:
    print last_error()
end
try:
    print dynamic_write("/tmp/unused", 1)
else:
    print last_error()
end
try:
    print dynamic_writebytes("/tmp/unused", "bytes")
else:
    print last_error()
end
try:
    print dynamic_run(1, [])
else:
    print last_error()
end
try:
    print dynamic_run("/bin/true", 1)
else:
    print last_error()
end
try:
    print dynamic_join_thread("1")
else:
    print last_error()
end
try:
    call dynamic_exit("1")
else:
    print last_error()
end
try:
    print dynamic_list(42)
else:
    print last_error()
end
try:
    print dynamic_real_array(["x"])
else:
    print last_error()
end
try:
    print dynamic_dictionary(42)
else:
    print last_error()
end
try:
    print dynamic_dictionary([1])
else:
    print last_error()
end
