function missing():
    return arg(99)
end
function inspect():
    value = arg(99)
    print value == None, value == "--help", type(value)
    print value
    print value is None, value is not None, missing() is None, missing() is not None
    print String(value), Bool(value)
    print missing() == None, missing() == "--help", type(missing())
    negative = arg(-1)
    print negative == None, negative == "--help", type(negative)
    present = arg(1)
    print present == "present", present != None, type(present)
end
call inspect()
