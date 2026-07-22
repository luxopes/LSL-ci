load config

function repeat():
    return repeated
end

repeated = config.lazy(repeat)
config = {"value": repeated}
