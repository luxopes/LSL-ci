# Runtime LSL

Runtime jazyka LSL (model objektů, alokátor a GC, řetězce, kolekce, převody
čísel, chyby, I/O, procesy, vlákna) je napsaný v LSL, stejně jako má Go
runtime v Go. Překládá ho `compiler/pure/lslc_runtime.lsl` do LuxIR a LuxIR
ho přeloží pro každý cíl. Pro každou platformu se liší jen dvě tenké vrstvy:

| Vrstva | Soubor | Obsah |
|---|---|---|
| architektura | `arch/<os>_<cpu>.S` | instrukce CPU, které LuxIR nemá: `syscall`, odmocnina (`lsl_arch_sqrt`), nastavení thread pointeru, vstup vlákna, návrat ze signálu |
| operační systém | `os_<os>.lsl` | soubory, procesy, paměť, čas přes rozhraní systému (Linux syscalls, Win32) |

Všechno ostatní je společné. Obecný kód (buffery, `readfile`, procesy…)
volá funkce vrstvy OS (`os_linux.read(…)`); ta na Linuxu používá jen
systémová volání společná x86_64, arm64 i rv64 (`openat`, `pipe2`, `dup3`,
`clone`, `mkdirat`, `unlinkat`, `newfstatat`, `ppoll`) s čísly z modulu
platformy cíle (`load _platform as platform`, `platform.SYS_OPENAT`).
Velikosti a posuny kernelových struktur patří taky do modulu platformy.

## Windows

`os_windows.lsl` má stejné rozhraní nad Win32 (kernel32, WaitOnAddress):
deskriptor je HANDLE (0, 1, 2 = standardní proudy), chyby jsou záporné errno
s hodnotami Linuxu, cesty a text UTF-8 (funkce `…W` dostávají UTF-16).
Rozdíly, které řeší vrstva OS:

- argv a prostředí sestaví `process_arguments` z `GetCommandLineW`
  a `GetEnvironmentStringsW` do stejného bloku, jaký Linux předá na zásobníku
  (stav +120); jména proměnných prostředí nerozlišují velikost písmen,
- blok vlákna runtime je v TLS slotu (`TlsAlloc`, TEB+0x1480, `gs`),
- vlákna vytváří `CreateThread`; vlákno zveřejní vrchol svého zásobníku samo
  (`lsl_thread_begin`), GC ho zastaví `SuspendThread` a registry přečte
  `GetThreadContext` (místo SIGUSR1),
- procesy: `CreateProcessW` s příkazovou řádkou podle pravidel
  `CommandLineToArgvW`, potomek dědí jen předané handle; memfd je dočasný
  soubor smazaný po zavření; výjimky (pád) končí kódem 139/132 jako signály,
- konzole: výstup `WriteConsoleW`, vstup `ReadConsoleW` v UTF-8 s `\n`.

Program se linkuje jako konzolový PE (`x86_64-w64-mingw32-ld`, ASLR, DEP,
zásobník 8 MiB celý zpřístupněný: LuxIR na Windows nesonduje zásobník).

## Přechod z x86 emitorů

Dříve byl runtime strojový kód x86-64 generovaný emitory
`compiler/pure/*_runtime_linux_x86_64.lsl`. Přepisuje se po rutinách:
`tools/runtime/build.py` sestaví `compiler/qbe/runtime.o` z obou částí a pro
každou rutinu `rt_runtime_*` definovanou tady vynechá x86 můstek. Datové
struktury (stav `lsl_state`, halda, objekty, slovníky) jsou stejné, takže
obě části pracují nad stejnými daty a po každé rutině lze pustit všechny
testy. Až x86 část nebude nic definovat, emitory se smažou.

```sh
python3 tools/runtime/build.py --compiler build/dev/lslcP2
```

## Pravidla runtime režimu (`# lsl: runtime`)

Každý modul začíná řádkem `# lsl: runtime`. Kód je omezená podmnožina LSL:

- Všechny hodnoty jsou surová 64bitová slova: Int, adresa, bity binary64.
  Parametry i výsledky funkcí jsou Int. Nevznikají žádné objekty LSL
  (seznamy, slovníky, řetězce za běhu); objekty runtime alokuje vlastními
  funkcemi.
- Funkce je exportovaný symbol se svým jménem (bez prefixu modulu), jména
  musí být jedinečná napříč moduly. `rt_runtime_*` volá vygenerovaný kód.
- Globál s jménem z velkých písmen (`OBJECT_DATA = 24`) je konstanta,
  dosadí se přímo do kódu. Ostatní globály jsou datové symboly, globály
  `tls_*` jsou thread-local. Hodnota na nejvyšší úrovni musí být celé číslo
  nebo konstantní výraz. Globál přiřazený seznamem celočíselných konstant
  (`TABULKA = [1, 2, 3]`) je pole slov v datech; jméno dává jeho adresu.
- Textový literál je statický záznam String (`+0` tag 1, `+8` délka, `+16`
  bajty); výraz dává jeho adresu.
- Paměť: `__lsl_qbe_load8/16/32/64(adresa)`, `__lsl_qbe_store8/16/32/64(adresa, hodnota)`.
- XOR je `a ~ b` (`^` je v LSL mocnina), NOT `~a`.
- Bez znaménka: `__lsl_qbe_ult/ule`, `__lsl_qbe_udiv/urem`, `__lsl_qbe_lshr`;
  dělení jako v C: `__lsl_qbe_idiv/irem`; posuny bez kontrol:
  `__lsl_qbe_shl/ashr`. Operátory `//`, `%`, `<<`, `>>` mají sémantiku
  LSL (zaokrouhlení dolů, kontrola dělení nulou a záporného posunu) a jsou
  pomalejší.
- Volání symbolu mimo LSL (vrstva architektury, x86 rutiny během přechodu):
  `__lsl_qbe_callN(__lsl_symbol("jméno"), a1, …, aN)` je přímé volání.
- Desetinná čísla: `__lsl_raw_fadd/fsub/fmul/fdiv/fneg`, porovnání
  `__lsl_raw_feq/fne/flt/fle/fgt/fge`, převody `__lsl_raw_fitof/fftoi`;
  literál `2.0` dává bity.
- Chyba: `__lsl_qbe_call1(__lsl_symbol("qbe_error_set"), "KeyError: …")`
  a návrat 0; text musí přesně odpovídat dosavadním výstupům.
- `maybe_gc` ani výjimky LSL tu nejsou; alokace GC nespouští.
- Malé funkce bez cyklů se vkládají do volajícího (LuxIR zatím neinlinuje);
  funkce `fatal_*` a `cold_*` nikdy, ať chladné cesty nezvětšují kód.

## Ověření každé změny

1. `tools/runtime/build.py`, kompilátor v pevném bodu (lslc z lslc z lslc).
2. Výstupy a diagnostiky testů a benchmarků proti předchozímu runtime.
3. `lsl-test qbe-fast` a `lsl-test qbe`.
4. Benchmarky a překlad kompilátoru: žádné zpomalení.
