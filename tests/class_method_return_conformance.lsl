# self must have the same instance type during return inference and emission,
# including when escaping functions disables call-site specialization.
class Result(True):
    function init(self, value):
        self.value = value
    end
    function identity(self):
        return self
    end
    function get_value(self):
        return self.value
    end
end
class Factory(True):
    function make(self):
        return Result(42)
    end
    function via_method(self):
        return self.make()
    end
end
function escaped(value):
    return value
end
callbacks = [escaped]
factory = Factory()
result = factory.via_method()
alias = result.identity()
print alias.get_value()
