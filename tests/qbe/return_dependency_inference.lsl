# A forward chain updates inherited method aliases after earlier evaluations.
class Ancestor:
    function scalar(self):
        return forward_value()
    end
    function parity(self, count):
        if count == 0:
            return True
        end
        return self.parity(count - 1)
    end
end
class Descendant(Ancestor):
    function value(self):
        return self.scalar()
    end
end
class Factory:
    function make(self):
        return Descendant()
    end
end
function forward_value():
    return later_value()
end
function later_value():
    return final_value()
end
function final_value():
    return 17
end
function nested_values():
    return [[forward_value() + i + j for j in rang(2)] for i in rang(2)]
end
factory = Factory()
print factory.make().value(), factory.make().scalar()
print factory.make().parity(4)
print nested_values()
