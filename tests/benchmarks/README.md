# Regrese automatického GC (0.8.4)

Oba zdroje jsou pure LSL a nevolají `gc()`. Přeložte stejné zdroje původním
compilerem 0.8.3 a kandidátem; běhy měřte sériově na stejném stroji alespoň
pětkrát, porovnejte mediány i checksumy. Neměřte souběžně s buildem/test suite.

`automatic_gc_snake.lsl` používá nezměněný renderer a pohyb původního
terminálového Snake 30×15 se třemi články. Had obíhá obdélník bez růstu;
každý snímek má stejnou délku. Součástí měření je `term.write`, nikoli čekání
na klávesnici nebo časování snímků. Předem nainstalujte `term` a pro oba
compilery ponechte stejný zdroj knihovny.

```text
lsl install term
lslc tests/benchmarks/automatic_gc_snake.lsl /tmp/snake-benchmark
/tmp/snake-benchmark 200 /tmp/snake-benchmark.log > /dev/null
lslc tests/benchmarks/automatic_gc_numeric.lsl /tmp/numeric-benchmark
/tmp/numeric-benchmark 100000000 /tmp/numeric-benchmark.log
```

Log obsahuje čas, checksum a u Snake také konečný RSS v KiB. Pro kontrolu
plateau zopakujte kandidáta s 10 000 snímky pod limitem 128 MiB virtuální
paměti. Původní verzi omezte na 200 snímků a 1 GiB; delší běh bez GC
nekontrolovaně rostl. Vlastní automatická paměťová regrese, nezávislá na
volitelném `term`, je `tests/automatic_gc_conformance.lsl`.
