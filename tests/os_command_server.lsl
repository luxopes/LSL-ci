if arg(1) == "fail":
    Error(OSServerError: "failed")
end

joined = ""
index = 1
while index < arg_count():
    if index > 1:
        joined += "|"
    end
    joined += arg(index)
    index += 1
end
print arg_count(), joined
