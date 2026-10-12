# split s jednobajtovým literálem: String přímo nativně, ostatní typy beze změny chování.
split_items = ["a=b", "=x=", "", "noeq", "č=ř=ž", "a==b"]
for split_t in split_items:
    print split_t.split("="), split_t.split(" "), split_t.split(",")
end
split_any = split_items[0]
print split_any.split("=")
split_lines = "1 2\n3 4\n".split("\n")
print split_lines, split_lines[0].split(" ")
try:
    split_x = 5
    print split_x.split("=")
else:
    print "chyba:", last_error()
end
try:
    split_y = [1, 2]
    print split_y.split("=")
else:
    print "chyba:", last_error()
end
print "a=b".split("="), "abc".split("bc"), "a b".split()
