class ImportedParent:
    ctype Public

    function init(self, value):
        self.imported_value = value
    end

    function imported_method(self):
        return "imported:" + String(self.imported_value)
    end
end
