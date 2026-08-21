load bigint

large = bigint.BigInt("123456789012345678901234567890")
negative = bigint.BigInt("-98765432109876543210")

print large.text()
print large.add(negative).text()
print large.subtract(negative).text()
print bigint.BigInt("12345678901234567890").multiply("9876543210").text()
print bigint.BigInt(-7).floor_divide(3).text(), bigint.BigInt(-7).modulo(3).text()
print bigint.BigInt(7).floor_divide(-3).text(), bigint.BigInt(7).modulo(-3).text()
print bigint.BigInt(2).power(200).text()
print bigint.BigInt("9223372036854775807").to_int()

alias = bigint.SuperInt("42")
print alias.add(8).text(), alias.compare("42"), alias.equals(42)

left = -40
while left <= 40:
    right = -40
    while right <= 40:
        big = bigint.BigInt(left)
        check(big.add(right).to_int() == left + right, "BigInt small add")
        check(big.subtract(right).to_int() == left - right, "BigInt small subtract")
        check(big.multiply(right).to_int() == left * right, "BigInt small multiply")
        if right != 0:
            check(big.floor_divide(right).to_int() == left // right, "BigInt small divide")
            check(big.modulo(right).to_int() == left % right, "BigInt small modulo")
        end
        right += 1
    end
    left += 1
end
print "small arithmetic passed"

try:
    print bigint.BigInt("9223372036854775808").to_int()
else:
    print last_error()
end
