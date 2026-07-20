# Plugin ABI

## Podporované: pure-LSL process ABI v1

`stdlib/plugin.lsl` poskytuje izolovanou plugin hranici bez shellu, libc nebo cizího loaderu:

```lsl
load plugin

value = plugin.request("/opt/my-plugin", "embed", {"text": "hello"})
```

Plugin je executable (může být přímo LSL-generovaný ELF). Host jej spustí přes `fork`/`execve`, předá jeden JSON argv request a zachytí jeden JSON stdout response.

Request:

```json
{"abi":1,"operation":"embed","payload":{"text":"hello"}}
```

Úspěšná response:

```json
{"abi":1,"ok":true,"value":{"vector":[1,2,3]}}
```

Chyba:

```json
{"abi":1,"ok":false,"error":"model unavailable"}
```

Host kontroluje ABI verzi, `ok`, prázdnou odpověď a propaguje `PluginError`. Hodnoty jsou omezené na JSON-compatible typy. Argumenty jsou oddělené argv; shellová interpolace se nepoužívá. Conformance je v `tests/plugin_process_*`.

Tato hranice je vhodná pro AI model servery, GPU workery a pluginy, kde isolation a jednoduché ownership převažují nad zero-copy.

## Plánované: in-process tensor/shared-object ABI

In-process zero-copy ABI zatím není podporované. Budoucí loader musí:

- zůstat implementovaný v LSL bez libc a cizího linkeru;
- verzovat layout, symbols a ownership;
- používat opaque tensor handles, shape/strides/dtype a explicitní device events;
- neodhalovat interní LSL heap layout;
- mít negative conformance pro version mismatch, lifetime a malformed ELF.

Process ABI se nepřejmenuje na zero-copy/native ABI a tato zbývající mezera není vydávána za hotovou.
