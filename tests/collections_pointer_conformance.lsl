function require(condition, message):
    if not condition:
        Error(TestFailure: message)
    end
end
function identity(value):
    return value
end
callbacks = [identity]
owner = ["alive"]
address = __lsl_address(owner)
values = [address, 0, address]
unique = identity(set(values))
ordered = sorted(values)
distinct = dedup(values)
call gc()
call require(type(ordered[2]) == "Int" and ordered[2] == address, "sorted boxed pointer-like Int")
call require(type(distinct[0]) == "Int" and distinct[0] == address, "dedup boxed pointer-like Int")
call require(address in unique and 0 in unique and len(unique) == 2, "Set boxed pointer-like Int")
call require(type(unique.pop()) == "Int", "Set pop keeps Int tag")
call require(owner == ["alive"], "owner retained")
print "collection pointer collision conformance passed"
