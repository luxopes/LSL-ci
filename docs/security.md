# Bezpečnostní model LSL

LSL 0.7 zpevňuje compiler, generovaný runtime a integrační
knihovny proti poškozeným vstupům, přetečením, únikům deskriptorů a zneužití
prostředků. Běžný LSL program stále běží s právy svého procesu; izolaci je
nutné výslovně zapnout přes `lsl sandbox`.

## Co chrání samotný runtime

- Generované Linux x86-64 executable jsou statické PIE s ASLR, jediným RX
  segmentem a neproveditelným stackem.
- Heap objekty, kolekce, I/O buffery, native handly a dynamické callbacky se
  před použitím validují; velikosti a násobení alokací mají pevné horní meze.
- Lexer, parser, linker, JSON, config a BigInt odmítají nadměrné nebo příliš
  hluboké vstupy dříve, než mohou způsobit neomezenou rekurzi či růst paměti.
- Dictionary používá per-process seed, takže předpočítaná sada kolizních klíčů
  nemůže spolehlivě změnit běžné vložení na kvadratickou práci.
- Worker vlákna mají guard page. GC při příliš hlubokém grafu raději neuvolní
  nic, než aby pokračoval po přetečení své mark rekurze.
- Process helpery používají přímé `execve`, kontrolují argv, zavírají zděděné
  deskriptory a jejich `*_clean` varianty předávají prázdné prostředí.

Tyto vlastnosti snižují dopad chyb, ale nenahrazují oddělení nedůvěryhodného
kódu na úrovni operačního systému.

Volitelný CUDA worker běží jako samostatný proces. Jeho JSON a binární protokol
má pevné limity vstupu, hloubky, počtu prvků a device paměti; release binárka
je PIE s full RELRO, NOW binding, stack protector a neproveditelným stackem.
CUDA driver a runtime přesto zůstávají cizí důvěryhodnou závislostí.

## HTTP, balíčky a TLS

TLS zajišťuje systémový `/usr/bin/curl` a jeho trust store. LSL předává URL,
hlavičky i tělo přes validovaný config na stdin, spouští curl s `-q`, omezuje
velikost odpovědi a nepovoluje redirecty. HTTPS je povinné; prosté HTTP je
povoleno jen pro číselné loopback adresy `127.0.0.1` a `[::1]`. Package registry
navíc ověřuje deklarovaný SHA-256, ale hash stažený ze stejného serveru není
náhradou za podepsaný registr.

Serverový modul přijímá jen omezené GET/HEAD HTTP a statické soubory otevírá
přes připnutý directory fd a `openat2` s `RESOLVE_BENEATH`/no-symlink policy.
HTTPS kryptografii deleguje systémovému nginx/OpenSSL a při jeho absenci
nespadne do plaintext fallbacku. Podrobnosti jsou v [serverové příručce](server.md).

## Native ABI

`native.call` spouští ověřený self-contained ET_DYN kód v krátkodobém fork
child procesu. Child zavře ostatní deskriptory, nastaví `no_new_privs`, strict
seccomp a časový limit; rodič přijme pouze jeden Int64 výsledek. Mapování jsou
W^X a souběžné `symbol`/`call`/`close` operace jsou serializované.

Tato hranice chrání integritu a dostupnost rodičovského LSL procesu před
memory-corruption chybou native kódu. Není to hranice důvěrnosti: fork child
zdědí čitelný snapshot adresního prostoru. Úmyslně škodlivý strojový kód proto
nesmí běžet přes `native.call`; spusťte jej jako nový `exec` worker v procesu,
který nikdy neobsahoval secrets.

## Bezpečný CLI překlad a privátní low-level ABI

Jména začínající `__lsl_` jsou interní privilegované rozhraní stdlib, nikoli
bezpečná aplikační API. Patří sem přímé syscalls, adresy, mmap a raw memory
pack/unpack operace. Program, který je volá, může obejít kontroly veřejných
modulů. Výchozí `lsl` a `lsl compile` je proto povolí jen v explicitním
lexikálním bloku `unsafe:` a kontrolují i uživatelské importy. `native_*` a
`thread_spawn` sdílejí stejnou hranici. `unsafe:` je auditní značka, nikoli
automatická ochrana.

Direktiva `# lsl: unchecked-intarray` podobně vypíná bounds checks pro celý
root source a vyžaduje `lsl compile --unsafe`. Nízkoúrovňový `lslc` je
trust-core nástroj bez této CLI policy.

## Procesový capability sandbox

`lsl sandbox` kompiluje pouze safe podmnožinu (odmítá i samotný `unsafe:`
blok) a spouští statický ELF přes bubblewrap. Výchozí profil oddělí user,
mount, PID, IPC, UTS, cgroup i network namespace, vytvoří prázdný tmpfs root a
zpřístupní jen read/write bindy zadané uživatelem. Systemd cgroup omezuje paměť
a počet tasků; `prlimit` a `timeout` přidávají address-space, CPU/wall clock,
stack, descriptor, output-file a core-dump limity. Finální program dostane
čisté prostředí.

Profil `server` sdílí host network namespace, ale zachovává filesystem a
process izolaci. Sandbox selže zavřeně, pokud chybí bubblewrap, systemd user
session nebo některý limitovací nástroj. Přesný model a příklady jsou v
[dokumentaci sandboxu](sandbox.md).

## Nedůvěryhodné workery a control plane

Nedůvěryhodný LSL worker spouštějte pomocí `lsl sandbox` jako krátkodobý proces
bez secrets a s minimem `--read`/`--write` oprávnění. C/C++ nebo CUDA worker
musí být samostatný executable a má dostat stejnou nebo silnější vnější
izolaci. Pro vysoce rizikový multi-tenant provoz přidejte ještě seccomp
allowlist, VM/microVM hranici a host-level monitoring.

LSL compiler, GC a codegen nemají nezávislý víceletý bezpečnostní audit.
TLS/OIDC, databáze, migrace, kryptografie, audit log a bezpečnostní kořen
služby proto patří do hostitelské platformy s vyzrálými knihovnami. Režim
`lsl config` staticky omezuje ambientní capability kvůli reprodukovatelnosti;
pro nepřátelský vstup jej i tak spusťte ve vnějším procesovém sandboxu.

Bezpečnostní chyby hlaste správci repozitáře neveřejným kanálem a přiložte
minimální reprodukci, verzi LSL a cílové Linux x86-64 prostředí.
