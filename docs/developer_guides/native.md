# Knihovna native

`load native`

Omezené CPU ET_DYN ABI izolované forkem. Knihovny musí být soběstačné
PIC bez relokací a externích závislostí; volání běží v krátce žijícím
podřízeném procesu pod přísným seccomp filtrem.

## Funkce

### native.open(path)

Namapuje a zvaliduje Linux x86_64 ET_DYN obraz. Vrací handle knihovny.

### native.symbol(library, name)

Najde adresu symbolu (tisknutelné jednoznakové ELF jméno).

### native.call(target, arguments)

Zavolá nativní funkci s argumenty (Int/Float) v izolovaném procesu.

### native.close(library)

Uvolní namapovanou knihovnu.

### native.u8 / u16 / u32(library, offset)

Čtení bajtů z paměti knihovny (ELF hlavičky apod.).

## Omezení

Žádné relokace, žádné závislosti, `st_value` mapované na offset souboru.
To záměrně vylučuje libc a cizí buildy — jen samoobsažné kernely.

## Chyby

- `NativeError` — neplatná cesta, špatný ELF, chybějící symbol.

## Související stránky

- `lsl man cuda` — GPU worker jako oddělený proces
- `lsl man process` — spouštění programů
