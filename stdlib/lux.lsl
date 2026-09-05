# Core Lux Simple Lang module: version metadata and small helpers.

version = "0.7.7"
name = "Lux Simple Lang"

function identity(value):
    return value
end

function clamp(value, low, high):
    if value < low:
        return low
    elif value > high:
        return high
    end
    return value
end

function is_empty(collection):
    return len(collection) == 0
end
