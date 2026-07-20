factor = 3
name = "module-ok"

class Tool(True):
    ctype Public
    function init(self, value):
        self.value = value
    end
    function double(self):
        return self.value * 2
    end
end

class Hidden(True):
    ctype Private
    value = "private"
end

function _scale(value):
    return value * factor
end

function multiply(value):
    return _scale(value)
end
