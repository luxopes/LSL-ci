# Knihovna system

`load system`

Imperativní pomocníci pro správu balíčků v LuxOS a Debianu. Každý příkaz
je argv, nikdy shell. Instalace detekuje dostupný správce balíčků
(`lux`/`apt`) a použije ten správný.

## Funkce

```lsl
system.install(package)   system.update(package)   system.remove(package)
```

Detekují správce balíčků a provedou akci. `package` je String s názvem
balíčku; validuje se proti znakům `[A-Za-z0-9._+-]` (bez cest, voleb
a mezer).

```lsl
system.install_with(package, lux_command, apt_command)
system.update_with(package, lux_command, apt_command)
system.remove_with(package, lux_command, apt_command)
```

Explicitní volba správců; `None` znamená nedostupný správce.

```lsl
system.detected_lux()    # cesta k lux, nebo None
system.detected_apt()    # cesta k apt, nebo None
system.required_tool(name)  # cesta k nástroji, jinak SystemError
```

## Validace vstupů

- `system.validate_package(package)` — název balíčku.
- `system.validate_name(value, label)` — obecný identifikátor.
- `system.validate_account_name(value, label)` /
  `system.validate_account_list(values, label)` — uživatelské účty.

## Chyby

- `SystemError` — neplatný vstup, chybějící nástroj nebo selhání příkazu.

## Související stránky

- `lsl man luxos` — deklarativní konfigurace systému
- `lsl man os` — spouštění programů
- `lsl man process` — zachytávání výstupů
