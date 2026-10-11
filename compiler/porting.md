# Porty LSL a hranice komponent

Dostupným cílem je `linux-x86_64`. `windows-x86_64` a `macos-x86_64` mají
registry descriptor, ale nejsou dostupné pro překlad. Chybějící implementace
se nesmí nahradit Linux modulem ani vytvořit ELF s jiným názvem.

```text
source + knihovny cíle
        ↓ frontend.prepare
validovaný AST, typy, binding IDs, připravené argumenty/chyby
        ↓ compiler_backend.emit
objekt: code, data, entry, relokace, symboly, importy, metadata
        ↓ image_writer.write
ELF / budoucí PE nebo Mach-O
```

## Co je společné a co poskytuje port

| Komponenta | Rozhraní | Windows/macOS x86_64 |
| --- | --- | --- |
| Frontend | `frontend.prepare`, `validation_version=1` | společný |
| CPU emise | `backend_x86_64.generate_object`, `x86_64`, `assembler_x86_64` | společná |
| Privátní LSL ABI | `abi_x86_64`, `value_abi` | společné, není OS native ABI |
| Cílový runtime | `runtime.select` a emise runtime helperů | nová implementace |
| Image writer | `image_writer.write` | nový PE32+/Mach-O64 writer |
| Knihovny | mapování rezervovaných importů v `target.modules` | nové poskytovatele |
| Hostitelské nástroje | `host`/`_compiler_host_platform`, install/update/package/catalog | nové poskytovatele |

Pro jiné CPU se navíc implementuje CPU ABI, encoder, assembler, relokace
a backend. Stabilní binding IDs a frontend se nemění na strojové offsety.

## Objekt a materializace

`object_code.program(architecture, code, data, entry_offset, relocations,
metadata, symbols=None, imports=None)` vrací `object_version=1`. Sekce jsou
ByteArray; entry je offset v code. Metadata nesou `target`, `abi`, `runtime`.
Symbols je Dictionary `name → {section, offset}`. Imports je List záznamů
`{symbol, library, name}` s unikátním symbol key.

Relokace obsahuje `kind`, `width`, `section`, `offset`, `base`, `addend` a buď
`target_section`/`target_offset`, nebo deklarovaný `symbol`. Objekt kontroluje
rozsahy, duplicity a deklaraci symbolů; architekturní handler a image writer
navíc kontrolují podporovaný druh a výsledný adresní rozsah.

`assembler.import_symbol(builder, library, name)` deklaruje externí symbol.
`assembler.external_relative(builder, opcode, symbol)` přidá čtyřbajtovou
`import_pc_rel32` relokaci; writer určí adresu importního slotu (například IAT).
Runtime používá tento vstup pro své adaptéry systémových API.
`assembler.export_symbol` zaznamená pojmenovaný offset. Backend přenáší tyto
tabulky z builderu do objektu bez znalosti DLL nebo Mach-O struktur.

`assembler.finish` vyřeší interní labely; datové a importní relokace zůstávají
pro writer. `image_writer` ověří shodu descriptoru a objektu. Writer rozhoduje
o adresách, ochranách a zarovnání sekcí, aplikuje relokace na kopii code a
vrátí obraz. Opakovaná materializace téhož objektu musí být deterministická.
Současný statický ELF odmítá externí importy. Nový writer musí podporovat své
importy a explicitně odmítnout nepodporované relokace a přetečení.

## Runtime kontrakt

`runtime.lsl` je dispatch; nový port přidá implementaci a jeho větve. Má tyto
vstupy se selected runtime ID a assembler builderem:

- `emit_all`, `emit_lazy(text_used, input_used)` emitují helpery s privátním LSL ABI;
- `emit_entry(globals_bytes, registry_bytes, registry_mask)` vytvoří heap, stav,
  kořeny, argumenty a hlavní thread; `emit_exit`/`emit_finish` ukončí proces;
- `state_bytes` určuje začátek globálů; `thread_load/store/store_immediate/compare`
  operují nad sloty `error`, `error_flag`, `stack_top`;
- `emit_gc_poll(done)` emituje safepoint; `release_input` uvolní stav vstupu;
- `prepare_static_write` a `emit_static_write` obslouží diagnostický zápis
  s `rdi=handle`, `rsi=data`, `rdx=bytes`.

Makra nesmí poškodit živé registry mimo deklarované cíle/scratch registry.
Zachování `rbx`, kořenů, frame a pending error při helper volání je součást ABI.
Linux TLS/GC offsety vlastní `runtime_abi_linux_x86_64`, nikoli `abi_x86_64`.
Port si volí vlastní state layout, TLS, synchronizaci a způsob alokace.

