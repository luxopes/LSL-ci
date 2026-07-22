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
