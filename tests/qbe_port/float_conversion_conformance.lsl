# lsl: internal-abi
load qbe_port.qbe_float as fp

function require(value, message):
    if not value:
        Error(TestFailure: message)
    end
end

for entry in [["1e300", 9094988921128908188],
              ["1e-6", 4517329193108106637],
              ["1e-12", 4427486594234968593],
              ["5e-324", 1], ["-0", -9223372036854775808],
              ["0x1.0000000000001p-1075", 1]]:
    parsed = fp.parse(entry[0])
    call require(__lsl_float_bits(parsed[0]) == entry[1], "exact binary64 rounding")
end
parsed = fp.parse("1.0000000596046448", True)
call require(__lsl_float_bits(parsed[0]) == 4607182419336888320,
             "binary32 conversion avoids double rounding")
parsed = fp.parse("0x1p-150", True)
call require(__lsl_float_bits(parsed[0]) == 0, "binary32 midpoint ties to even")
parsed = fp.parse("0x1.0000001p-150", True)
call require(__lsl_float_bits(parsed[0]) == 3936146074321813504,
             "binary32 subnormal above midpoint")

# A raw numeric limb is permitted to have exactly the bits of a live object
# pointer. It must never pass through generic Any numeric classification.
object = __lsl_float_from_bits(4607182418800017408)
word = __lsl_address(object)
limbs = [word]
call fp._mul(limbs, 1)
call require(__lsl_qbe_raw_int(limbs[0]) == (word & 1073741823),
             "pointer-shaped limb stays numeric")
if __lsl_qbe_lshr(word, 30) != 0:
    call require(__lsl_qbe_raw_int(limbs[1]) == __lsl_qbe_lshr(word, 30),
                 "pointer-shaped limb carry")
end
call require(__lsl_float_bits(object) == 4607182418800017408,
             "limb arithmetic leaves live object intact")
print "PASS exact floating conversion"
