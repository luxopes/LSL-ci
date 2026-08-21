# LSL 0.6.1

Údržbové vydání nad [0.6](release-0.6.md). Doplňuje práci s jednotlivými bity,
kterou jazyk dosud neuměl vyjádřit jinak než násobením a dělením mocninami dvou.

## Jazyk

- `a & b`, `a | b`, `a ~ b` a `~a` jsou bitový AND, OR, XOR a NOT.
- `a << b` a `a >> b` jsou posuny; `>>` je aritmetický, takže odpovídá
  `a // 2^b` i pro záporná čísla.
- XOR má znak `~`, protože `^` je v LSL mocnina. Unární `~` je NOT. Stejné
  rozdělení má Lua, ze které LSL přebírá i `^` a `//`.
- Složená přiřazení `&=`, `|=`, `~=`, `<<=` a `>>=`.
- Literály s prefixem `0x`, `0o` a `0b`, například `0xFF`, `0o755`, `0b1010`.
  Redukují se modulo `2^64` stejně jako desítkové, takže
  `0xFFFFFFFFFFFFFFFF` je `-1`.

## Sémantika

- Priorita je jako v Pythonu: `<<` a `>>` jsou volnější než `+`, ale těsnější
  než porovnání. `x & 1 == 1` proto znamená `(x & 1) == 1`.
- Operandy musí být `Int` nebo `Bool`; `Bool` se počítá jako `0`/`1`
  a výsledek je vždy `Int`.
- Statický `Float` nebo kolekce jsou chyba překladu se span diagnostikou.
  Dynamická hodnota jiného typu vyvolá `TypeError` za běhu — bity živého
  pointeru se nikdy nečtou jako číslo.
- Posun o záporný počet bitů je `ValueError` s původní cestou a řádkem.
- Posun o 64 a více bitů je definovaný: `<<` dává `0`, `>>` dává `0` pro
  nezáporné a `-1` pro záporné číslo.

## Compiler

- Konstantní posun se složí už při překladu, jinak se emituje jako immediate
  `shl`/`sar`. Proměnný posun používá `CL` a rozsah kontroluje explicitně,
  místo aby spoléhal na maskování počtu procesorem.
- `&`, `|` a `~` používají stejnou leaf-register cestu jako `+` a `*`, takže
  se u literálu ani proměnné nespill na stack.
- `lsl-install` kopíruje i moduly `math` a `bigint`.
- Compiler zůstává bitově reprodukovatelný ve fixed pointu a všechny tracked
  ELF mají jediný `R E` `PT_LOAD` bez `INTERP` a `DYNAMIC`.

## Ověření

```text
./tests/lsl-test
./tests/lsl-test fixed-point
```
