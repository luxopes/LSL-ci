load config

options = {}
config = {"generated": {}, "values": [0]}
for index in rang(100):
    name = "generated.k" + String(index)
    options[name] = config.option("Int", index, "generated option")
    if index % 4 == 0:
        config["generated"]["k" + String(index)] = config.mkForce(index * 10)
    elif index % 2 == 0:
        config["generated"]["k" + String(index)] = index * 2
    end
    config["values"].append(index)
end
assertions = [[len(config["values"]) == 101, "generated values length"]]
