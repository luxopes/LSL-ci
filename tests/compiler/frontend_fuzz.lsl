# Deterministic valid-source lexer/parser fuzz smoke. Invalid syntax diagnostics
# are covered separately by the subprocess negative corpus because fail() exits.

load parser

seed = 2463534242
parsed = 0
for iteration in rang(1000):
    seed = seed * 1103515245 + 12345
    number = abs(seed % 1000000)
    source = "# generated " + String(iteration) + chr(10)
    source += "value = " + String(number) + chr(10)
    source += "ratio = " + String(number % 97) + ".25e+2" + chr(10)
    source += "text = \"žluťoučký 😀 " + String(number % 31) + "\"" + chr(10)
    source += "items = [value, ratio, text, True, None]" + chr(10)
    source += "mapping = {\"value\": value, \"items\": items}" + chr(10)
    source += "if value >= 0 and len(items) == 5:" + chr(10)
    source += "    mapping[\"ok\"] = True" + chr(10)
    source += "else:" + chr(10)
    source += "    Error(TestError: \"unreachable\")" + chr(10)
    source += "end" + chr(10)
    program = parser.parse("<fuzz>", source)
    if len(program) != 6:
        Error(TestFailure: "generated parser AST length differs")
    end
    parsed += 1
end
print parsed
