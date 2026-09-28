# Knihovna unixsock

`load unixsock`

Unix-domain sockety s předáváním deskriptorů souborů, v čistém LSL nad
surovým syscall builtinem. To je přesně to, co potřebuje display server
a co běžný fd obal nevyjádří: klienti předávají sdílené bufferové
deskriptory v řídicí zprávě `sendmsg`/`recvmsg` (`SCM_RIGHTS`).

## Server a klient

```lsl
unixsock.socket_path(path)               # ověří a vrátí cestu
unixsock.listen_unix(path, backlog)      # naslouchající socket
unixsock.accept_unix(server)             # přijaté spojení
fd.connect_unix(path)                    # klientské připojení (knihovna fd)
```

## Přenos dat a deskriptorů

```lsl
unixsock.send_bytes(handle, payload, count)
unixsock.send_fd(handle, payload, count, descriptor)
unixsock.send_from(handle, payload, offset, count)
unixsock.send_from_fd(handle, payload, offset, count, descriptor)
unixsock.recv_fds(handle, payload, count, fds)
```

`payload` je ByteArray; předané deskriptory se vrací v `fds`.

## Pomocné primitivy

```lsl
unixsock.memfd(name, size)        # anonymní sdílená paměť
unixsock.pipe_nonblock()          # neblokující roura
unixsock.set_nonblocking(handle)
unixsock.chmod_path(path, mode)   unixsock.chown_path(path, user, group)
```

## Chyby

- `UnixSocketError` — neplatná cesta, chyba syscallu.

## Související stránky

- `lsl man fd` — deskriptorové I/O
- `lsl man httpserver` — TCP server
