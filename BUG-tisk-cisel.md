# Chyba: výpis čísel se občas rozpadne (nález 2026-08-21)

**Stav: opraveno ve vydání 0.6.5 (2026-08-26).** Minimální třímodulová
reprodukce i původní smíšené rozložení nyní opakovaně procházejí v běžném
prostředí. `String(Float)` ověřuje kandidáty bez dočasných heapových objektů a
`Float(String)` akumuluje do jediného privátního boxu, takže už nevzniká
extrémní layoutově citlivý alokační režim popsaný níže. Trvalý test
`tests/float_format_allocation_conformance.lsl` hlídá text, IEEE round-trip i
růst registru objektů.

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

## Doplněk vyšetřování (Fable, později 2026-08-21)

Postoupil jsem v diagnóze, ale **kořenovou příčinu jsem nepřipnul** (v prostředí
není gdb/valgrind; vlastní ptrace watchpoint buď mířil na špatný cíl, nebo ho
krokování přes breakpoint utlumilo).

Ověřená fakta (deterministicky, ne odhadem):

- **Minimální repro**: 3 moduly `float_format_conformance` + `del_conformance`
  + `boxed_collection_conformance`, `setarch -R` → padá 12/12. Delta-debug na
  aktuálním compileru.
- **Spouštěč je `Float(text)`** (String→Float přes LSL `__lsl_parse_float`).
  V `show()` je `text = String(value); reparsed = Float(text)`. Když se řádek
  `reparsed = Float(text)` nahradí `reparsed = value`, koruptace zmizí (0/15).
- `__lsl_format_float` vrací **správný** řetězec (ověřeno re-parsem výsledku
  uvnitř funkce — vždy sedí na `target_bits`).
- Během `__lsl_parse_float` se **`text` nemění** (kontrolní součet bajtů na
  vstupu i výstupu shodný). Parser tedy ze správného vstupu spočítá layout-
  závisle špatné bity → koruptuje se **mezilehlá heap Float krabice** v
  aritmetice `value = value*10.0 + Float(digit)` (desítky alokací na jedno
  volání).
- **Není to gc ani vlákna** (potvrzeno už v původním reportu) a **není to ani
  registrová alokace** (s `register_locals = {}` padá dál 12/12) **ani peephole
  `cmp→test`** (s vypnutým padá dál).
- Bez `free()`/gc je alokátor čistý bump přes `brk` → nemůže vracet překrývající
  se bloky. Přepis tedy musí být **zápis mimo meze** ze sousední alokace, nebo
  divoký pointer. Audit všech runtime primitiv (`runtime_alloc` alloc_new/reuse,
  `runtime_register_object`, `runtime_grow_object_table`, `runtime_grow_intern_table`,
  `runtime_string_concat`, `runtime_int_to_string`, `runtime_fraction_string`,
  `runtime_float_new`, `emit_float_binary`, `runtime_string_clone`,
  `runtime_string_to_float`) **neodhalil off-by-one** — všechny mají správné meze.
- Souvislost s druhým reportem (`BUG-float-to-string-memory-leak.md`):
  `String(float)` alokuje **stovky–tisíce** dočasných objektů na jednu konverzi
  (round-trip smyčka až 300 iterací). Bez gc registr objektů roste do milionů
  záznamů. Tenhle extrémní alokační režim je právě to, co koruptaci spouští.
- Minimální 3-modulový případ se stal **deterministickým** až od commitu
  `083b20b` (globály do state bloku, posun intern tabulky o 112 B). Plný
  27-modulový probe ale padá i před ním (ASLR-závisle), takže je to
  **pre-existující** memory-safety chyba, ne regrese `083b20b`.

Doporučený další krok: nainstalovat `gdb` (`apt install gdb`, potřebuje síť) a
dát hardwarový watchpoint na `reparsed` box (breakpoint na návratu
`__lsl_parse_float`, pak `PTRACE_CONT` bez krokování) — to viníka připne
jednoznačně. Alternativně red-zone kolem každé alokace v `runtime_alloc` a
kontrola při každé další alokaci.

Tato doporučení patří k původnímu vyšetřování; pro ověření opravy 0.6.5 už
nejsou potřeba.
