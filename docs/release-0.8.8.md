# Release LSL 0.8.8

Opravné vydání. Compiler i host runtime zůstávají pure LSL.

## Oprava překladu: typy proměnných do fixpointu

Compiler odvozuje statické typy lokálních proměnných jedním průchodem
v pořadí zdroje. Když proměnná dostala dynamickou hodnotu až později
v kódu, dřívější výrazy s ní zůstaly přeložené jako celočíselné:

```lsl
while zbytek > 1:
    p = tabulka[zbytek]        # Int z IntArray
    delitele.append(p)
    while zbytek % p == 0:
        zbytek = zbytek // p   # přeloženo jako Int // Int ...
    end
end
for p in delitele:             # ... ale tady se p stane dynamickým
    obsazeno[p] = 1
end
```

Při emisi se `zbytek // p` vyhodnotilo dynamicky (boxovaný výsledek), ale
uložilo do surového celočíselného slotu `zbytek` — proměnná pak obsahovala
ukazatel: nesmyslné hodnoty, `IndexError` nebo zacyklení. Od 0.8.8 se
odvození typů opakuje, dokud se žádný typ nemění; rozšíření jde vždy jen
směrem k dynamické hodnotě, takže se ustálí během několika průchodů.
Programy, které chybu nespouštěly, se překládají stejně jako dosud.

Regrese: `tests/type_widening_conformance.lsl` (modulová i funkční varianta;
compiler 0.8.7 na ní visí).

## Diagnostika comprehension

`[0, for x in rang(3)]` dřív hlásilo `E1104: expected comma in List literal`,
tedy přesně opak skutečné příčiny. Nově `E1119: unexpected comma before for
in a List comprehension` s nápovědou `write [value for item in iterable]`.

## Manuál

Kapitola 11 nově začíná volbou kolekce: `IntArray` místo `List` pro velké
číselné tabulky (síto do 1 000 000: 2,5 s → 0,03 s).

## Přechod

`lsl update` (u systémové instalace `sudo /usr/local/bin/lsl update --system`).
Programy zasažené opravou stačí znovu spustit; samostatné binárky z
`lsl compile` znovu přeložte.
