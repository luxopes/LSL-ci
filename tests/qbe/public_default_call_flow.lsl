function identity(value):
    return value
end
function wrapper(value=2.5):
    return identity(value)
end
count = Int("1")
print identity(count), wrapper(), wrapper("ok")
