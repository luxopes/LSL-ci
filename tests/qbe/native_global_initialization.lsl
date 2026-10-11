function read_text(flag):
    if flag:
        print len(text)
    end
end
call read_text(False)
safe:
    call read_text(True)
end
print last_error().startswith("NameError:")
text = "ok"
call read_text(True)
del(text)
safe:
    call read_text(True)
end
print last_error().startswith("NameError:")

function erase_text():
    del(text)
end
text = "new"
callback = erase_text
call callback()
safe:
    print len(text)
end
print last_error().startswith("NameError:")
text = "again"
print len(text)

# Zero and None are valid initialized values, not uninitialized sentinels.
function read_number():
    return number
end
safe:
    print read_number()
end
print last_error().startswith("NameError:")
number = 0
print read_number()
del(number)
safe:
    print read_number()
end
print last_error().startswith("NameError:")
number = 42
print read_number()

function read_none():
    return none_value
end
safe:
    print read_none()
end
print last_error().startswith("NameError:")
none_value = None
print type(read_none())
del(none_value)
safe:
    print read_none()
end
print last_error().startswith("NameError:")
