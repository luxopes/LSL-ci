# lsl: internal-abi
load qbe_port.qbe_memory as mem
p = mem.malloc(64)
call mem.store(p, 1, 255)
call mem.store(p + 2, 2, 65535)
call mem.store(p + 4, 4, 4294967295)
call mem.store(p + 8, 8, -9223372036854775808)
check(mem.load(p, 1) == 255, "uint8")
check(mem.load(p, 1, True) == -1, "int8")
check(mem.load(p + 2, 2, True) == -1, "int16")
check(mem.load(p + 4, 4) == 4294967295, "uint32")
check(mem.load(p + 4, 4, True) == -1, "int32")
check(mem.load(p + 8, 8) == -9223372036854775808, "int64")
text = "QBE 1.3: žluťoučký"
source = mem.cstr(text)
call gc()
check(mem.text(source) == text, "UTF8 C lifetime across GC")
call mem.strcpy(p, source)
check(mem.strcmp(p, source) == 0, "strcpy")
call mem.memmove(p + 1, p, mem.strlen(p) + 1)
check(mem.text(p + 1) == text, "overlapping memmove")
p = mem.realloc(p, 128)
call gc()
check(mem.text(p + 1) == text, "realloc preserves bytes")
call mem.memset(p, 255, 32)
check(mem.load(p + 16, 8) == -1, "memset word fill")
call mem.free(p)
call mem.free(0)
zeroed = mem.calloc(513, 8)
check(zeroed % 16 == 0, "C max-alignment")
check(mem.load(zeroed + 4096, 8) == 0, "calloc spans pages")
call mem.store(zeroed, 8, 1234567)
smaller = mem.realloc(zeroed, 8)
check(mem.load(smaller, 8) == 1234567, "shrinking realloc")
call gc()
check(mem.load(smaller, 8) == 1234567, "explicit C ownership survives GC")
call mem.free(smaller)
# Reused small slabs must provide distinct, aligned slots and calloc must
# clear old contents rather than relying on fresh mmap pages.
pointers = []
for size in [0, 1, 16, 17, 48, 49, 112, 240, 496, 1008, 2032, 4080, 8176, 16368, 32752, 65520, 65521, 131072]:
    p = mem.malloc(size)
    check(p % 16 == 0, "slab and large max-alignment")
    call mem.memset(p, 165, max(1, size))
    pointers.append(p)
end
call gc()
for p in pointers:
    check(mem.load(p, 1) == 165, "distinct raw allocation lifetime")
    call mem.free(p)
end
for round in rang(20):
    dirty = mem.malloc(31)
    call mem.memset(dirty, 255, 31)
    call mem.free(dirty)
    clean = mem.calloc(31, 1)
    check(mem.load(clean, 8) == 0 and mem.load(clean + 30, 1) == 0, "calloc clears reused slab")
    call mem.free(clean)
end
p = mem.malloc(17)
call mem.memset(p, 37, 17)
p = mem.realloc(p, 40)
check(mem.load(p + 16, 1) == 37, "realloc within capacity")
p = mem.realloc(p, 100000)
check(mem.load(p + 16, 1) == 37, "slab to large realloc")
p = mem.realloc(p, 1)
check(mem.load(p, 1) == 37, "large to slab realloc")
call mem.free(p)
dirty = mem.malloc(31)
call mem.memset(dirty, 165, 31)
call mem.free(dirty)
c_text = mem.cstr("fresh C literal in reused slab")
check(mem.strlen(c_text) == 30 and mem.load(c_text + 30, 1) == 0, "cstr terminates reused allocation")

# Compare block-copy routines with byte snapshots for every tail length and
# source/destination alignment. memcpy ranges are disjoint; memmove covers
# both overlap directions at each source alignment.
copy_arena = mem.malloc(352)
for source_alignment in rang(8):
    for destination_alignment in rang(8):
        for count in rang(130):
            source = copy_arena + 8 + source_alignment
            destination = copy_arena + 176 + destination_alignment
            for index in rang(count):
                call mem.store(source + index, 1, (index * 37 + count) & 255)
            end
            snapshot = []
            for index in rang(count):
                snapshot.append(mem.load(source + index, 1))
            end
            check(mem.memcpy(destination, source, count) == destination,
                "memcpy returns destination")
            for index in rang(count):
                check(mem.load(destination + index, 1) == snapshot[index],
                    "memcpy aligned and unaligned block/tail result")
            end
        end
    end
end

for alignment in rang(8):
    for count in rang(130):
        for index in rang(176):
            call mem.store(copy_arena + index, 1, (index * 53 + count) & 255)
        end
        source = copy_arena + 16 + alignment
        destination = source + 1
        snapshot = []
        for index in rang(count):
            snapshot.append(mem.load(source + index, 1))
        end
        check(mem.memmove(destination, source, count) == destination,
            "right-overlap memmove returns destination")
        for index in rang(count):
            check(mem.load(destination + index, 1) == snapshot[index],
                "right-overlap memmove matches snapshot")
        end

        for index in rang(176):
            call mem.store(copy_arena + index, 1, (index * 71 + count) & 255)
        end
        source = copy_arena + 17 + alignment
        destination = source - 1
        snapshot = []
        for index in rang(count):
            snapshot.append(mem.load(source + index, 1))
        end
        check(mem.memmove(destination, source, count) == destination,
            "left-overlap memmove returns destination")
        for index in rang(count):
            check(mem.load(destination + index, 1) == snapshot[index],
                "left-overlap memmove matches snapshot")
        end
    end
end

# Signed and high-byte inputs must replicate their low eight bits across the
# 64-bit fill word and preserve the exact C byte result for every tail.
for byte in rang(-128, 128):
    for count in rang(130):
        destination = copy_arena + (byte & 7)
        check(mem.memset(destination, byte, count) == destination,
            "memset returns destination")
        expected_byte = byte & 255
        for index in rang(count):
            check(mem.load(destination + index, 1) == expected_byte,
                "memset arbitrary byte and tail result")
        end
    end
end
call mem.free(copy_arena)
print "PASS QBE memory"
