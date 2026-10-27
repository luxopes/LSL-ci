# Síť, TLS a kryptografie (cíl `linux-x86_64-gnu`)

Moduly `net`, `tls`, `crypto` a `mdns` dávají programům cíle
`linux-x86_64-gnu` sokety TCP a UDP, TLS 1.2/1.3 a kryptografii nad
systémovým OpenSSL (libssl, libcrypto) a hledání služeb v síti (DNS-SD).
LSL nemá vlastní implementaci kryptografie: moduly volají OpenSSL přímo,
stejně jako Python `ssl` a `hashlib`. Jsou psané pro aplikace jako LuxDrop
(přenos souborů s připnutými klíči, LocalSend) a pro GUI v GTK: každé
čekání má časový limit a sokety jdou napojit na hlavní smyčku GLib.

```
lslc --target linux-x86_64-gnu program.lsl program
```

Program potřebuje knihovny systému (`libssl.so.3`, `libcrypto.so.3`, pro
`mdns` GLib/GIO a běžící Avahi). Handle (soket, kontext, spojení, klíč,
certifikát) je číslo `Int`; paměť OpenSSL uvolní příslušná funkce `*_free`
nebo `close`, GC ji nevidí.

Chyby: `OSError` (systém, text `strerror`), `TLSError` (fronta chyb
OpenSSL), `CryptoError`, `ValueError` pro špatné argumenty a `TimeoutError`
po vypršení limitu. Limity jsou v milisekundách, `-1` čeká bez omezení,
`0` jen zjistí, co je hned připravené.

## Modul `net`

Sokety jsou deskriptory systému. Data k odeslání jsou `String` nebo
`ByteArray`, přijatá data `ByteArray` (prázdný = protistrana zavřela
spojení). `net.text(bajty)` z nich udělá `String` (UTF-8),
`net.bytes(text)` naopak.

| Funkce | Význam |
| --- | --- |
| `net.tcp_listen(host, port, backlog=64)` | naslouchající soket; host `""` = všechny adresy IPv4, `"::"` IPv6 i IPv4, konkrétní adresa nebo `"fe80::1%wlan0"`; port `0` vybere systém |
| `net.accept(soket, limit=-1)` | `[deskriptor, adresa, port]`, nebo `[]` po vypršení limitu |
| `net.tcp_connect(host, port, limit=10000)` | spojení na jméno nebo adresu (zkouší adresy postupně); vrací deskriptor |
| `net.send(soket, data, limit=-1)` | odešle vše, vrací počet bajtů |
| `net.recv(soket, maximum=65536, limit=-1)` | nejvýš `maximum` bajtů; `TimeoutError` bez dat |
| `net.close(soket)`, `net.shutdown(soket, net.SHUT_WR)` | zavření, polovina spojení (`SHUT_RD`, `SHUT_WR`, `SHUT_RDWR`) |
| `net.local_address(soket)`, `net.peer_address(soket)` | `[adresa, port]` (IPv6 link-local se zónou `%rozhraní`) |
| `net.set_nonblocking(soket, True)`, `net.set_nodelay(soket, True)` | neblokující režim; TCP_NODELAY |
| `net.wait(soket, události, limit)` | `poll()`: vrací `net.POLLIN`, `POLLOUT`, `POLLERR`, `POLLHUP`, nebo `0` |
| `net.interfaces()` | adresy rozhraní: `[jméno, "ipv4"/"ipv6", adresa, maska, příznaky]` |

UDP a multicast:

| Funkce | Význam |
| --- | --- |
| `net.udp_open("ipv4")`, `net.udp_open("ipv6")` | soket UDP |
| `net.udp_bind(soket, host, port, reuse=True)` | navázání; `reuse` (SO_REUSEADDR + SO_REUSEPORT) dovolí více posluchačů portu |
| `net.sendto(soket, data, host, port)` | datagram |
| `net.recvfrom(soket, maximum=65536, limit=-1)` | `[ByteArray, adresa, port]`, nebo `[]` po vypršení limitu |
| `net.multicast_join(soket, skupina, rozhraní="")`, `multicast_leave` | skupina IPv4 (rozhraní = jeho adresa IPv4) nebo IPv6 (rozhraní = jméno) |
| `net.multicast_interface(soket, rozhraní, ipv6=False)` | rozhraní pro odchozí multicast |
| `net.multicast_ttl(soket, ttl)`, `net.multicast_loop(soket, True)` | TTL a doručení vlastních zpráv zpět |
| `net.set_broadcast(soket, True)` | odesílání na broadcast |

