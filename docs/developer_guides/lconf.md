# Knihovna lconf

`load lconf`

Přísný kodek manifestů závislostí pro `.lux` archivy balíčků. Formát je
řádkový, jeden klíč na řádek, hodnoty oddělené čárkou.

## Formát

```text
apt: curl, git
lux: myapp
lsl: textkit
```

## Funkce

### lconf.decode(text)

Dekóduje manifest na Dictionary:

```lsl
{"apt": ["curl", "git"], "lux": ["myapp"], "lsl": ["textkit"]}
```

### lconf.encode(manifest)

Zakóduje Dictionary zpět na text (jeden klíč na řádek, každá hodnota
zvlášť, deterministicky).

### lconf.parse(text, path)

Jako `decode`, ale s `path` pro chybová hlášení s číslem řádku.

### lconf.valid_dependency(name)

Ověří jméno závislosti; vrací `True`/`False`.

## Příklad

```lsl
load lconf

text = "apt: curl, git\nlux: myapp\nlsl: textkit\n"
deps = lconf.decode(text)
print deps["apt"]            # ["curl", "git"]
print lconf.encode(deps)
```

## Chyby

- `LconfError` — neplatná syntaxe, neznámý klíč, neplatné jméno
  závislosti.

## Související stránky

- `lsl man config` — konfigurace
- `lsl man system` — instalace balíčků podle manifestu
