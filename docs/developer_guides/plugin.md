# Knihovna plugin

`load plugin`

Procesní plugin ABI v1 v čistém LSL: požadavky jako JSON na stdin,
odpovědi jako JSON na stdout — payloady a tajemství se neobjevují
v argv procesu.

## Funkce

```lsl
plugin.request(executable, operation, payload)
plugin.request_input(executable, operation, payload)   # alias
plugin.request_with_timeout(executable, operation, payload, seconds)
plugin.request_argv(executable, operation, payload)    # legacy transport
```

- `operation` — String s názvem operace.
- `payload` — libovolná JSON-encodable hodnota.
- `request` používá výchozí timeout 30 s; požadavek je omezen na 4 MiB.
- `request_argv` je zpětně kompatibilní transport přes argv, omezený
  `MAX_ARG_STRLEN` a nevhodný pro tajemství — nové integrace mají
  používat `request()`.

Worker čte JSON obálku `{"abi": 1, "operation": ..., "payload": ...}`
a na stdout vrací JSON odpověď.

## Příklad

```lsl
load plugin

result = plugin.request("/usr/lib/lsl/plugins/sum", "add", [1, 2, 3])
print result
```

## Chyby

- `PluginError` — neplatná operace, příliš velký požadavek, timeout,
  nevalidní odpověď workeru.

## Související stránky

- `lsl man json` — JSON obálka
- `lsl man process` — zachytávání s stdin
