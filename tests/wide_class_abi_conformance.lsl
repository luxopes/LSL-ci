class Wide(True):
    function init(self, a, b, c, d, e, f, g, h):
        self.total = a + b + c + d + e + f + g + h
    end

    function add(self, a, b, c, d, e, f, g):
        return self.total + a + b + c + d + e + f + g
    end
end

wide = Wide(1, 2, 3, 4, 5, 6, 7, 8)
print wide.total, wide.add(1, 2, 3, 4, 5, 6, 7)
