load config

options = {
    "service.port": config.option("Int", 8080, "Port")
}
config = {"service": {"port": "wrong"}}
