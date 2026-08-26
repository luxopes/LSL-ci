function dynamic_identity(value):
    return value + 0
end

object = ["live"]
address = __lsl_address(object)
through_call = dynamic_identity(address)
through_list = [address][0]
through_dict = {address: "int", "object": object}
print type(through_call), __lsl_type_code(through_call), through_call == address
print type(through_list), __lsl_type_code(through_list), through_list == address
print through_dict[address], type(through_dict.keys()[0]), through_dict["object"] == object
print through_call == object, through_list == object
call gc()
print through_call == address, through_dict[address]

# A raw Int can also equal the address of a boxed Int. Static Int boundaries
# must box those bits directly instead of mistaking the existing box for the
# value being passed.
boxed_owner = [123456789]
boxed_address = __lsl_address(boxed_owner[0])
boxed_address_list = [boxed_address]
boxed_address_dict = {boxed_address: "address"}
print __lsl_unbox_int(boxed_address_list[0]) == __lsl_raw_int(boxed_address)
print boxed_address_dict[boxed_address] == "address"