Objevování LocalSend (multicast 224.0.0.167:53317) na každém rozhraní IPv4:

```
load net
load json

receiver = net.udp_open("ipv4")
call net.udp_bind(receiver, "0.0.0.0", 53317)
sender = net.udp_open("ipv4")
for entry in net.interfaces():
    if entry[1] == "ipv4" and entry[2] != "127.0.0.1":
        call net.multicast_join(receiver, "224.0.0.167", entry[2])
        call net.multicast_interface(sender, entry[2])
        call net.sendto(sender, json.encode({"alias": "LuxOS", "announce": True}), "224.0.0.167", 53317)
    end
end
packet = net.recvfrom(receiver, 65536, 2000)
if len(packet) == 3:
    print packet[1], net.text(packet[0])
end
```

### Hlavní smyčka GLib

`glib.fd_add(soket, podmínky, obsluha)` zavolá `obsluha(soket, podmínky)`,
když je soket připravený (`glib.IO_IN`, `IO_OUT`, `IO_ERR`, `IO_HUP`),
dokud obsluha vrací `True`. Obsluha čte s limitem `0`, takže GUI nikdy
nečeká na síť:

```
function on_packet(fd, condition):
    packet = net.recvfrom(fd, 65536, 0)
    if len(packet) == 3:
        call handle(packet)
    end
    return True
end
call glib.fd_add(receiver, glib.IO_IN, on_packet)
```

## Modul `tls`

TLS nad připojeným soketem modulu `net`. Kontext (`SSL_CTX`) nese
nastavení, spojení (`SSL`) jeden handshake a přenos.

| Funkce | Význam |
| --- | --- |
| `tls.context("server")`, `tls.context("client")` | nový kontext: TLS 1.2 až 1.3, bez ověření protistrany, bez obnovy relace |
| `tls.set_versions(ctx, "1.3", "1.3")` | rozsah verzí (`"1.2"`, `"1.3"`) |
| `tls.use_certificate(ctx, certifikát, klíč)` | vlastní certifikát a klíč z modulu `crypto` |
| `tls.use_certificate_files(ctx, cert.pem, key.pem)` | totéž ze souborů PEM (řetězec certifikátů) |
| `tls.verify_none(ctx)` | bez ověření řetězce (výchozí): klíč si připne aplikace |
| `tls.verify_system(ctx)` | ověření systémovými CA a jména serveru (běžné HTTPS) |
| `tls.request_client_certificate(ctx, required=False)` | server žádá certifikát klienta (mTLS) a přijme jakýkoli; `required` odmítne klienta bez certifikátu |
| `tls.set_ciphersuites(ctx, "TLS_AES_256_GCM_SHA384:…")` | šifry TLS 1.3 v pořadí přednosti |
| `tls.set_cipher_list(ctx, "ECDHE+AESGCM")` | šifry TLS 1.2 (syntaxe OpenSSL) |
| `tls.server_preference(ctx, True)` | server vybírá šifru podle svého pořadí |
| `tls.set_alpn(ctx, ["luxdrop/1"])` | ALPN: klient nabídne, server vybere první svůj nabídnutý; bez shody spojení pokračuje bez ALPN |
| `tls.context_free(ctx)` | uvolnění kontextu |

Spojení:

| Funkce | Význam |
| --- | --- |
| `tls.client(ctx, soket, server_name="")` | klientská strana (SNI a kontrola jména při `verify_system`) |
| `tls.server(ctx, soket)` | serverová strana nad `net.accept` |
| `tls.handshake(spojení, limit=30000)` | celý handshake |
| `tls.handshake_step(spojení)` | jeden krok na neblokujícím soketu: `"done"`, nebo `"read"`/`"write"` (zavolat znovu, až bude soket připravený) |
| `tls.read(spojení, maximum=65536, limit=-1)` | aplikační data (`ByteArray`; prázdný = konec spojení) |
| `tls.write(spojení, data, limit=-1)` | zapíše vše, vrací počet bajtů |
| `tls.pending(spojení)` | bajty už dešifrované v OpenSSL (čtou se bez čekání) |
| `tls.shutdown(spojení)` | pošle close_notify |
| `tls.close(spojení, close_socket=True)` | uvolní spojení a zavře soket |
| `tls.fd(spojení)` | soket spojení (pro `net.wait`, `glib.fd_add`) |

