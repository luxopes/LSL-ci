# Knihovna json

`load json`

Čistě LSL JSON kodek bez libc a cizího runtime. Kodér i dekodér jsou
přísné: dekodér odmítá koncová data, nesprávné escapy a přetečení,
vstup je omezen na 4 MiB.

## Funkce

### json.encode(value)

Zakóduje hodnotu do JSON textu. Podporuje `None`, `Bool`, `Int`, `Float`,
`String`, `List`, `Tuple` a `Dictionary` (klíče musí být String).

### json.decode(text)

Dekóduje JSON text na nativní hodnoty LSL (objekty na Dictionary, pole na
List, čísla na Int/Float). Přijme nejvýše 4 MiB.

### json.pretty(value)

Zakódovaný JSON s odsazením, vhodný pro protokoly a čitelný výstup.

## Příklad

```lsl
load json

data = {"name": "LSL", "releases": [{"version": "0.8.8"}]}
text = json.encode(data)
print text
print json.decode(text)["releases"][0]["version"]

try:
    json.decode("{invalid")
else:
    print "JSON chyba:", last_error()   # JsonError
end
```

## Chyby

- `JsonError` — neplatný vstup nebo výstup (přísné parsování, limity).

## Související stránky

- `lsl man requests` — `Response.json()`
- `lsl man lconf` — manifesty závislostí
- `lsl man plugin` — procesní plugin ABI s JSON zprávami
