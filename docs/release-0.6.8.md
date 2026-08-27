# LSL 0.6.8

LSL 0.6.8 je čistě bezpečnostní vydání bez změny syntaxe jazyka. Aktualizuje
živý manuál a přidává samostatný bezpečnostní model; nový kopírovaný snapshot
manuálu není potřeba.

Hlavní změny:

- runtime odmítá přetečení a nadměrné alokace kolekcí, validuje raw objekty na
  I/O/memory hranicích a omezuje rekurzi equality i GC mark fáze;
- worker stacky mají guard page, callbacky musí být živé Function objekty a
  selhání kritického thread setupu končí fail-closed;
- native loader serializuje `symbol`/`call`/`close`, drží ownership knihovny
  přes GC a volá kód v krátkodobém `fork` child procesu s uzavřenými
  deskriptory, `no_new_privs`, strict seccomp a timeoutem;
- process helpery validují program i argv, zavírají cizí file descriptory,
  čistí prostředí v bezpečnostních variantách, omezují zachycený výstup a
  používají bezpečné setup-error cesty; řízené stdin/stdout/stderr endpointy
  správně přežijí `execve` i při původně zavřených fd 0/1/2;
- filesystem zápis chrání proti symlinkům a používá bezpečnější atomické
  vytvoření; file, fd, mmap a Unix socket API kontrolují typy, rozsahy a NUL;
- HTTP/curl config je byte-lineární, omezený velikostí, bez redirectů a bez
  ambientního curl configu; prosté HTTP přijímá jen numerický loopback;
- JSON, config, BigInt, lexer, parser a linker mají byte-přesné limity délky,
  hloubky a počtu prvků; config navíc omezuje celý importní graf, detekuje
  cykly a kompiluje ověřený snapshot;
- Dictionary hash je per-process seedovaný proti předpočítaným collision DoS;
  dynamická Int mocnina je logaritmická a záporný exponent končí řízenou
  chybou;
- package, plugin, GUI/display a ostatní stdlib hranice dostaly stejné
  typové, velikostní a process-isolation kontroly;
- CUDA worker validuje celý JSON protokol a ABI, odmítá duplicitní klíče,
  omezuje stdin, hloubku, počty prvků i device buffery a release binárka má
  PIE, full RELRO, NOW binding, stack protector a neproveditelný stack;
- dočasný vývojový compiler už nemůže potichu načíst starý `/lib/lsl` strom;
  fyzická cesta resource se oddělila od kanonického source jména, takže
  fixed-point výstup nezávisí na umístění executable;
- ze stromu zmizel nepoužívaný historický `-o` ET_EXEC artefakt; release zdroj
  tak neobsahuje zastaralý executable mimo auditovaný toolchain.

Bezpečnostní hranice jsou popsány v [docs/security.md](security.md). Běžný LSL
program ani privátní `__lsl_*` ABI nejsou sandbox. Native child izolace chrání
rodičovský proces před poškozením a zacyklením, nikoli jeho adresní snapshot
před úmyslně škodlivým strojovým kódem; takový kód patří do externího `exec`
workeru bez secrets.

Regresní sada pokrývá alokační overflow, deep GC/equality, neplatné callbacky,
native ownership a souběžný close/call, zděděné descriptory, symlink zápis,
HTTP/JSON/config/CUDA limity a poškozené ELF obrazy. Vydání prošlo bitově shodným
self-host fixed pointem, fast i full suite, instalovaným fixed pointem a auditem
všech generovaných ELF. Finální SHA-256 jsou uvedené v
`PURE_LSL_PROGRESS.md` a `docs/developer_guides/downloads/SHA256SUMS`.
