load fd
load unixsock

function security_noop():
    return None
end

bytes = __lsl_byte_zeros(0)
bytes.append(65)
print len(bytes), bytes[0], arg(-1) == None

negative_int = False
negative_bytes = False
try:
    call __lsl_int_zeros(-1)
else:
    negative_int = True
end
try:
    call __lsl_byte_zeros(-1)
else:
    negative_bytes = True
end
print negative_int, negative_bytes

values = IntArray()
values.append(7)
add_bounds = False
xchg_bounds = False
cas_bounds = False
try:
    call atomic_add(values, 1, 2)
else:
    add_bounds = True
end
try:
    call atomic_xchg(values, -2, 2)
else:
    xchg_bounds = True
end
try:
    call atomic_cas(values, 8, 7, 9)
else:
    cas_bounds = True
end
print add_bounds, xchg_bounds, cas_bounds, values[0]

buffer = ByteArray()
buffer.append(1)
buffer.append(2)
buffer.append(3)
print __lsl_fd_read(-1, buffer, -1), __lsl_fd_write(-1, buffer, -1)
print unixsock.send_fd(-1, buffer, 4, -1), unixsock.send_from_fd(-1, buffer, -1, 1, -1)
print unixsock.recv_fds(-1, buffer, -1, []), fd.mmap(-1, -1, -1)

print run("/bin/true" + chr(0) + "ignored", [])
invalid_capture = False
try:
    call capture("/bin/true", ["safe" + chr(0) + "ignored"])
else:
    invalid_capture = True
end
print invalid_capture

print __lsl_getenv(0) == None
print native_size(0), native_u64(0, 0), native_name_equal(0, 0, "x"), native_function(0, 0), native_close(0)
invalid_native_call = False
try:
    call native_call(0, [])
else:
    invalid_native_call = True
end
print invalid_native_call

nul_path = "/definitely-missing" + chr(0) + "ignored"
path_failed = False
try:
    call readfile(nul_path)
else:
    path_failed = True
end
print path_failed, not exists(nul_path), __lsl_fd_open(nul_path, 0)

# Raw device helpers reject forged object values before dereferencing them.
print __lsl_fd_read(-1, 0, 1), __lsl_fd_write(-1, 0, 1), __lsl_fd_connect(-1, 0, 1), __lsl_fd_ioctl(-1, 0, 0)
print __lsl_data_address(0), __lsl_text_byte(0, 0), __lsl_text_from_bytes(0, 0, 1) == ""
print __lsl_raster_pack(0, 0, 0, 0, 1), __lsl_byte_copy(0, 0, 0, 0, 1), __lsl_mem_pack(1, 0, 0, 0, 1), __lsl_mem_unpack(0, 0, 1, 1)

# Exponent work is bounded by the Int width, and dynamic Int semantics match
# statically typed Int semantics for negative exponents.
print 1 ^ 9223372036854775807, 1.0 ^ -9223372036854775808
dynamic_ints = [2]
dynamic_negative_power = False
try:
    call dynamic_ints[0] ^ -1
else:
    dynamic_negative_power = True
end
print dynamic_negative_power

# Function rendering must not disclose a PIE code address, and a dynamic
# non-Function passed to thread_spawn must fail without starting a worker.
invalid_callbacks = [0]
print security_noop, thread_spawn(invalid_callbacks[0])

# Text-to-number conversion and recursive equality have explicit work/depth
# ceilings instead of allowing attacker-controlled CPU or native stack use.
oversized_number = "0" * 4097
int_text_limited = False
float_text_limited = False
try:
    call Int(oversized_number)
else:
    int_text_limited = True
end
try:
    call Float(oversized_number)
else:
    float_text_limited = True
end
deep_left = []
deep_right = []
left_cursor = deep_left
right_cursor = deep_right
depth = 0
while depth < 66:
    next_left = []
    next_right = []
    left_cursor.append(next_left)
    right_cursor.append(next_right)
    left_cursor = next_left
    right_cursor = next_right
    depth += 1
end
comparison_limited = False
try:
    call deep_left == deep_right
else:
    comparison_limited = True
end
print int_text_limited, float_text_limited, comparison_limited

deep_gc_root = []
gc_cursor = deep_gc_root
depth = 0
while depth < 300:
    next_gc = []
    gc_cursor.append(next_gc)
    gc_cursor = next_gc
    depth += 1
end
call gc()
gc_cursor = deep_gc_root
survived_depth = 0
while len(gc_cursor) == 1:
    gc_cursor = gc_cursor[0]
    survived_depth += 1
end
print survived_depth == 300

snapshot_path = arg(1) + "/fd-snapshot-input"
call writebytes(snapshot_path, [1, 0, 0, 0])
snapshot_fd = fd.open(snapshot_path, fd.read_only)
snapshot_address = __lsl_fd_snapshot(snapshot_fd, 0, 4)
call writebytes(snapshot_path, [9, 0, 0, 0])
snapshot_value = __lsl_int_zeros(1)
call __lsl_mem_unpack(snapshot_value, 0, snapshot_address, 1)
call unixsock.munmap(snapshot_address, 4)
call fd.close(snapshot_fd)
print snapshot_value[0], __lsl_fd_snapshot(-1, -1, 0)

cyclic_list = []
cyclic_list.append(cyclic_list)
cyclic_dictionary = {}
cyclic_dictionary["self"] = cyclic_dictionary
print String(cyclic_list), String(cyclic_dictionary)
print "ab" * 3, "ab".replace("", "-")
sortable = [5, 1, 4, 1, 3, 2]
call sortable.sort()
print sortable
