# Errors in unused functions must not enable per-expression lookups elsewhere.
function unused_invalid():
    return len()
end
function valid(value):
    return value * 2 + 1
end
function invalid_callback():
    return len()
end
class Example:
    function init(self):
        self.value = 7
    end
    function broken(self):
        return len()
    end
end
print valid(3)
# Both main and a callback keep their own recorded errors.
safe:
    call nonexist()
end
print last_error().startswith("NameError:")
callback = invalid_callback
safe:
    call callback()
end
print last_error().startswith("TypeError:")
instance = Example()
safe:
    call instance.broken()
end
print last_error().startswith("TypeError:")
# Unreached errors retain their original short-circuit behavior.
safe:
    print False and nonexist()
    print True or nonexist()
end
