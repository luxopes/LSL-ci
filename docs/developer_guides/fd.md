# Knihovna fd

`load fd`

Nízkoúrovňové I/O s deskriptory souborů nad runtime builtiny
`__lsl_fd_*`. Zařízení (framebuffer, evdev) potřebují trvalý deskriptor,
bajtové čtení a neblokující režim, které vestavěné `readbytes`/`writebytes`
neumí vyjádřit.

## Deskriptory

```lsl
fd.open(path, flags)             # otevře soubor/zařízení
fd.socket(domain, kind)          # surový socket
fd.connect_unix(path)            # připojení k unix socketu
fd.close(handle)                 # zavře deskriptor
```

## Přenos dat

```lsl
fd.read(handle, buffer, count)   # čte do ByteArray
fd.write(handle, buffer, count)  # zapíše z ByteArray
fd.seek(handle, position)        # posune pozici
```

## Ovládání a mapování

```lsl
fd.ioctl(handle, request, buffer)
fd.mmap(handle, length, offset)
```

## Omezené čtení souborů

```lsl
fd.read_all_limit(path, limit)   # bajty s limitem
fd.read_all(path)                # celý soubor
fd.read_text(path)               # UTF-8 text
fd.read_text_limit(path, limit)  # UTF-8 text s limitem
```

## Příklad

```lsl
load fd

text = fd.read_text_limit("/proc/version", 4096)
print text.strip()
```

## Chyby

- `FDError` — neplatná cesta, zavřený deskriptor, chyba syscallu.

## Související stránky

- `lsl man unixsock` — unix sockety s předáváním deskriptorů
- `lsl man httpserver` — HTTP server postavený na fd transportu
