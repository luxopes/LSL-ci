load json

slash = chr(92)
invalid = [
    "",
    " ",
    "{",
    "[",
    "[1",
    "[1,]",
    "{\"a\"}",
    "{\"a\":}",
    "{\"a\":1,}",
    "\"unterminated",
    "\"" + slash,
    "\"" + slash + "x\"",
    "\"" + slash + "u12\"",
    "\"" + slash + "uZZZZ\"",
    "\"" + slash + "uD800\"",
    "\"" + slash + "uDC00\"",
    "01",
    "-",
    "1.",
    "1e",
    "true false",
    "nullx",
    "{1:2}",
    "[,]",
    "{\"a\":1,\"a\":2}",
    "9223372036854775808",
    "1e9999"
]
rejected = 0
for source in invalid:
    try:
        call json.decode(source)
    else:
        rejected += 1
    end
end

deep = "0"
for index in rang(129):
    deep = "[" + deep + "]"
end
try:
    call json.decode(deep)
else:
    rejected += 1
end

cycle = []
cycle.append(cycle)
try:
    call json.encode(cycle)
else:
    rejected += 1
end

seed = 123456789
roundtrips = 0
for index in rang(200):
    seed = seed * 1103515245 + 12345
    number = abs(seed % 100000)
    value = {"n": number, "text": "v" + String(number), "items": [number % 17, True, None]}
    decoded = json.decode(json.encode(value))
    if decoded != value:
        Error(TestFailure: "JSON round trip differs")
    end
    roundtrips += 1
end

special = json.decode("[-0.5,1e3,\"" + slash + "uD83D" + slash + "uDE00\"]")
print roundtrips, rejected, special[0], special[1], special[2], json.encode(chr(1)) == "\"" + slash + "u0001\""
