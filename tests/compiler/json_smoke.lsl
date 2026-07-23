load json
from json load decode as parse_json

value = {"ok": True, "values": [1, None, "x"]}
text = json.encode(value)
parsed = parse_json(text)
emoji = parse_json("\"" + chr(92) + "ud83d" + chr(92) + "ude00\"")
print text
print parsed["ok"], parsed["values"][0], parsed["values"][1], parsed["values"][2]
print emoji, len(emoji), chr(10) in json.pretty(parsed)
