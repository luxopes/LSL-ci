# Bezpečnostní model LSL

LSL 0.6.9 zpevňuje compiler, generovaný runtime a integrační knihovny proti
poškozeným vstupům, přetečením, únikům deskriptorů a zneužití prostředků. Není
to ale bezpečnostní sandbox. Běžný LSL program běží s právy svého procesu a
může číst soubory, otevírat sockety a spouštět další programy.

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

## Privátní low-level ABI

Jména začínající `__lsl_` jsou interní privilegované rozhraní stdlib, nikoli
bezpečná aplikační API. Patří sem přímé syscalls, adresy, mmap a raw memory
pack/unpack operace. Program, který je volá, může obejít kontroly veřejných
modulů a musí být považován za důvěryhodný native-adjacent kód.

Direktiva `# lsl: unchecked-intarray` podobně vypíná bounds checks pro celý
root source. Používejte ji pouze pro algoritmy, které mají rozsahy indexů
samostatně dokázané a otestované.

## Nedůvěryhodné workery a control plane

Nedůvěryhodný LSL, C/C++ nebo CUDA kód spouštějte jako samostatný krátkodobý
proces bez secrets a s minimem filesystem/network oprávnění. Podle rizika
přidejte user/mount/network namespaces, seccomp allowlist, cgroup limity,
read-only filesystem a časový limit z nadřazeného procesu.

LSL compiler, GC a codegen nemají nezávislý víceletý bezpečnostní audit.
TLS/OIDC, databáze, migrace, kryptografie, audit log a bezpečnostní kořen
služby proto patří do hostitelské platformy s vyzrálými knihovnami. Režim
`lsl config` staticky omezuje ambientní capability kvůli reprodukovatelnosti,
ale pro nepřátelský vstup stále používejte vnější OS sandbox.

Bezpečnostní chyby hlaste správci repozitáře neveřejným kanálem a přiložte
minimální reprodukci, verzi LSL a cílové Linux x86-64 prostředí.
