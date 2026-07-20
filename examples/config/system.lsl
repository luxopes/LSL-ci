# Root konfigurace importuje moduly a přepisuje jejich defaults.
load config

imports = ["base.lsl"]

config = {
    "system": {
        "name": "ai-workstation"
    }
    "services": {
        "ai": {
            "enable": True
            "model": config.mkForce("local/model-q4")
            "port": 11434
        }
    }
    "environment": {
        "packages": ["git", "clang"]
    }
}

assertions = [
    [True, "AI service policy rejected this machine"]
]
