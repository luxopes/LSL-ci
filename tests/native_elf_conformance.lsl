load native

test_root = arg(1)

race_target = None
race_started = IntArray()
race_started.append(0)
race_outcome = IntArray()
race_outcome.append(0)

function native_race_worker():
    call atomic_xchg(race_started, 0, 1)
    outcome = 0
    try:
        if native.call(race_target, [1, 2]) == 3:
            outcome = 1
        end
    else:
        outcome = 2
    end
    call atomic_xchg(race_outcome, 0, outcome)
    return None
end

function native_function_without_library(path):
    temporary_library = native.open(path)
    return native.symbol(temporary_library, "add")
end

function little(value, width):
    result = []
    index = 0
    while index < width:
        result.append(value % 256)
        value = value // 256
        index += 1
    end
    return result
end

function put(image, offset, values):
    index = 0
    while index < len(values):
        image[offset + index] = values[index]
        index += 1
    end
end

function sandbox_rejects(base_image, code, path):
    candidate = base_image[0:len(base_image)]
    call put(candidate, 64, [144, 144, 144, 144, 144, 144, 144])
    call put(candidate, 64, code)
    call writebytes(path, candidate)
    library = native.open(path)
    target = native.symbol(library, "add")
    rejected = False
    try:
        call native.call(target, [1, 2])
    else:
        rejected = True
    end
    call native.close(library)
    return rejected
end

image = []
for index in rang(384):
    image.append(0)
end
call put(image, 0, [127, 69, 76, 70, 2, 1, 1, 0])
call put(image, 16, little(3, 2))
call put(image, 18, little(62, 2))
call put(image, 20, little(1, 4))
call put(image, 40, little(128, 8))
call put(image, 52, little(64, 2))
call put(image, 58, little(64, 2))
call put(image, 60, little(4, 2))
call put(image, 64, [72, 137, 248, 72, 1, 240, 195])
call put(image, 72, [0, 97, 100, 100, 0])
call put(image, 104, little(1, 4))
image[108] = 18
call put(image, 110, little(1, 2))
call put(image, 112, little(64, 8))
call put(image, 120, little(7, 8))
call put(image, 196, little(1, 4))
call put(image, 200, little(6, 8))
call put(image, 208, little(64, 8))
call put(image, 216, little(64, 8))
call put(image, 224, little(7, 8))
call put(image, 240, little(16, 8))
call put(image, 260, little(3, 4))
call put(image, 280, little(72, 8))
call put(image, 288, little(5, 8))
call put(image, 304, little(1, 8))
call put(image, 324, little(11, 4))
call put(image, 344, little(80, 8))
call put(image, 352, little(48, 8))
call put(image, 360, little(2, 4))
call put(image, 364, little(1, 4))
call put(image, 368, little(8, 8))
call put(image, 376, little(24, 8))
valid_path = test_root + "/native-flat.so"
call writebytes(valid_path, image)

library = native.open(valid_path)
addition = native.symbol(library, "add")
print native.call(addition, [19, 23])
caught = ""
try:
    call native.symbol(library, "missing")
else:
    caught = last_error()
end
print caught
call native.close(library)
print native_size(library), native_u64(library, 0)
try:
    call native.close(library)
else:
    caught = last_error()
end
print caught
try:
    call native.call(addition, [1, 2])
else:
    caught = last_error()
end
print caught

# NativeFunction keeps its library alive across gc(), while close racing a
# call either lets the forked call finish or reports a controlled close error.
owned_function = native_function_without_library(valid_path)
call gc()
print native.call(owned_function, [20, 22])
owned_function = None
call gc()

race_safe = True
iteration = 0
while iteration < 16:
    race_library = native.open(valid_path)
    race_target = native.symbol(race_library, "add")
    call atomic_xchg(race_started, 0, 0)
    call atomic_xchg(race_outcome, 0, 0)
    race_thread = thread_spawn(native_race_worker)
    while race_started[0] == 0:
        call atomic_pause()
    end
    call native.close(race_library)
    call thread_join(race_thread)
    if race_outcome[0] != 1 and race_outcome[0] != 2:
        race_safe = False
    end
    iteration += 1
end
print race_safe

crash_rejected = sandbox_rejects(image, [72, 49, 192, 72, 139, 0, 195], test_root + "/native-crash.so")
syscall_rejected = sandbox_rejects(image, [106, 39, 88, 15, 5, 195], test_root + "/native-syscall.so")
hang_rejected = sandbox_rejects(image, [235, 254], test_root + "/native-hang.so")
print crash_rejected, syscall_rejected, hang_rejected

relocation_image = image[0:len(image)]
call put(relocation_image, 196, little(4, 4))
relocation_path = test_root + "/native-relocation.so"
call writebytes(relocation_path, relocation_image)
relocation_library = native.open(relocation_path)
try:
    call native.symbol(relocation_library, "add")
else:
    caught = last_error()
end
print caught
call native.close(relocation_library)

truncated_image = image[0:len(image)]
call put(truncated_image, 40, little(360, 8))
truncated_path = test_root + "/native-truncated.so"
call writebytes(truncated_path, truncated_image)
truncated_library = native.open(truncated_path)
try:
    call native.symbol(truncated_library, "add")
else:
    caught = last_error()
end
print caught
call native.close(truncated_library)

negative_image = image[0:len(image)]
call put(negative_image, 216, [0, 0, 0, 0, 0, 0, 0, 128])
negative_path = test_root + "/native-negative-offset.so"
call writebytes(negative_path, negative_image)
negative_library = native.open(negative_path)
try:
    call native.symbol(negative_library, "add")
else:
    caught = last_error()
end
print caught
call native.close(negative_library)

invalid_path = test_root + "/native-invalid.so"
call writebytes(invalid_path, [0])
try:
    call native.open(invalid_path)
else:
    caught = last_error()
end
print caught
