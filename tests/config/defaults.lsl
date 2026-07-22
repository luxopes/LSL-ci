load config

options = {
    "service.enable": config.option("Bool", True, "Enable service")
    "service.port": config.option("Int", 9000, "Service port")
    "labels": config.option("List", ["default"], "Labels")
}

config = {}
