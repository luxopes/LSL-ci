# Bezpečnostní model LSL

LSL 0.7 zpevňuje compiler, generovaný runtime a standardní knihovnu proti
poškozeným vstupům, přetečením, únikům deskriptorů a resource-exhaustion
útokům. Běžný LSL program stále běží s právy svého procesu; procesovou izolaci
je nutné zapnout přes `lsl sandbox`.

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

Statický server LSL přijímá jen omezené GET/HEAD, má pevné request/response
limity a document root připíná přes directory fd + fail-closed `openat2`.
HTTPS kryptografii deleguje systémovému nginx/OpenSSL.

## Native kód

`native.call` spustí ověřený ET_DYN kód v krátkodobém fork child procesu.
Child zavře ostatní descriptory, nastaví `no_new_privs`, strict seccomp a
dvousekundový alarm. Mapování jsou W^X a rodič přijme pouze jeden Int64
výsledek.

Tato izolace chrání integritu a dostupnost rodiče před chybou native kódu.
Není hranicí důvěrnosti: fork child zdědí čitelný snapshot adresního prostoru.
Úmyslně škodlivý strojový kód proto spusťte jako nový `exec` worker v procesu,
který nikdy neobsahoval secrets.

## Safe/unsafe hranice a nedůvěryhodné programy

Jména začínající `__lsl_` jsou privilegované interní stdlib ABI. Přímé syscalls,
adresy a raw memory operace mohou obejít veřejné kontroly a nejsou bezpečným
aplikačním API. Výchozí `lsl compile` je spolu s `native_*` a `thread_spawn`
povolí pouze v explicitním `unsafe:` bloku a kontroluje i uživatelské importy.
Direktiva `# lsl: unchecked-intarray` vyžaduje celý překlad `--unsafe`.

`lsl sandbox` unsafe kód vůbec nepřeloží a spustí worker v bubblewrap
user/mount/PID/IPC/UTS/cgroup/network namespaces, prázdném rootu a čistém
prostředí. Read/write host cesty jsou pouze explicitní capabilities; systemd
cgroup, prlimit a timeout omezují tasky, paměť, CPU, čas, stack, deskriptory a
výstup. `server` profil sdílí jen network namespace. C/C++ nebo CUDA worker
musí být samostatný executable a má dostat stejnou nebo silnější izolaci.

LSL compiler, GC a codegen nemají nezávislý víceletý bezpečnostní audit.
TLS/OIDC, databáze, kryptografie, audit log a bezpečnostní kořen služby proto
patří do hostitelské platformy s vyzrálými knihovnami. `lsl config` staticky
omezuje ambientní capability kvůli reprodukovatelnosti; pro nepřátelský vstup
jej i tak spusťte v procesovém sandboxu.
