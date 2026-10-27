# Release LSL 0.10.7

Vydáno 27. 10. 2026. Backend LuxIR 0.4.4.

Opravy chyb nalezených při převodu LuxAI do LSL a nové moduly pro síť,
TLS, kryptografii a mDNS (zadání LuxOS pro přepis LuxDrop do LSL).

## Opravy

- Instance předaná jako parametr, prvek seznamu nebo argument callbacku:
  `item.value`, `item.value = x` i `item.metoda()` fungují (dřív
  `AttributeError: member value requires a class or instance`). Typ se
  ověří za běhu; stejnojmennou metodu více tříd na hodnotě bez statického
  typu překladač odmítne srozumitelnou chybou.
- Podmíněný výraz `a if podmínka else b` z manuálu (dřív E1201);
  vyhodnotí jen vybranou větev.
- Vnořená funkce hlásí E1248 u definice místo `KeyError: key not found`.
- Funkce, která v jedné větvi vrací `None` a v jiné `Int`/`Float`/`Bool`,
  vrací `None` (dřív `0`, `0.0`, `False`).
- `strip`, `lstrip`, `rstrip` (i se znaky) a výřez `value[a:b]` na hodnotě
  bez statického typu jsou lineární: 16 kB textu 5 µs místo 0,18 s,
  200 kB výřez desítky ms místo vypršení.
- `glib.pump()` už nepadá na `pass` (`NameError`).
- Vestavěné `cwd()`, `chdir(cesta)`, `remove_path(cesta)` a globální
  `args` z manuálu existují (dřív „unknown native function/variable“).
  `cwd`/`chdir` na Linuxu, Windows a macOS; WASI a bare metal mají kořen
  `/` a `chdir` hlásí chybu.
- Interní ABI cíle gnu: `__lsl_qbe_icallN` vrací C `int` znaménkově
  rozšířený (`open()` = `-1`, ne `4294967295`); `__lsl_qbe_f32(x)` předá
  parametr C `float` v jednoduché přesnosti (dřív funkce četla `0.0`), tím
  fungují i `gtk.label_set_xalign`/`set_yalign` a
  `pango.layout_set_line_spacing`.
- Programy cíle gnu mají verze importovaných symbolů glibc (LuxIR 0.4.4):
  `realpath(cesta, NULL)` volá `realpath@GLIBC_2.3`, ne kompatibilní 2.2.5
  (`EINVAL`). Program potřebuje glibc alespoň verze stroje překladu.

## Nové moduly cíle `linux-x86_64-gnu`

Kapitola manuálu `network` (`lsl man network`).

- `net`: TCP servery a klienti IPv4/IPv6 (i link-local se zónou), časové
  limity, neblokující režim, UDP, multicast (skupina, rozhraní, TTL,
  smyčka), adresy rozhraní, `net.text`/`net.bytes` pro ByteArray a String.
- `tls`: TLS 1.2 a 1.3 nad systémovým OpenSSL, klient i server, vlastní
  certifikát a klíč, bez ověření řetězce s připnutím klíče (`peer_spki`,
  `peer_certificate_der`), ověření systémovými CA, mTLS (server přijme
  certifikát podepsaný sebou samým), ALPN, šifry TLS 1.3/1.2 a jejich
  pořadí, přednost serveru, vyjednaná verze/šifra/ALPN, čtení a zápis
  s limitem, neblokující `handshake_step` pro hlavní smyčku GLib.
- `crypto`: náhodné bajty, SHA-256/384/512 najednou, po částech i ze
  souboru, HMAC, klíče EC P-256 (PEM PKCS#8, DER, SubjectPublicKeyInfo),
  ECDSA se SHA-256 (podpis DER), certifikáty X.509 podepsané sebou samým,
  porovnání v konstantním čase, hex.
- `mdns`: ohlášení a hledání služeb DNS-SD (TXT, změna TXT, odvolání)
  přes Avahi D-Bus, bez Avahi čisté mDNS (IPv4); blokující `browse` i
  události v hlavní smyčce GLib.
- `glib.fd_add(soket, podmínky, obsluha)`: deskriptor v hlavní smyčce.

## Testy

Nové `tests/fixes_0107_conformance.lsl`, `tests/gnu/net_conformance.lsl`,
`tls_conformance.lsl` (handshake na loopbacku s připnutým klíčem, ALPN,
výběr šifry, mTLS, TLS 1.2), `crypto_conformance.lsl` (SHA-256 FIPS 180-2,
HMAC RFC 4231, ECDSA P-256 RFC 6979), `mdns_conformance.lsl` (Avahi
i čisté mDNS), `abi_0107_conformance.lsl` a negativní test E1248. TLS
ověřeno i proti `openssl s_client` (mTLS) a Python `ssl` (připnutý klíč).

## Známá omezení

- Překlad malých programů je proti 0.10.6 o 3–12 % pomalejší (větší
  dynamická stdlib a skokový rozpočet GC); běh programů je stejný nebo
  rychlejší. Podrobnosti v `tests/release/0.10.7/README.md`.
- Podepsaný kanál `lsl update` zůstává na 0.10.6; 0.10.7 se instaluje
  z archivu (`lsl-install`).
- `mdns` bez Avahi umí jen IPv4 a neřeší kolize jmen.
- Návratovou hodnotu C `float` interní ABI nečte (jen parametry přes
  `__lsl_qbe_f32`).
