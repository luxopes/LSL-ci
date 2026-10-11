load frontend_scope_helper as helpers
from frontend_scope_helper load value as imported
from frontend_scope_helper load exported as imported_function
value = 100
function local(imported, value):
    imported_function = imported
    for step in rang(3):
        value += step
    end
    return value + imported_function
end
function imports():
    return imported_function(helpers.value)
end
function nested(value):
    temporary = [value + index for index in rang(3)]
    total = 0
    for item in temporary:
        for index in rang(2):
            total += item + index
        end
    end
    return total
end
print local(5, 10), imports(), imported, value, nested(2)