Vyjednané parametry: `tls.version(spojení)` (`"TLSv1.3"`),
`tls.cipher(spojení)` (`"TLS_AES_256_GCM_SHA384"`; u TLS 1.2 jméno OpenSSL
jako `"ECDHE-ECDSA-AES256-GCM-SHA384"`), `tls.alpn(spojení)` (`""` bez
ALPN), `tls.peer_spki(spojení)` (DER SubjectPublicKeyInfo protistrany),
`tls.peer_certificate_der(spojení)` (celý certifikát v DER; obojí prázdné,
když protistrana certifikát neposlala), `tls.peer_certificate(spojení)`
(ukazatel X509 pro modul `crypto`, `0` bez certifikátu) a
`tls.verify_result(spojení)` (`0` = ověření prošlo).

Klient LuxDrop: jen TLS 1.3, AES-256-GCM, ALPN a připnutý klíč serveru
(otisk = SHA-256 z DER SubjectPublicKeyInfo):

```
load net
load tls
load crypto

ctx = tls.context("client")
call tls.set_versions(ctx, "1.3", "1.3")
call tls.set_ciphersuites(ctx, "TLS_AES_256_GCM_SHA384")
call tls.set_alpn(ctx, ["luxdrop/1"])
conn = tls.client(ctx, net.tcp_connect(address, 47923, 5000))
call tls.handshake(conn, 10000)
if tls.alpn(conn) != "" and tls.alpn(conn) != "luxdrop/1":
    Error(ValueError: "unexpected ALPN")
end
fingerprint = crypto.sha256(tls.peer_spki(conn))
if not crypto.constant_time_equal(fingerprint, pinned):
    call tls.close(conn)
    Error(ValueError: "key_mismatch")
end
call tls.write(conn, request, 30000)
```

Server se šiframi v pořadí AES-256-GCM, ChaCha20-Poly1305, AES-128-GCM a
předností serveru; pro LocalSend navíc TLS 1.2, ALPN `http/1.1` a
certifikát klienta (otisk LocalSend = SHA-256 celého certifikátu v DER):

```
server_ctx = tls.context("server")
call tls.use_certificate(server_ctx, certificate, key)
call tls.set_ciphersuites(server_ctx, "TLS_AES_256_GCM_SHA384:TLS_CHACHA20_POLY1305_SHA256:TLS_AES_128_GCM_SHA256")
call tls.server_preference(server_ctx, True)
call tls.set_alpn(server_ctx, ["http/1.1"])
call tls.request_client_certificate(server_ctx)
listener = net.tcp_listen("::", 53317)
accepted = net.accept(listener)
conn = tls.server(server_ctx, accepted[0])
call tls.handshake(conn, 10000)
sender = crypto.hex(crypto.sha256(tls.peer_certificate_der(conn))).upper()
```

GUI: soket přepněte do neblokujícího režimu, volejte
`tls.handshake_step` z obsluhy `glib.fd_add` (podmínka podle výsledku
`"read"`/`"write"`) a data čtěte `tls.read(spojení, maximum, 0)`;
`TimeoutError` pak znamená „zatím nic“. Před čekáním na soket se podívejte
na `tls.pending`, OpenSSL může mít data už dešifrovaná.

## Modul `crypto`

| Funkce | Význam |
| --- | --- |
| `crypto.random_bytes(n)` | kryptograficky bezpečné náhodné bajty |
| `crypto.sha256(data)`, `crypto.hash("sha384", data)` | haš najednou (`"sha256"`, `"sha384"`, `"sha512"`, `"sha1"`) |
| `crypto.hash_new(jméno)`, `hash_update(h, data)`, `hash_final(h)` | haš po částech (velké soubory); `hash_final` uvolní kontext |
| `crypto.hash_file(jméno, cesta)` | haš souboru po blocích 1 MiB |
| `crypto.hmac("sha256", klíč, data)` | HMAC |
| `crypto.constant_time_equal(a, b)` | porovnání v konstantním čase (otisky, MAC) |
| `crypto.hex(data)`, `crypto.from_hex(text)` | převod na text hex a zpět |

