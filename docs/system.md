# Správa balíčků LuxOS

Modul `system` je běžná imperativní LSL knihovna pro LuxOS a Debian. Není to
nový konfigurační jazyk: lze používat proměnné, funkce, podmínky a smyčky stejně
jako v každém jiném `.lsl` programu.

```lsl
load system

call system.install("git")
call system.update("curl")
call system.remove("old-package")
```

Program se spouští normálně, nikoli přes čistý `lsl config` evaluator:

```text
./lsl machine.lsl
```

Tyto funkce skutečně mění hostitelský systém. Program proto spusťte s právy,
která vyžaduje Lux nebo apt. Modul automaticky nepoužívá `sudo`.

## Volba správce balíčků

Pro každou operaci modul postupuje takto:

1. pokud je v `PATH` příkaz `lux`, spustí `lux install|update|remove NAME`;
2. při statusu 0 vrátí `"lux"`;
3. při chybě nebo chybějícím Lux spustí `apt`, případně `apt-get`;
4. při úspěchu vrátí `"apt"`, jinak vyvolá `PackageError`.

Apt příkazy jsou neinteraktivní:

```text
apt install -y -- NAME
apt install -y --only-upgrade -- NAME
apt remove -y -- NAME
```

Nenulový Lux status vždy znamená fallback na apt. Pokud chcete chybu Lux řešit
jinak, použijte explicitní `install_with`, `update_with` nebo `remove_with` a
předejte `None` místo apt příkazu.

## Běžné LSL konstrukce

Více balíčků nepotřebuje zvláštní deklarativní strukturu:

```lsl
load system

packages = ["git", "curl", "ca-certificates"]
for package in packages:
    backend = system.install(package)
    print package, "installed by", backend
end
```

Podmínky fungují stejně:

```lsl
if exists("/etc/debian_version"):
    call system.install("build-essential")
end
```

## API

- `system.install(name)` — Lux install, potom apt install;
- `system.update(name)` — Lux update, potom apt `--only-upgrade`;
- `system.remove(name)` — Lux remove, potom apt remove;
- `system.install_with(name, lux_command, apt_command)`;
- `system.update_with(name, lux_command, apt_command)`;
- `system.remove_with(name, lux_command, apt_command)`;
- `system.detected_lux()` a `system.detected_apt()` — nalezená cesta nebo `None`.

Explicitní varianty jsou vhodné pro custom umístění nástrojů, chroot a testy:

```lsl
call system.install_with("editor", "/opt/lux/bin/lux", "/usr/bin/apt")
```

Jméno balíčku musí být neprázdný String bez whitespace a nesmí začínat `-`.
Všechny příkazy se spouštějí přímým `execve` s odděleným argv; nepoužívá se shell ani interpolace.
`system` je ambientní capability a v čistém `lsl config` režimu je zakázán.
