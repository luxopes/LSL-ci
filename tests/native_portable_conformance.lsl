# Nativní knihovna na každém systému: stejný obraz ELF (čistý kód) se volá
# izolovaně (Linux: fork a strict seccomp, Windows a macOS: dceřiný proces).
# Výsledek, pád, zacyklení a zavřená knihovna; zakázaná systémová volání
# ověřuje jen Linux (native_elf_conformance).
load native
load env
load random
load _platform as platform

CODE = {
    62: {"add": [72, 137, 248, 72, 1, 240, 195], "crash": [72, 49, 192, 72, 139, 0, 195], "syscall": [106, 39, 88, 15, 5, 195], "hang": [235, 254]},
    183: {"add": [0, 0, 1, 139, 192, 3, 95, 214], "crash": [0, 0, 128, 210, 0, 0, 64, 249], "syscall": [136, 21, 128, 210, 1, 0, 0, 212], "hang": [0, 0, 0, 20]},
    243: {"add": [51, 5, 181, 0, 103, 128, 0, 0], "crash": [3, 53, 0, 0, 103, 128, 0, 0], "syscall": [147, 8, 192, 10, 115, 0, 0, 0], "hang": [111, 0, 0, 0]}
}[platform.ELF_MACHINE]

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

function with_code(base_image, code, path):
    candidate = base_image[0:len(base_image)]
    call put(candidate, 64, code)
    call writebytes(path, candidate)
    return native.open(path)
end

function rejected(library):
    target = native.symbol(library, "add")
    failed = False
    try:
        call native.call(target, [1, 2])
    else:
        failed = last_error().startswith("NativeError")
    end
    call native.close(library)
    return failed
end

directory = env.get("TMPDIR", env.get("TEMP", "/tmp"))
path = directory + "/lsl-native-" + String(random.randint(100000000, 999999999)) + ".so"
image = []
for index in rang(384):
    image.append(0)
end
call put(image, 0, [127, 69, 76, 70, 2, 1, 1, 0])
call put(image, 16, little(3, 2))
call put(image, 18, little(platform.ELF_MACHINE, 2))
call put(image, 20, little(1, 4))
call put(image, 40, little(128, 8))
call put(image, 52, little(64, 2))
call put(image, 58, little(64, 2))
call put(image, 60, little(4, 2))
call put(image, 64, CODE["add"])
call put(image, 72, [0, 97, 100, 100, 0])
call put(image, 104, little(1, 4))
image[108] = 18
call put(image, 110, little(1, 2))
call put(image, 112, little(64, 8))
call put(image, 120, little(len(CODE["add"]), 8))
call put(image, 196, little(1, 4))
call put(image, 200, little(6, 8))
call put(image, 208, little(64, 8))
call put(image, 216, little(64, 8))
call put(image, 224, little(len(CODE["add"]), 8))
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
call writebytes(path, image)
library = native.open(path)
addition = native.symbol(library, "add")
print native.call(addition, [19, 23]), native.call(addition, [-5, 2])
call native.close(library)
try:
    call native.call(addition, [1, 2])
else:
    print last_error()
end
print "crash rejected", rejected(with_code(image, CODE["crash"], path))
print "hang rejected", rejected(with_code(image, CODE["hang"], path))
call unlink(path)