Klíče EC P-256 a podpisy:

| Funkce | Význam |
| --- | --- |
| `crypto.ec_generate()` | nový klíč P-256 (secp256r1) |
| `crypto.key_to_pem(klíč)`, `key_from_pem(text)` | PEM PKCS#8 bez šifrování (`BEGIN PRIVATE KEY`); načte i `BEGIN EC PRIVATE KEY` |
| `crypto.key_to_der(klíč)`, `key_from_der(data)` | DER PKCS#8 |
| `crypto.public_key_der(klíč)`, `public_key_pem(klíč)` | veřejný klíč jako SubjectPublicKeyInfo (DER, PEM) |
| `crypto.public_key_from_der(data)`, `public_key_from_pem(text)` | veřejný klíč pro `verify` |
| `crypto.key_type(klíč)`, `crypto.key_curve(klíč)` | `"EC"`, `"prime256v1"` |
| `crypto.sign(klíč, data)` | ECDSA se SHA-256, podpis DER (Java `SHA256withECDSA`) |
| `crypto.verify(veřejný, data, podpis)` | `True`/`False` |
| `crypto.key_free(klíč)` | uvolnění |

Certifikáty X.509:

| Funkce | Význam |
| --- | --- |
| `crypto.self_signed_certificate(klíč, cn, days=36500)` | certifikát podepsaný sebou samým: CN, platnost od teď, SHA-256, BasicConstraints CA:FALSE |
| `crypto.certificate_to_pem(c)`, `certificate_from_pem(text)` | PEM |
| `crypto.certificate_der(c)`, `certificate_from_der(data)` | DER |
| `crypto.certificate_spki(c)`, `certificate_public_key(c)` | SubjectPublicKeyInfo (DER), veřejný klíč |
| `crypto.certificate_common_name(c)` | CN subjektu |
| `crypto.certificate_matches_key(c, klíč)` | patří klíč k certifikátu? |
| `crypto.certificate_free(c)` | uvolnění |

Identita LuxDrop (klíč P-256, certifikát na 100 let, otisk a ID zařízení):

```
load crypto

key = crypto.ec_generate()
fingerprint = crypto.sha256(crypto.public_key_der(key))
device_id = crypto.hex(fingerprint)[0:16]
certificate = crypto.self_signed_certificate(key, "LuxDrop " + device_id)
call writefile(directory + "/identity-key.pem", crypto.key_to_pem(key))
call writefile(directory + "/identity-cert.pem", crypto.certificate_to_pem(certificate))
```

## Modul `mdns`: DNS-SD (ohlášení a hledání služeb v místní síti)

Modul `mdns` ohlašuje služby DNS-SD (Bonjour, Zeroconf) a hledá je v místní
síti, například `_luxdrop._tcp`, `_http._tcp` nebo `_ipp._tcp`. Má dva backendy:

- **Avahi** přes systémovou sběrnici D-Bus (`org.freedesktop.Avahi`). Je
  výchozí, když démon běží. Jména ověřuje (probing) a kolize řeší Avahi
  a jeho mezipaměť sdílí všechny programy na stroji.
- **Vlastní mDNS** (`raw`) přes UDP multicast `224.0.0.251:5353` (modul
  `net`). Použije se, když Avahi na sběrnici není. Soket sdílí port 5353
  s ostatními responzory (`SO_REUSEADDR`), takže funguje i vedle běžícího
  Avahi.

```
load mdns

# ohlášení
handle = mdns.announce("Antonin laptop (a1b2c3)", "_luxdrop._tcp", 47923,
    {"v": "1", "id": "a1b2c3d4e5f60718", "name": "Antonínův laptop"})
call mdns.update_txt(handle, {"v": "1", "id": "a1b2c3d4e5f60718", "name": "Nové jméno"})
call mdns.withdraw(handle)

# blokující hledání (nejvýš 3 s)
for service in mdns.browse("_luxdrop._tcp", 3000):
    print service["name"], service["address"], service["port"], service["txt"]["id"]
end
```

