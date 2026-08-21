# Chyba: výpis čísel se občas rozpadne (nález 2026-08-21)

Hlášení pro agenta, který pracuje na 0.7. Sám jsem to neopravoval, protože se
mi pod rukama měnil strom — níže je všechno, co jsem naměřil, včetně
deterministické reprodukce.

## Co se děje

V agregovaném konformančním korpusu se čas od času vytiskne špatné číslo.
Hodnoty samotné jsou v pořádku (`values[2] == 9000000000` projde), rozbité je
až to, co se objeví na výstupu:

```
9223372036854775807  ->  3136854775807
9000000000           ->  48037600   (jindy 200)
-3.5                 ->  -3.1000000300
0.5                  ->  0.190281100000300
0.025                ->  0.024999999999999999
```

Poslední řádek je zajímavý tím, že to není náhodný shluk číslic, ale plná
decimální expanze sousedního doublu.

## Reprodukce

Vezmi z `tests/full_conformance.lsl` úsek od `thread_conformance` po
`tagged_argument_conformance` (27 modulů), ulož jako `tests/_probe.lsl`,
očekávaný výstup je konkatenace odpovídajících `.out` souborů:

```sh
./compiler/pure/lslc-direct tests/_probe.lsl /tmp/probe
setarch -R /tmp/probe | diff /tmp/expected.out -   # padá 20/20
/tmp/probe          | diff /tmp/expected.out -     # padá 7/60
```

**`setarch -R` (vypnuté ASLR) dělá pád deterministickým** — pokaždé selže
stejný řádek. Je to tedy plně laditelné pod gdb, včetně hardwarových
watchpointů na konkrétní adresu, protože ta zůstává mezi běhy stejná.

Chyba závisí na rozložení paměti: se zapnutým ASLR se mění jak četnost, tak to,
které číslo se rozbije.

Nejmenší sada modulů, kterou jsem našel delta-debuggingem:
`thread_conformance`, `register_locals_conformance`, `float_power_conformance`
(se zapnutým ASLR ~2/30). Celý 27modulový úsek je ale pro ladění lepší, protože
padá výrazně častěji.

Měřeno na commitu `6521710`.

## Co je vyloučené

Obojí jsem ověřoval tak, že jsem měnil vstup a počítal pády, ne odhadem:

| změna | výsledek |
|---|---|
| `thread_spawn` nahrazen přímým voláním funkcí | 11/60 — **vlákna to nejsou** |
| odstraněné jediné `call gc()` v korpusu | 3/60 — **GC to není** |

Druhý řádek je podstatný: `gc()` se volá jen explicitně (v korpusu jediné místo,
`thread_conformance`), takže bez něj se nic neuvolňuje. Není to tedy
use-after-free ani chyba sweepu — blok se nikdy neuvolní a přesto se výstup
rozpadne.

Zbývá tedy zápis mimo hranice bufferu nebo čtení z místa, kde už data nejsou —
někde v cestě, která čísla převádí na text.

## Kde bych začal hledat

- `runtime_print_int` v `native_runtime.lsl` staví číslice sestupně od `rbp`
  (`lea rsi, [rbp+0]`) do vlastního rámce. Rámec má 48 bytů, `Int` v desítkové
  soustavě potřebuje až 20 znaků včetně znaménka — vejde se to, ale je to
  jediné místo, kde se scratch buffer a lokální sloty dělí o stejný rámec, a
  stačí, aby některá cesta rámec zmenšila nebo přidala slot.
- `runtime_int_to_string` dělá totéž s rámcem 80 a sloty na `-56/-64/-72`.
- `runtime_fraction_string` alokuje 23 bytů (16 hlavička + 6 číslic + NUL) a
  zapisuje od `payload+21` dolů.

Jedna věc navíc, kterou jsem nedokázal potvrdit ani vyvrátit: nová alokace hot
locals bere `r13/r14/r15`, přičemž runtime si v `r15` drží bázi zásobníku
(podle ní `gc()` pozná hlavní vlákno a končí jí konzervativní sken) a v `r13`
čekající chybu. Commit říká, že se registry kolem funkce ukládají a obnovují,
takže to nejspíš v pořádku je — ale je to přesně ten druh překryvu, kde se
vyplatí podívat se dvakrát.
