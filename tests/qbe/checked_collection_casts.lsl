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
        check(last_error() == "TypeError: IntArray cast requires an existing IntArray", "IntArray error changed")
        caught += 1
    end
    try:
        call FloatArray(value)
    else:
        check(last_error() == "TypeError: FloatArray cast requires an existing FloatArray", "FloatArray error changed")
        caught += 1
    end
    try:
        call ByteArray(value)
    else:
        check(last_error() == "TypeError: ByteArray cast requires an existing ByteArray", "ByteArray error changed")
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