Modul je pro cíl `linux-x86_64-gnu` (`lslc --target linux-x86_64-gnu`), protože
používá `gio` a `glib`.

### Funkce

| Funkce | Význam |
| --- | --- |
| `mdns.announce(name, typ, port, txt=None, domain="local")` | ohlásí službu a vrátí handle (Int). `name` je jméno instance (UTF-8, nejvýš 63 bajtů), `typ` je `"_jméno._tcp"` nebo `"_jméno._udp"`, `txt` je Dictionary String → String (každá položka `klíč=hodnota` má nejvýš 255 bajtů). Neblokuje: stav ověření jména ukáže `state` |
| `mdns.update_txt(handle, txt)` | nové TXT ohlášené služby (Avahi `UpdateServiceTxt`, vlastní mDNS službu znovu ohlásí) |
| `mdns.withdraw(handle)` | stáhne službu (Avahi zruší skupinu záznamů, vlastní mDNS pošle „goodbye“ s TTL 0) |
| `mdns.state(handle)` | `"registering"` (Avahi ověřuje jméno), `"established"`, `"collision"` (jméno v síti už je, ohlaste jiné), `"failure"`, `"uncommitted"` |
| `mdns.browse(typ, timeout_ms=3000, domain="local")` | blokující hledání. Vrací List slovníků služby. Avahi skončí dřív, jakmile má vyřešené všechno, co zná (`AllForNow`). Vlastní mDNS čeká celý limit |
| `mdns.browse_start(typ, handler, domain="local")` | hledání v hlavní smyčce GLib: `handler(event, service)`, `event` je `"added"`, `"updated"` (změna TXT nebo adresy) nebo `"removed"`. Vrací id |
| `mdns.browse_stop(id)` | ukončí hledání (`True`, `False` pro neznámé id) |
| `mdns.pump(timeout_ms=0)` | zpracuje události mDNS a celé hlavní smyčky GLib po dobu `timeout_ms`. Pro programy bez `glib.main()`/`gtk.main()` |
| `mdns.use_backend(jméno)` | `"auto"` (výchozí), `"avahi"` nebo `"raw"`. Platí pro další `announce`/`browse`. Už běžící zůstávají na svém backendu |
| `mdns.backend()` | backend, který použije další volání: `"avahi"` nebo `"raw"`. Když je vynucený `"avahi"` a démon neběží, vyvolá `MDNSError` |
| `mdns.avahi_available()` | běží Avahi na systémové sběrnici? (zjišťuje se jednou za běh programu) |
| `mdns.interface_name(index)` | jméno rozhraní podle indexu (`""`, když takové rozhraní není) |

Chyby: špatné argumenty vyvolají `ValueError` (dlouhé jméno, špatný typ
služby, TXT, neznámý handle nebo backend). Chyby Avahi a soketu vyvolají
`MDNSError`, například `MDNSError: Avahi AddService:
org.freedesktop.Avahi.CollisionError: Local name collision`, když tentýž
stroj už službu se stejným jménem ohlašuje. Chyba v obsluze `browse_start`
hledání nezastaví, jen se vypíše na stderr jako `mdns handler error: …`.

### Výsledek hledání

Každá služba je Dictionary:

| Klíč | Hodnota |
| --- | --- |
| `name` | jméno instance (`"Antonin laptop (a1b2c3)"`) |
| `type`, `domain` | `"_luxdrop._tcp"`, `"local"` |
| `host` | jméno stroje (`"jupiter.local"`) |
| `address` | adresa IPv4 nebo IPv6. IPv6 link-local adresa má zónu (`"fe80::671:1466:f439:97a7%wlp4s0"`), takže ji jde rovnou předat `net.tcp_connect` |
| `port` | Int |
| `txt` | Dictionary String → String (u opakovaného klíče platí první výskyt, položka bez `=` má hodnotu `""`) |
| `interface`, `interface_name` | index a jméno rozhraní, kde byla služba nalezena |
| `protocol` | `"ipv4"` nebo `"ipv6"` (rodina adresy) |
| `local` | `True` pro službu z tohoto stroje (i vlastní ohlášení) |
| `backend` | `"avahi"` nebo `"raw"` |

