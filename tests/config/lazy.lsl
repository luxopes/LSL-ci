load config

function delayed_port():
    return 8123
end

function delayed_labels():
    return ["lazy", "resolved"]
end

config = {
    "service": {
        "port": config.lazy(delayed_port)
        "labels": config.lazy(delayed_labels)
    }
}
