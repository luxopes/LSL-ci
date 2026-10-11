# lsl: internal-abi
# Known scalar operands must not be reinterpreted as managed object pointers.
# Inspect the raw result so a second dynamic equality cannot hide the failure.
int_anchor = __lsl_box_int(37)
bool_anchor = __lsl_box_bool(True)
zero = [0]
one = [1]
for anchor in [int_anchor, bool_anchor]:
    address = __lsl_address(anchor)
    print __lsl_raw_int(address - zero[0]) == address
    print __lsl_raw_int(zero[0] + address) == address
    print __lsl_raw_int(address * one[0]) == address
    print __lsl_raw_int(address ^ one[0]) == address
    print __lsl_raw_int(one[0] ^ address) == 1
    print address / one[0] == Float(address)
    typed = IntArray()
    call typed.append(0)
    print address - typed[0] == address
end
