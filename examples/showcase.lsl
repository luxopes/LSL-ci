# Hlavní vlastnosti Lux Simple Lang
name = "Ada"
age = 1 + 10
print "ahoj", name, "je ti", age
printl "ahoj {name}, je ti {1 + 10}"

total = 0
for i in rang(1, 5):
    total += i
end

safe:
    Error(ValueError: "tato chyba se ignoruje")
end

try:
    Error(NetworkError: "ukázková chyba")
else:
    print "try fallback funguje"
end

function motor(power):
    return power * 2
end
print "motor:", motor(total)

class Auto(True):
    ctype Public
    function init(self, brand):
        self.brand = brand
    end
    function info(self):
        return self.brand
    end
end

car = Auto("Lux")
printl "auto: {car.info()}"

items = ["A", 1, True]
items.append("konec")
fixed = ![1, 2, 3]
fixed[1] = 8
print items, fixed, type(fixed), len(items)

load lux
print "LSL", lux.version
