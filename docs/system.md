# Správa LuxOS z běžného LSL

Modul `system` je imperativní pure-LSL knihovna pro LuxOS a Debian. Není to nový
konfigurační jazyk: konfigurace stroje je normální `.lsl` program s proměnnými,
funkcemi, podmínkami a smyčkami.

```lsl
load system

call system.refresh()
for package in ["git", "curl"]:
    call system.install(package)
end
call system.enable_service("ssh.service")
```

Spouští se normálně:

```text
./lsl machine.lsl
```

Funkce skutečně mění hostitelský systém. Program spusťte s právy požadovanými
Lux, apt, systemd a účtovými nástroji. Modul automaticky nepoužívá `sudo`.
Všechny procesy používají přímý `execve` s odděleným argv; shell ani interpolace
se nespouští.

## Balíčky a repozitáře

```lsl
call system.refresh()
backend = system.install("git")
call system.update("curl")
call system.remove("old-package")
print backend  # "lux" nebo "apt"
```

`refresh()` nyní provádí `apt update`. Pro package operace modul hledá `lux`,
potom `apt` a nakonec `apt-get`:

1. spustí `lux install|update|remove NAME`, pokud je Lux dostupný;
2. status 0 vrátí `"lux"`;
3. nenulový status použije apt;
4. chyba posledního backendu vyvolá `PackageError`.

Apt příkazy jsou neinteraktivní:

```text
apt update
apt install -y -- NAME
apt install -y --only-upgrade -- NAME
apt remove -y -- NAME
```

Samostatný Lux package katalog a příkaz pro bezpečné rozlišení „balíček
neexistuje“ od síťové chyby budou doplněny společně se správcem Lux balíčků.
Do té doby každý nenulový Lux status znamená apt fallback.

## Služby

```lsl
call system.enable_service("ssh.service")
call system.restart_service("ssh.service")
print system.service_active("ssh.service")
call system.disable_service("old.service")
```

Enable/disable používá `systemctl ... --now`. Neaktivní služba vrací `False`;
neočekávaná chyba systemctl vyvolá `SystemError`.

## Identita systému

```lsl
call system.set_hostname("luxos")
call system.set_timezone("Europe/Prague")
call system.set_locale("C.UTF-8")
```

Funkce používají `hostnamectl`, `timedatectl` a `localectl`.

## Skupiny a uživatelé

```lsl
call system.ensure_group("developers")
created = system.ensure_user("ada", "/usr/local/bin/luxsh", ["developers", "sudo"])
print created
```

`ensure_group` a `ensure_user` jsou idempotentní. Existující účet se aktualizuje
přes `usermod`, nový vznikne přes `useradd --create-home`. Funkce vrací `True`,
pokud objekt vytvořila, jinak `False`.

Destruktivní operace jsou explicitní:

```lsl
call system.remove_user("obsolete")  # userdel --remove
call system.remove_group("obsolete")
```

## Adresáře a atomické soubory

```lsl
call system.ensure_directory("/etc/my-service", "0750")
call system.write_file("/etc/my-service/config", "port=8080\n", "0640")
call system.write_owned_file("/etc/my-service/secret", "value\n", "0600", "root", "root")
```

`write_file` vytvoří bezpečný dočasný soubor přes `mktemp` ve stejném adresáři,
nastaví režim a případného vlastníka a posledním `mv` provede atomickou rename.
Cesty musí být absolutní, nesmí obsahovat `..`; file/directory operace záměrně
odmítají `/`. `remove_file(path)` maže pouze explicitně uvedený soubor.

## Mounty

```lsl
mounted = system.ensure_mount(
    "/dev/vdb1",
    "/srv/data",
    "ext4",
    ["rw", "noatime"]
)
print mounted
call system.unmount("/srv/data")
```

`ensure_mount` nejprve použije `mountpoint -q`. Vrací `False`, pokud už je cíl
mountpoint, jinak vytvoří adresář, provede mount a vrátí `True`.

## LuxOS generace a rollback

Modul obaluje existující LuxOS aktivátor:

```lsl
call system.check_system("/etc/luxos/system.lsl")
call system.dry_run_system("/etc/luxos/system.lsl")
call system.apply_system("/etc/luxos/system.lsl")
print system.lux_status()
print system.generations()
call system.rollback("20260717T120000Z-abcd1234")
```

`lux apply` používá existující LuxOS lock a generaci; `rollback` znovu aktivuje
vybranou generaci. Přímé jednotlivé imperativní operace (`install`,
`write_file`, `ensure_user` atd.) nejsou vydávány za jednu atomickou transakci:
APT ani systemd takovou transakci neposkytují. Pro rollback celého stroje je
hranice transakce `apply_system`/LuxOS generace.

## Explicitní nástroje

Každá oblast má variantu s explicitní cestou, například:

```lsl
call system.install_with("editor", "/opt/lux/bin/lux", "/usr/bin/apt")
call system.enable_service_with("ssh.service", "/usr/bin/systemctl")
```

Další varianty jsou `refresh_with`, `update_with`, `remove_with`,
`service_active_with`, `set_hostname_with`, `set_timezone_with`,
`set_locale_with`, `ensure_group_with`, `ensure_user_with`, `write_file_with`, `ensure_directory_with`, `ensure_mount_with`,
`check_system_with`, `apply_system_with`, `generations_with` a `rollback_with`.
Jsou určené pro custom umístění, chroot a hermetické testy.

Jména balíčků a služeb nesmí být prázdná, obsahovat whitespace ani začínat `-`.
Unix users/groups navíc používají lowercase `[a-z_][a-z0-9_-]*` a nejvýše 32
znaků. File modes jsou tři nebo čtyři octal digits. `system` je
ambientní capability a v čistém `lsl config` režimu je zakázán.
