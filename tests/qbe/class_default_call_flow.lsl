# A method/default body skipped by parameter inference must not call a
# specialized numeric helper with a boxed Float or String behind that ABI.
function twice(value):
    return value + value
end
print twice(2)
class DefaultMethod:
    function run(self, value=1.5):
        return twice(value)
    end
    function static_run(value="z"):
        return twice(value)
    end
end
class DefaultConstructor:
    function init(self, value="x"):
        self.value = twice(value)
    end
end
print DefaultMethod().run()
print DefaultMethod.static_run()
print DefaultConstructor().value
