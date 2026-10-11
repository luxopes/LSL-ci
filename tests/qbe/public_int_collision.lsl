# Public Any boundaries must unbox once, even when numeric bits equal a live
# managed object's address. These collisions are deliberate, not ASLR luck.
function convert(value):
    return Int(value)
end

function identity(value):
    return value
end

int_anchor = __lsl_box_int(37)
bool_anchor = __lsl_box_bool(True)
for anchor in [int_anchor, bool_anchor]:
    address = __lsl_address(anchor)
    boxed_address = __lsl_box_int(address)
    print __lsl_unbox_int(boxed_address) == address, Int(boxed_address) == address
    print convert(address) == address, Int(identity(address)) == address
    print convert(String(address)) == address, convert(Float(address)) == address
    print Int(boxed_address + 0) == address, Int(boxed_address * 1) == address
    print Bool(String(boxed_address) == String(address)), Bool(Float(boxed_address) == Float(address))
    values = [address]
    mapping = {"value": address}
    values[0] += 1
    mapping["value"] += 1
    print Int(values[0]) == address + 1, Int(mapping["value"]) == address + 1
    call gc()
    print Int(boxed_address) == address, __lsl_unbox_int(boxed_address) == address
end

print convert(0), convert(-1), convert(True), convert(False), convert(3.75), convert("-42")
print convert(-9223372036854775808), convert(9223372036854775807)
