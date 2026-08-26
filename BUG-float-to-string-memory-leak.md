# Chyba: memory leak v převodu float→string (String(float))

**Stav: opraveno ve vydání 0.6.5 (2026-08-26).** Stejných 60 000 převodů
doběhne s `bad 0` a maximálním RSS přibližně 31 MiB místo 5,1 GiB.
Korekční a zkracovací smyčka formátovače používá stackový kandidát a raw
IEEE-754 porovnání; omezovaná post-format kolekce se aktivuje až po 256
formátováních a růstu registru o 4 096 adres. Veřejný `Float(String)` současně
mutuje jediný privátní akumulátor místo dvou nových Float boxů na číslici.

Nález 2026-08-21. Hlášení pro agenta pracujícího na 0.7. Neopravoval jsem sám —
níže je vše, co jsem naměřil, včetně deterministické reprodukce.

## Symptom

Test `fl.lsl` (tři `String(float)` v cyklu) nafoukne paměť procesu na ~5 GB
a jádro ho zabije OOM killerem:

```
Aug 21 19:04:43 jupiter kernel: Out of memory: Killed process (fl)
  total-vm:8855100kB anon-rss:5069212kB UID:1000
```

Proces měl název `fl`, protože to je jméno zkompilované binárky z `fl.lsl`.

## Reprodukce

```lsl
bad = 0
round = 0
while round < 20000:
    a = String(-4.5)
    b = String(0.5)
    c = String(9007199254740992.0)
    if a != "-4.5":
        bad += 1
        print "a", a
    end
    if b != "0.5":
        bad += 1
        print "b", b
    end
    if c != "9007199254740992.0":
        bad += 1
        print "c", c
    end
    round += 1
end
print "bad", bad
```

```sh
./compiler/pure/lslc-direct fl.lsl /tmp/fl
/usr/bin/time -v /tmp/fl     # sleduj "Maximum resident set size"
```

## Naměřeno

- 20000 iterací × 3 `String()` = **60000 konverzí** → **~5,1 GB RSS**.
- To je **~85 kB na jednu `String(float)`** — výsledek má přitom řádově desítky
  bajtů. Režie je o 3–4 řády vyšší, než by odpovídalo jen „nevolané gc()".
- ~85 kB ≈ **~21 stránek po 4 kB** na jednu konverzi. To odpovídá tomu, že
  každá z mnoha dílčích alokací v jedné konverzi si bere čerstvou stránku
  z brk() a nic se nevrací do free-listu.

## Kde to je

- `compiler/pure/native_runtime.lsl` — `emit_float_to_string` (ř. 378) /
  `runtime_float_to_string` (ř. 406). Volá `runtime_int_to_string` (ř. 65),
  `runtime_chr` (ř. 159), `runtime_string_concat`, `runtime_string_clone`
  a frakční buffer přes `runtime_alloc` (`runtime_fraction_string`).
- `compiler/pure/dynamic_stdlib.lsl` — `__lsl_format_float` (ř. 505), druhá
  (LSL-level) cesta pro `print`/formátování.
- `compiler/pure/heap_runtime.lsl` — `runtime_alloc` (ř. 16, free-list + brk),
  `runtime_string_concat` (ř. 348), `runtime_string_clone` (ř. 470),
  `runtime_gc` (ř. 940).

## Hypotéza

`runtime_float_to_string` dělá na každé volání řadu dočasných alokací
(int→string, chr, concat, frakční buffer, clone). Ty se zřejmě **nevracejí do
free-listu** (nebo `runtime_string_concat` neuvolňuje své vstupy), takže každá
alokace prodlouží brk() o celou stránku. gc() se volá jen explicitně (viz
BUG-tisk-cisel.md), takže v cyklu bez gc() paměť roste neomezeně a skončí OOM.

## Úkol

1. Ověřit, že `runtime_string_concat` / `runtime_chr` / `runtime_int_to_string`
   / `runtime_string_clone` vracejí nepotřebné vstupní stringy do free-listu
   (v `runtime_alloc` free-list existuje — otázka je, jestli ho helpery
   skutečně plní a jestli se shodují velikostní třídy).
2. Najít, proč jedna `String(float)` stojí ~85 kB místo desítek bajtů.
3. Cíl: RSS při běhu `fl.lsl` zůstane plochý po celých 20000 iterací, bez
   nutnosti ručního `gc()`.

## Ověření opravy

```sh
./compiler/pure/lslc-direct fl.lsl /tmp/fl
/usr/bin/time -v /tmp/fl   # "Maximum resident set size" má být řádově desítky MB, ne GB
```
