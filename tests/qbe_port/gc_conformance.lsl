# lsl: internal-abi
load qbe_port.qbe_memory as mem
roots = {"text": "retained žluťoučký", "values": [7, 11, 19]}
address = mem.cstr("raw C pointer stays owned")
temporary = ""
# No explicit gc(): ephemeral strings exceed the old object-table bound.
for index in rang(1500000):
    temporary = "iteration:" + String(index)
end
check(temporary == "iteration:1499999", "last loop value")
check(roots["text"] == "retained žluťoučký", "dictionary string root")
check(roots["values"][2] == 19, "nested collection root")
check(mem.text(address) == "raw C pointer stays owned", "C allocation lifetime")
print "PASS automatic GC safepoints"
