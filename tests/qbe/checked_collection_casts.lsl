ints = IntArray()
ints.append(42)
floats = FloatArray()
floats.append(1.25)
bytes = ByteArray()
bytes.append(65)
check(__lsl_address(IntArray(ints)) == __lsl_address(ints), "IntArray cast changed identity")
check(__lsl_address(FloatArray(floats)) == __lsl_address(floats), "FloatArray cast changed identity")
check(__lsl_address(ByteArray(bytes)) == __lsl_address(bytes), "ByteArray cast changed identity")
function invalid_cast(value):
    caught = 0
    try:
        call IntArray(value)
    else:
        check(last_error() == "TypeError: IntArray(value) only converts an existing IntArray; create an empty one with IntArray() and add items with append", "IntArray error changed")
        caught += 1
    end
    try:
        call FloatArray(value)
    else:
        check(last_error() == "TypeError: FloatArray(value) only converts an existing FloatArray; create an empty one with FloatArray() and add items with append", "FloatArray error changed")
        caught += 1
    end
    try:
        call ByteArray(value)
    else:
        check(last_error() == "TypeError: ByteArray(value) only converts an existing ByteArray; create an empty one with ByteArray() and add items with append", "ByteArray error changed")
        caught += 1
    end
    check(caught == 3, "an invalid typed-array cast succeeded")
end
escaped = invalid_cast
for value in [[], [1, 2.5], {}, "bytes", 42, True, None]:
    call invalid_cast(value)
end
check(ints[0] == 42 and floats[0] == 1.25 and bytes[0] == 65, "cast mutated storage")
print "typed collection casts preserve identity and reject other objects"