Tatáž služba přijde zvlášť pro každé rozhraní a protokol, stejně jako
v `avahi-browse` (např. `wlp4s0`/ipv4, `wlp4s0`/ipv6 a `lo`/ipv4). Kdo
potřebuje jedno zařízení jednou, seskupí výsledky podle TXT `id` nebo
podle `name`. U `"removed"` obsahuje `service` poslední známé údaje.

### Hledání v GUI bez zamrznutí

`browse` blokuje. V programu GTK proto použijte `browse_start`. Obsluha se
volá z hlavní smyčky (`gtk.main()` nebo `glib.main()`), takže může rovnou
měnit widgety:

```
load gtk
load mdns

devices = {}

function on_service(event, service):
    key = service["txt"].get("id", service["name"])
    if event == "removed":
        if key in devices:
            del(devices[key])
        end
    else:
        devices[key] = service
    end
    call refresh_list()
    return 0
end

browser = mdns.browse_start("_luxdrop._tcp", on_service)
own = mdns.announce(instance_name, "_luxdrop._tcp", 47923, txt)
call gtk.main()
```

Program bez hlavní smyčky (služba v terminálu) volá v cyklu
`mdns.pump(ms)`. Pro vlastní mDNS to platí i u samotného ohlášení:
odpovědi na dotazy a opakovaná ohlášení se posílají jen tehdy, když běží
hlavní smyčka nebo `pump`.

### Vlastní mDNS (`raw`)

- Soket IPv4 `0.0.0.0:5353` je ve skupině `224.0.0.251` na všech rozhraních
  `UP` + `MULTICAST` a na loopbacku. Napojí se na hlavní smyčku přes
  `glib.fd_add`. Časovač GLib (250 ms) obstarává opakované dotazy
  a ohlášení a mazání prošlých záznamů.
- Hledání pošle dotaz PTR hned a pak znovu po 1, 2, 4 … nejvýš 60 s. Pro
  instance, kterým chybí SRV, TXT nebo adresa stroje, se doptá. Čte
  záznamy PTR, SRV, TXT, A a AAAA z odpovědí i doplňující sekce. Záznam
  s TTL 0 („goodbye“) službu hned odebere.
- Ohlášení pošle PTR, SRV, TXT, PTR `_services._dns-sd._udp` a A záznam
  stroje (`<hostname>.local` s adresou daného rozhraní) hned a pak za 1 a 3 s.
  Na dotazy odpovídá na rozhraní, odkud dotaz přišel. Na dotaz z jiného
  portu než 5353 („legacy unicast“, třeba `dig -p 5353`) odpovídá unicastem.
- Rozhraní přijaté zprávy se určuje podle adresy odesílatele (vlastní
  adresa, potom stejná podsíť). Zpráva z cizí podsítě má `interface_name`
  `""` a `interface` 0.

Omezení vlastního mDNS: posílá a přijímá jen přes IPv4 (skupinu `ff02::fb` pro
IPv6 nepoužívá). Záznamy AAAA přijaté přes IPv4 ale hlásí jako výsledky
`"ipv6"`. Neověřuje jméno (probing) ani neřeší kolize, `state` je hned
`"established"`. Nepoužívá potlačení známých odpovědí ani kompresi jmen
v odesílaných zprávách. Vlastní ohlašovaný stroj má jen adresu IPv4.

### Testování obou backendů

`mdns.use_backend("raw")` vynutí vlastní mDNS i na stroji, kde běží Avahi.
Test `tests/gnu/mdns_conformance.lsl` takto v jednom procesu ohlásí a najde
službu nejdřív přes Avahi a pak přes vlastní mDNS (multicast se vrací zpět
na tentýž stroj, i přes loopback). Ověří přitom TXT s UTF-8, změnu TXT
(`"updated"`) a stažení služby (`"removed"`).

Testy: `tests/gnu/net_conformance.lsl`, `tls_conformance.lsl` (handshake
na loopbacku s připnutým klíčem, ALPN, výběr šifry, mTLS, TLS 1.2) a
`crypto_conformance.lsl` (vektory SHA-256 FIPS 180-2, HMAC RFC 4231, ECDSA
P-256 RFC 6979) a `mdns_conformance.lsl` (oznámení a hledání přes Avahi
i čisté mDNS, potřebuje běžící avahi-daemon).
