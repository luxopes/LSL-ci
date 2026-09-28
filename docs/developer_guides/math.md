# Knihovna math

`load math`

Matematické konstanty a numerické funkce v čistém LSL.

## Zaokrouhlování a znaménka

```lsl
math.floor(value)   math.ceil(value)   math.round(value)
math.sign(value)    math.clamp(value, lower, upper)
```

## Interpolace a úhly

```lsl
math.lerp(start, stop, amount)
math.degrees(radians_value)   math.radians(degrees_value)
```

## Dělitelnost a faktoriál

```lsl
math.gcd(left, right)   math.lcm(left, right)
math.factorial(value)        # Int
math.factorial_big(value)    # bigint.BigInt pro velká n
```

## Logaritmy a mocniny

```lsl
math.exp(value)   math.log(value)   math.log2(value)   math.log10(value)
```

## Goniometrie a aktivace (neuronové sítě)

```lsl
math.sin(value)   math.cos(value)   math.tan(value)
math.sigmoid(value)   math.tanh(value)
math.relu(value)   math.softplus(value)   math.swish(value)
math.hypot(x, y)
```

## Porovnávání a statistika

```lsl
math.is_close(left, right, relative_tolerance, absolute_tolerance)
math.mean(values)                 math.variance(values)
math.standard_deviation(values)   math.median(values)
```

## Příklad

```lsl
load math

print math.gcd(48, 36)            # 12
print math.clamp(7.5, 0, 5)       # 5.0
print math.sigmoid(0)             # 0.5
print math.mean([1, 2, 3, 4])     # 2.5
print math.pi(5)                  # 3.14159
```

## Chyby

- `MathError` — definiční obor (logaritmus záporného čísla apod.),
  neplatné argumenty.

## Související stránky

- `lsl man bigint` — přesná celočíselná aritmetika
- `lsl man random` — rozdělení pravděpodobnosti
- `lsl man tensor` — tenzory a maticové operace
