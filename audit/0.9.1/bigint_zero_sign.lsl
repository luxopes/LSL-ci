load bigint
x = bigint.BigInt({"sign": 0, "digits": "5"})
print x.text(), x.is_zero(), x.absolute().text()
