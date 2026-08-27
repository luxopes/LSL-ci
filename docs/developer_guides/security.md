# Bezpečnostní model LSL

LSL 0.6.8 zpevňuje compiler, generovaný runtime a standardní knihovnu proti
poškozeným vstupům, přetečením, únikům deskriptorů a resource-exhaustion
útokům. Běžný LSL program ale **není sandbox**: běží s právy svého procesu a
může číst soubory, otevírat sockety a spouštět programy.

## Runtime a vstupy

- Výstup je statické Linux x86-64 PIE s ASLR, jediným RX segmentem a
  neproveditelným stackem.
- Kolekce, I/O, callbacky a native handly se před použitím validují; alokace,
  parser, linker, JSON, config a BigInt mají pevné limity.
- Worker stacky mají guard page. GC a rekurzivní equality končí fail-safe při
  příliš hlubokém grafu.
- Dictionary hash používá per-process seed proti předpočítaným collision DoS.
- Process helpery používají přímé `execve`, kontrolují argv a zavírají zděděné
  descriptory; `*_clean` varianty předávají prázdné prostředí.
- Volitelný CUDA worker validuje celý JSON objekt a ABI a má pevné limity pro
  stdin, hloubku, pole i device buffery. Release binárka je PIE s full RELRO,
  NOW binding, stack protector a neproveditelným stackem.

## HTTP a TLS

TLS zajišťuje systémový `/usr/bin/curl`. URL, hlavičky i tělo jdou přes
validovaný config na stdin; LSL vypíná ambientní curl config a redirecty a
omezuje velikost odpovědi. HTTPS je povinné, prosté HTTP je povoleno jen pro
`127.0.0.1` a `[::1]`.

## Native kód

`native.call` spustí ověřený ET_DYN kód v krátkodobém fork child procesu.
Child zavře ostatní descriptory, nastaví `no_new_privs`, strict seccomp a
dvousekundový alarm. Mapování jsou W^X a rodič přijme pouze jeden Int64
výsledek.

Tato izolace chrání integritu a dostupnost rodiče před chybou native kódu.
Není hranicí důvěrnosti: fork child zdědí čitelný snapshot adresního prostoru.
Úmyslně škodlivý strojový kód proto spusťte jako nový `exec` worker v procesu,
který nikdy neobsahoval secrets.

## Privátní ABI a nedůvěryhodné programy

Jména začínající `__lsl_` jsou privilegované interní stdlib ABI. Přímé syscalls,
adresy a raw memory operace mohou obejít veřejné kontroly a nejsou bezpečným
aplikačním API. Direktiva `# lsl: unchecked-intarray` obdobně vypíná bounds
checks pro celý root source.

Nedůvěryhodný LSL, C/C++ nebo CUDA kód spouštějte bez secrets jako samostatný
proces s minimem filesystem/network oprávnění. Podle rizika přidejte
namespaces, seccomp allowlist, cgroup limity, read-only filesystem a timeout z
nadřazeného procesu.

LSL compiler, GC a codegen nemají nezávislý víceletý bezpečnostní audit.
TLS/OIDC, databáze, kryptografie, audit log a bezpečnostní kořen služby proto
patří do hostitelské platformy s vyzrálými knihovnami. `lsl config` staticky
omezuje ambientní capability kvůli reprodukovatelnosti, ale pro nepřátelský
vstup stále potřebuje vnější OS sandbox.
