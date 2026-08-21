# Bitwise operators and based integer literals.

function mask(value, bits):
    return value & bits
end

function dynamic_shift(value, amount):
    return value << amount
end

print 12 & 10, 12 | 10, 12 ~ 10, ~12
print 12 << 3, 12 >> 2, -8 >> 2, -1 >> 1

# Precedence: shifts bind tighter than comparison but looser than +.
print 1 << 2 + 1
print 5 & 3 | 8
print 6 ~ 3 & 2
print 1 << 3 == 8
print not 0 & 1

# Int64 wrap, exactly like the rest of Int arithmetic.
print 1 << 62
print 1 << 63
print 1 << 64
print -1 >> 63
print -1 >> 64
print 9223372036854775807 >> 64

# Dynamic operands travel through the boxed path and stay exact.
values = [12, 10, -8, True, False]
print mask(values[0], values[1])
print values[0] & values[1], values[0] | values[1], values[0] ~ values[1]
print ~values[2], values[3] & 1, values[4] | 1
print dynamic_shift(values[0], 4), dynamic_shift(1, 200)

# Bool follows Python and counts as 0/1.
print True & True, True | False, True ~ True, ~True

# Augmented forms lower to the same operators.
flags = 0
flags |= 1
flags |= 4
flags <<= 2
print flags
flags >>= 1
print flags
flags &= 6
print flags
flags ~= 15
print flags

# Based literals.
print 0xFF, 0xff, 0X10, 0b1010, 0o755, 0O17
print 0x7FFFFFFFFFFFFFFF, 0xFFFFFFFFFFFFFFFF, 0x8000000000000000
print 0xdeadbeef, 0b0, 0x0

# Byte packing, the reason the operators exist.
packed = 0
for byte in [1, 2, 3, 4]:
    packed = (packed << 8) | byte
end
print packed
print (packed >> 24) & 0xFF, (packed >> 16) & 0xFF, (packed >> 8) & 0xFF, packed & 0xFF

# Constant folding must agree with the emitted instructions.
shift_amount = 3
print 40 >> 3, 40 >> shift_amount
print 40 << 3, 40 << shift_amount
print 0xF0 & 0x3C, 0xF0 | 0x3C, 0xF0 ~ 0x3C

# ByteArray element access keeps the static Int type.
buffer = __lsl_byte_zeros(4)
buffer[0] = 0xAB
print buffer[0] & 0x0F, buffer[0] >> 4
