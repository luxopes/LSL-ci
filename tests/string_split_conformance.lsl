# String.split conformance: byte-exact pieces for multi-byte UTF-8 and
# linear cost on large inputs. Regression for the 0.7.3 split, which probed
# bytes but sliced by code points, returning wrong pieces for any multi-byte
# String and walking code points from the start per piece.

load time

separator = chr(10)

pieces = ("žá" + separator + "bc" + separator + separator + "ď").split(separator)
print len(pieces)
print pieces[0]
print pieces[1]
print "[" + pieces[2] + "]"
print pieces[3]

print ("příliš žluťoučký kůň").split(" ")
print ("a,b,,c").split(",")
print ("no-separator-here").split(";")
print ("řetězec").split("ě")
print ("xx").split("x")

# Multi-byte separator.
print ("aŽŽb" + "ŽŽ" + "c").split("ŽŽ")

# Large input finishes in linear time; the quadratic version needed minutes
# for this size. The runner's comparison only sees the deterministic output.
line = "žluťoučký-line-payload-0123456789"
big = ""
index = 0
while index < 2000:
    big += line + separator
    index += 1
end
started = time.monotonic()
big_pieces = big.split(separator)
elapsed = time.monotonic() - started
print len(big_pieces), big_pieces[0] == line, big_pieces[1999] == line, big_pieces[2000]
print elapsed < 5.0
