load modules.sample as fixture

name = "Ada"
age = 36
text = l"Jmenuji se {name}, je mi {age}."
print text
print l"alias={fixture.multiply(14)} power={2 ^ 3 ^ 2}"
print l"literal braces: {{name}} dictionary={String({\"x\": 7})}"
printl "printl remains compatible: {fixture.name}"
