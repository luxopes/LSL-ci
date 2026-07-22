maximum = 9223372036854775807
minimum = -9223372036854775808
print maximum + 1, minimum - 1, maximum * 2, -minimum, abs(minimum)
print 2 ** 63, 3 ** 40
values = [maximum, minimum, 2, 63]
print values[0] + 1, values[1] - 1, values[0] * values[2], values[2] ** values[3]
print Int("9223372036854775807"), Int("-9223372036854775808")
print Int("9223372036854775808"), Int("-9223372036854775809")
print minimum // -1, minimum % -1