Runtime poskytuje labely pro skaláry/boxing, kolekce/GC, print/input, files,
procesy/capture, čas, vlákna/atomiky a native pluginy, na které odkazuje backend.
Nevyřešený label assembler odmítá. Normální knihovny požadují operace, raw
`__lsl_syscall`/`__lsl_syscall6` zůstávají specifickým Linux rozhraním. Port musí
nepodporovanou službu jasně odmítnout; například Windows nemá předstírat Linux
SCM_RIGHTS nebo seccomp. Zachytitelné chyby a návratové hodnoty veřejných API
se zachovají nebo dostanou výslovnou chybu nepodporované platformy.

## Knihovny a hostitel

`target.provider_modules(os)` mapuje `_fd_platform`, `_unixsock_platform`,
`_httpserver_transport`, `_random_platform`, `_tui_platform`, `_cuda_transport`,
`_ai_platform`, `_os_platform`, `_plugin_platform`, `_native_platform`,
`_system_platform`, `_sandbox_platform`, `_luxos_platform` a `_host_platform`.
Jména konkrétních stdlib implementací jsou `_<service>_<os>_x86_64`.

Veřejné API fasády zachovávají signatury a default argumenty. Linux provider
určuje Linux flags, errno, kernelové struktury, cesty a externí nástroje.
Provider dalšího OS může používat vlastní reprezentaci handle a vlastní flags;
nesmí posílat Linux sockaddr/stat/pollfd přímo do cizího API. HTTP parser,
PRNG algoritmy, TUI renderování/dekódování a CUDA protokol zůstávají společné.
Native API v1 má Linux ELF loader v samostatném provideru.

Compiler nástroje mají `_update_platform`, `_update_install_platform`,
`_catalog_platform`, `_package_platform`, `_install_platform`; konkrétní moduly
jsou bez úvodního podtržítka. Linux instalace, atomické symlinky, updater,
adresářové záznamy a shell-free systémové příkazy jsou výhradně v těchto modulech.

`host.lsl` vybírá interní provider přes `_compiler_host_platform`; veřejné
knihovny používají malý `_host_platform` pro nástroje a null device. Interní provider
je součástí compiler trust core, aby zdrojové cesty knihoven neměnily fixed point.
Používá hostitele, pro který byl compiler sám zkompilován.
Řeší hledání zdrojů, knihoven a nástrojů, cesty, HOME, scratch directory,
terminál a limitovaný evaluator. Při cross překladu z Linuxu do Windows zůstává
běžící compiler na Linux host provideru; importy sestavovaného programu vybírá
Windows descriptor. Chybějící trusted knihovny musí selhat bez shadowingu cwd.
Bootstrap fasády existují jen pro sestavení starším compilerem.

## Windows a macOS

Windows runtime potřebuje adaptéry mezi privátním LSL ABI a Win64 systémovými
API. Win64 používá čtyři argumentové registry, shadow space a požadavky na
zarovnání; přímé volání LSL funkce tedy nestačí. Viz
[Microsoft x64 calling convention](https://learn.microsoft.com/en-nz/cpp/build/x64-calling-convention?view=msvc-170).
PE writer musí vytvořit platné PE32+ headers, sekce, entry, importy a potřebné
relokace. Host provider dodá Windows cesty, spouštění procesů, terminál a instalaci.

macOS runtime potřebuje vlastní startup, systémová volání/API, TLS, vlákna,
procesy, heap a native knihovny. Mach-O writer vytvoří x86_64 CPU metadata,
load commands, segmenty, entry a případné dylib bindings; požadavky na podpis
se ověří na podporované verzi macOS. Definice formátu jsou v Apple XNU
[loader.h](https://github.com/apple-oss-distributions/xnu/blob/main/EXTERNAL_HEADERS/mach-o/loader.h)
a [machine.h](https://github.com/apple-oss-distributions/xnu/blob/main/osfmk/mach/machine.h).

Implementujte runtime, writer a providery nejprve s cílem označeným jako
nedostupný. Zapojte dispatch, distribuční seznamy a testy. Teprve po ověření
na skutečném cílovém OS přepněte `available=True`. Přeznačení Linux descriptoru
není port. Release ani změna verze není součást tohoto rozdělení.

## Ověření

`tests/compiler/object_image_conformance.lsl` ověřuje společný frontend pro
metadata všech tří OS, oddělenou emisi a materializaci, opakovaný writer,
spuštění Linux obrazu, nesoulad descriptorů, rozdělené sekce, rel32 hranice,
symboly/importy a odmítnutí neimplementovaných cílů.

Každý port potřebuje skutečné spuštění základních programů, files/Unicode,
CLI run/compile/config, procesů/capture, chyb, GC, threadů/atomik, terminálu,
socketů, případně native pluginů a instalace. Ověřte host/target rozdíl,
trusted resource lookup, negativní relokace a self-host fixed point. Linux
regrese běží existujícím `tests/lsl-test full` s kandidátním compilerem.
