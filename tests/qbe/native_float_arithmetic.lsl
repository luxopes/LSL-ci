# Numeric expressions round at each binary64 operation, not as integer math
# or a fused multiply-add. Float boxing remains observable only at boundaries.
print (1.25 + 2.5) * 4.0 - 1.0
print (3.0 + True) * 2, 2 * (3.0 - False)
print (7 / 2) + 0.25, (7 + 2) / 4.0
print __lsl_float_bits(-0.0), __lsl_float_bits(0.0 * -1.0)
print __lsl_float_bits(-(-0.0)), __lsl_float_bits(-0.0 + -0.0)
print __lsl_float_bits((9007199254740993 + 1) + 0.0) == __lsl_float_bits(9007199254740994.0)
# The wrapped Int converts to exact IEEE -2^63; legacy decimal parsing is
# independently checked by native_float_literals rather than this oracle.
print __lsl_float_bits((9223372036854775807 + 1) + 0.0) == -4332462841530417152

tiny = __lsl_float_from_bits(1)
print __lsl_float_bits(tiny + tiny), __lsl_float_bits(tiny * 0.5)
print __lsl_float_bits(-tiny * 0.5)
huge = __lsl_float_from_bits(9218868437227405311)
print __lsl_float_bits(huge * 2.0) == 9218868437227405312
print __lsl_float_bits(1.0 / 0.0) == 9218868437227405312
print __lsl_float_bits(-1.0 / 0.0) == -4503599627370496
print __lsl_float_bits(1.0 / -0.0) == -4503599627370496
nan_value = 0.0 / 0.0
nan_bits = __lsl_float_bits(nan_value)
print (nan_bits & 9218868437227405312) == 9218868437227405312, (nan_bits & 4503599627370495) != 0
payload = __lsl_float_from_bits(9221120237041090602)
print __lsl_float_bits(payload + 1.0) == 9221120237041090602
signaling = __lsl_float_from_bits(9218868437227405313)
print __lsl_float_bits(signaling * 1.0) == 9221120237041090561

# An optimizer must not reassociate these operations or contract them to FMA.
a = 1.0000000000000002
b = 0.9999999999999998
print __lsl_float_bits(a * b - 1.0) == 0
large = 1e16
print (large + -large) + 1.0, large + (-large + 1.0)
function local_math(value):
    current = (value + 0.5) * 1.25
    if current > 0.0:
        current = current / 2.0 - 0.25
    end
    return current
end
print local_math(3.5), type(local_math(3.5))
# Scalar is/is not compare values, including IEEE Float equality. Equal
# values in separate Float boxes compare True; collections retain identity.
identity_value = 1.25
print identity_value is +identity_value, identity_value is (identity_value + 0.0)
print 1.0 is 1.0
