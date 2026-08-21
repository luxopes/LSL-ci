# Math and BigInt

## Built-in square root

`sqrt(value)` is available without an import. It accepts `Int` or `Float`,
returns `Float`, and raises `ValueError` for a negative input.

```lsl
print sqrt(81)     # 9.0
print sqrt(2.25)   # 1.5
```

## math

```lsl
load math

print math.PI
print math.sin(math.PI / 2.0)
print math.sigmoid(0.0)
print math.mean([1, 2, 3, 4])
print math.pi(50)
```

The module exports:

- constants: `PI`, `TAU`, `E`, `LN2`, `SQRT2`;
- rounding and ranges: `floor`, `ceil`, `round`, `sign`, `clamp`, `lerp`;
- number theory: `gcd`, `lcm`, `factorial`, `factorial_big`;
- exponential functions: `exp`, `log`, `log2`, `log10`;
- trigonometry: `sin`, `cos`, `tan`, `degrees`, `radians`, `hypot`;
- activations: `sigmoid`, `tanh`, `relu`, `softplus`, `swish`;
- statistics: `mean`, `median`, `variance`, `standard_deviation`;
- comparison: `is_close(left, right, relative_tolerance, absolute_tolerance)`;
- decimal π generation: `pi(decimal_places)`.

`pi()` uses a spigot algorithm, so it is not limited by the Int64 range:

```lsl
print math.pi(20)  # 3.14159265358979323846
```

## bigint

`BigInt` stores a sign and an arbitrary number of decimal digits. Arithmetic
returns a new value and does not mutate its operands.

```lsl
load bigint

a = bigint.BigInt("123456789012345678901234567890")
b = bigint.BigInt(2).power(200)

print a.add(b).text()
print a.multiply("100000000000000000000").text()
```

Methods:

- `text()`, `is_zero()`;
- `compare(other)`, `equals(other)`;
- `negate()`, `absolute()`;
- `add(other)`, `subtract(other)`, `multiply(other)`;
- `floor_divide(other)`, `divide(other)`, `modulo(other)`;
- `power(non_negative_exponent)`;
- `to_int()` with an `OverflowError` if the value does not fit Int64.

Arguments may be `Int`, decimal `String`, `Bool`, or another `BigInt`.
`SuperInt` is an alias implemented as a `BigInt` subclass.
