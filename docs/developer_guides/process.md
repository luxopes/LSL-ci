# Knihovna process

`load process`

Strukturované procesní pomocníky nad syscallovým runtime: oddělený
stdout/stderr, vstup na stdin a streamovaný výstup. Stejně jako `os`
nikdy nepoužívá shell — jen přímý argv.

## Funkce

```lsl
process.capture_result(executable, arguments)
process.capture_input_result(executable, arguments, input_text)
process.capture_input_stream_result(executable, arguments, input_text, on_chunk)
```

Všechny vracejí:

```lsl
{"stdout": String, "stderr": String, "status": Int, "ok": Bool}
```

- `capture_input_result` pošle programu `input_text` na stdin.
- `capture_input_stream_result` navíc volá `on_chunk(text)` s každým
  kusem stdout (bez deadlocku díky memfd transportu).

```lsl
process.check(executable, arguments) → stdout
process.check_input(executable, arguments, input_text) → stdout
process.check_input_stream(executable, arguments, input_text, on_chunk) → stdout
```

Kontrolní varianty: při nenulovém statusu vyhodí `ProcessError`, jinak
vrátí stdout.

## Příklad

```lsl
load process

result = process.capture_input_result("/usr/bin/cat", [], "hello")
print result["ok"], result["stdout"]   # True hello
```

## Chyby

- `ProcessError` — nenulový exit status u `check*`.

## Související stránky

- `lsl man os` — jednoduché spouštění a PATH lookup
- `lsl man plugin` — JSON plugin ABI
