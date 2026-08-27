function dynamic_identity(value):
    return value + 0
end

function dynamic_floor_identity(value):
    return value // 1
end

function dynamic_mod_identity(value):
    return value % (value + 1)
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
through_sum = sum([address, 0])
print type(through_sum), __lsl_type_code(through_sum), through_sum == address, through_sum == object
through_floor = dynamic_floor_identity(address)
through_mod = dynamic_mod_identity(address)
print type(through_floor), through_floor == address, type(through_mod), through_mod == address
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
