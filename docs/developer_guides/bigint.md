# Knihovna bigint

`load bigint`

Celočíselná aritmetika s libovolnou přesností pro hodnoty mimo Int64.
Operace s kvadratickou složitostí mají pracovní limit, který zabrání
přetížení procesoru.

## Třída BigInt

```lsl
bigint.BigInt(value)
bigint.parse(value)      # totéž jako BigInt(value)
```

`value` je Int, Float (celá část), String s desítkovými číslicemi,
`Bool` nebo jiný `BigInt`/`SuperInt`.

### Metody

```lsl
n.text()            # String s desítkovým zápisem
n.is_zero()         # Bool
n.compare(other)    # -1 / 0 / 1
n.equals(other)     # Bool
n.negate()          # opačná hodnota
n.absolute()        # absolutní hodnota
n.add(other)        n.subtract(other)
n.multiply(other)
n.floor_divide(other)   n.divide(other)   n.modulo(other)
n.power(exponent)
n.to_int()          # Int, pokud se vejde
```

`other` může být libovolný podporovaný typ jako u konstruktoru.
Výsledky aritmetiky jsou nové objekty `BigInt`.

## Třída SuperInt

```lsl
bigint.SuperInt(value)
```

Dědí z `BigInt` a zapamatovává si, zda vznikl násobením nebo dělením —
pro typové systémy, které chtějí zachovat informaci o operaci.

## Příklad

```lsl
load bigint

large = bigint.BigInt("12345678901234567890")
print large.multiply("9876543210").text()
print bigint.BigInt(2).power(200).text()
```

## Chyby

- `BigIntError` — neplatný vstup nebo překročený pracovní limit operace.

## Související stránky

- `lsl man math` — `math.factorial_big`
- `lsl man random` — `randrange` s velkými rozsahy
