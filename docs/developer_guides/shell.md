# Knihovna shell 1.1.0 — běh příkazů s potlačeným prostředím

`load shell`

Spouští příkazy přes `/bin/sh -c` a vrací strukturovaný výsledek. Modul `os`
záměrně shell nikdy nespouští (pouze execve bez rour a přeposílání), takže
`shell` je jeho explicitní, ohraničený protějšek: pipes, smyčky, přesměrování
i rozšiřování proměnných fungují, ale běží v čistém prostředí bez zděděných
proměnných. Balíček je určen pro LSL 0.8.9 nebo novější.

```bash
lsl install shell      # první instalace
lsl update shell       # další aktualizace
```

## Základní použití

```lsl
load shell

result = shell.capture_result("printf out; printf err >&2; exit 3")
printl "stdout: {result[\"stdout\"]}"
printl "stderr: {result[\"stderr\"]}"
printl "status: {result[\"status\"]}, ok: {result[\"ok\"]}"
```

`capture_result` vrací Dictionary `{stdout, stderr, status, ok}`. Pro běžné
případy stačí kratší varianty:

```lsl
load shell

status = shell.run("true")               # Int: exit status
out = shell.capture("ls / | wc -l")      # String: stdout včetně konců řádků
printl "true vrátilo {status}; výpis má {out.strip()} řádků"
```

## Roury a konstrukce shellu

```lsl
load shell

# Pipes, smyčky, přesměrování i &&/|| fungují jako v běžném shellu.
first = shell.capture("echo a b c | tr ' ' '\\n' | sort | head -1")
loop_out = shell.capture("for i in 1 2 3; do printf $i; done")
both = shell.run("true && false")
either = shell.run("false || true")
printl "První řádek: {first.strip()}"
printl "Smyčka: {loop_out}"
printl "&&: {both}, ||: {either}"
```

## Timeout

```lsl
load shell

# sleep 5 by trval pět sekund; timeout 1 ho přeruší statusem 124.
status = shell.run_t("sleep 5", 1)
printl "Přerušeno statusem {status}"
```

Bez `_t` varianty se timeout nehlídá. Timeout je Int 1–86400 sekund.

## Bezpečné skládání argumentů: quote

```lsl
load shell

name = "$HOME; rm -rf /tmp/test"         # nedůvěryhodný vstup
quoted = shell.quote(name)               # '$HOME; rm -rf /tmp/test'
printl shell.capture("printf %s " + quoted)   # vypíše vstup doslova, nic nespustí

files = ["a b.txt", "it's.txt"]
printl shell.capture("wc -l " + shell.quote_all(files))
```

`quote` obalí hodnotu do jednoduchých uvozovek a vnitřní apostrof zapíše jako
`'\''`, takže shell hodnotu interpretuje doslova. `quote_all` uvozené hodnoty
spojí mezerou. Nikdy neskládejte nedůvěryhodný vstup do příkazu bez `quote`.

## Bezpečnost a omezení

Příkaz se spouští přes `env -i` s jedinými proměnnými `HOME` a `PATH`
(`/usr/local/bin:/usr/bin:/bin`); `TERM`, `IFS` a zbytek prostředí procesu
se nepředává. Samotný sh si nastavuje už jen `PWD` podle pracovního adresáře.

- Příkaz musí být neprázdný String bez NUL, nejvýše 65536 znaků.
- Timeout musí být Int 1–86400; bez timeoutu se příkaz neomezuje.
- Všechny kontroly hlásí `ShellError`, zachytitelný přes `try`/`else`.
- Žádný příkaz se nespouští v `lsl config` režimu ani v sandboxu bez
  příslušných oprávnění.

## Agent s nástrojem shell

Spojení s AI knihovnou `aikit`: model dostane nástroj `run_bash`, jehož
výsledek vrací klientovi přes roli `tool`:

```lsl
load aikit as ai
load shell
load json
load env

tools = [
    {"type": "function", "function": {
        "name": "run_bash",
        "description": "Spustí příkaz v omezeném shellu a vrátí stdout, stderr a status.",
        "parameters": {
            "type": "object",
            "properties": {"command": {"type": "string"}},
            "required": ["command"]
        }
    }}
]

function run_bash(command):
    result = shell.capture_result_t(command, 10)
    return json.encode({"stdout": result["stdout"], "stderr": result["stderr"],
                        "status": result["status"], "ok": result["ok"]})
end

endpoint = "https://api.lux-ai.cz/v1/chat/completions"
token = env.require("LUX_AI_API")
model = env.get("LUX_AI_MODEL", "flash")
messages = [{"role": "user", "content": "Kolik souborů je v /etc? Použij nástroj."}]

response = ai.request(endpoint, token, model, messages,
                      {"tools": tools, "tool_choice": "auto", "timeout": 120})
calls = ai.tool_calls(response)
if len(calls) > 0:
    assistant_calls = []
    for call in calls:
        assistant_calls.append({"id": call["id"], "type": "function",
                                "function": {"name": call["name"],
                                             "arguments": call["arguments"]}})
    end
    messages.append({"role": "assistant", "content": None, "tool_calls": assistant_calls})
    for call in calls:
        args = json.decode(call["arguments"])
        messages.append(ai.tool_message(call["id"], call["name"],
                                        run_bash(args["command"])))
    end
    printl "Odpověď: {ai.content(ai.request(endpoint, token, model, messages, {\"tools\": tools, \"timeout\": 120}))}"
else:
    printl "Odpověď: {ai.content(response)}"
end
```

Model navrhuje příkazy, ale nespouští je sám: běží přes `shell` s timeoutem
a v čistém prostředí. Před nasazením do produkce omezte nástroj na důvěryhodné
příkazy nebo sandbox — plný shell je silný nástroj.

## Funkce

| Volání | Výsledek |
|---|---|
| `run(command)` | Int — exit status; stdio se zachytí. |
| `capture(command)` | String — stdout. |
| `capture_result(command)` | Dictionary `{stdout, stderr, status, ok}`. |
| `run_t(command, timeout)` / `capture_t` / `capture_result_t` | Stejné s timeoutem v sekundách; vypršení vrací status 124. |
| `quote(value)` | String — jeden shell argument uvozený proti interpretaci. |
| `quote_all(values)` | String — uvozené hodnoty spojené mezerou. |
| `help()` / `version` | Krátká nápověda / verze knihovny. |
