# Smyčka rang s krokem známým při překladu: jediné porovnání, stejné chování.
function rang_show(label, values):
    print label, values
end
rang_out = []
for rang_i in rang(5):
    rang_out.append(rang_i)
end
call rang_show("a", rang_out)
rang_out = []
for rang_i in rang(2, 9, 3):
    rang_out.append(rang_i)
end
call rang_show("b", rang_out)
rang_out = []
for rang_i in rang(9, 2, -3):
    rang_out.append(rang_i)
end
call rang_show("c", rang_out)
rang_out = []
for rang_i in rang(5, 5):
    rang_out.append(rang_i)
end
call rang_show("d", rang_out)
rang_out = []
for rang_i in rang(3, -3, - 2):
    rang_out.append(rang_i)
end
call rang_show("e", rang_out)
rang_out = []
for rang_i in rang(-3, 3, +2):
    rang_out.append(rang_i)
end
call rang_show("f", rang_out)
rang_step = -1
rang_out = []
for rang_i in rang(3, 0, rang_step):
    rang_out.append(rang_i)
end
call rang_show("g", rang_out)
rang_out = []
for rang_i in rang(0, 3, -1):
    rang_out.append(rang_i)
end
call rang_show("h", rang_out)
rang_out = []
for rang_i in rang(3, 0, 1):
    rang_out.append(rang_i)
end
call rang_show("i", rang_out)
for rang_i in rang(4):
    rang_i = 100
end
print "after", rang_i
for rang_i in rang(10, 0, -4):
    if rang_i == 6:
        break
    end
end
print "break", rang_i
for rang_j in rang(9223372036854775805, 9223372036854775807):
    rang_out.append(rang_j)
end
print "big", rang_out[-2:]
try:
    for rang_i in rang(0, 5, 0):
        print "never"
    end
else:
    print "zero", last_error()
end
try:
    for rang_i in rang(0, 5, 0x0):
        print "never"
    end
else:
    print "zerohex", last_error()
end
for rang_i in rang(10, 0, -0x2):
    rang_out.append(rang_i)
end
print "hexneg", rang_out[-5:]
