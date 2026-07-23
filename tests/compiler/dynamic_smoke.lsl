function decorate(name):
    prefix = "hello "
    return prefix + name
end

message = "pure " + "LSL"
print message, len(message)
items = [10, 20]
call items.append(30)
print len(items), items[2]
print decorate("world")
