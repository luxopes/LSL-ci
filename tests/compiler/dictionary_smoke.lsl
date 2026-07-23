data = {"name": "LSL", "value": 40}
data["value"] = data["value"] + 2
print data["name"], data["value"], len(data)
print data.get("name")
