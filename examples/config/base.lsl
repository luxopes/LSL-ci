# Sdílený deklarativní modul.
load config

options = {
    "system.name": config.option("String", "lux-machine", "Stable machine name")
    "services.ai.enable": config.option("Bool", False, "Enable local AI service")
    "services.ai.model": config.option("String", "default", "Model identifier")
    "services.ai.port": config.option("Int", 8080, "HTTP listen port")
    "environment.packages": config.option("List", [], "Requested packages")
}

config = {
    "system": {
        "name": config.mkDefault("lux-machine")
    }
    "services": {
        "ai": {
            "enable": config.mkDefault(False)
            "model": config.mkDefault("tiny-model")
            "port": config.mkDefault(8080)
        }
    }
    "environment": {
        "packages": ["curl", "ca-certificates"]
    }
}
