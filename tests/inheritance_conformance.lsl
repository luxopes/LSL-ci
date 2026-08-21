load modules.inheritance_base as inherited

class Parent:
    function init(self, value):
        self.value = value
    end

    function describe(self):
        return "parent:" + String(self.value)
    end

    function doubled(self):
        return self.value * 2
    end
end

class Child(Parent):
    function init(self, value):
        origin.init(value + 1)
    end

    function describe(self):
        return origin.describe() + ":child"
    end
end

class Grandchild(Child):
    function describe(self):
        return origin.describe() + ":grandchild"
    end
end

class ImportedChild(inherited.ImportedParent):
    function imported_method(self):
        return origin.imported_method() + ":child"
    end
end

child = Child(20)
grandchild = Grandchild(40)
imported_child = ImportedChild(7)

print child.describe()
print child.doubled()
print grandchild.describe()
print grandchild.doubled()
print imported_child.imported_method()
