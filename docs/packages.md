# Instalace a původ LSL knihoven

LSL 0.7 umí instalovat jednosouborové zdrojové moduly bez sudo a uchovává
jejich ověřený původ:

```text
lsl install textkit
lsl update textkit
lsl install --config libraries.conf
lsl origin
lsl origin textkit
```

Výchozí endpoint je:

```text
https://lsl.lux-ai.cz/packages
```

Pro jméno `textkit` klient stáhne `textkit.lsl` a `textkit.sha256`. Jméno musí
odpovídat `[a-z][a-z0-9_]{0,63}`, takže nemůže opustit cílový adresář ani vložit
volbu procesu.

## Instalační postup

Klient:

1. povolí HTTPS; nezabezpečené HTTP přijme pouze pro číselný loopback
   `127.0.0.1` při lokálním testu (nikoli přes měnitelný DNS/NSS název); diskless LuxOS bez curlu smí použít
   certificate-checking BusyBox wget pouze pro přesný produkční endpoint;
2. přes přímé argv volání transportu přijme nejvýše 1 MiB zdroje a SHA-256 sidecar;
3. odmítne prázdný zdroj, NUL byte a neplatný 64znakový lowercase SHA-256;
4. zapíše skrytý staging soubor a ověří jeho hash přes `sha256sum`;
5. spustí `lsl compile` nad staging zdrojem, takže syntakticky nebo linkově
   neplatná knihovna se nenainstaluje;
6. vytvoří přísně parsovaný `NAME.lsl.origin` sidecar se jménem, normalizovaným
   registry originem, přesnou source URL a ověřeným SHA-256;
7. nastaví mód `0644`, vezme per-package kernel lock a atomickým `mv` nahradí
   provenance a zdroj; lock soubor nesmí být symlink ani speciální soubor.

`lsl origin` bez jména vypíše aktivní registry URL. `lsl origin NAME` pod
stejným zámkem přečte sidecar, znovu spočítá SHA-256 instalovaného zdroje a až
po shodě vypíše pole `name`, `origin`, `source` a `sha256`; síť přitom
nekontaktuje. Ruční změna zdroje nebo přerušený dvoufázový commit proto skončí
chybou integrity. Balíček instalovaný starší verzí sidecar nemá a musí se
nejdřív aktualizovat pomocí LSL 0.7.

`lsl update NAME` nejdřív vyžaduje existující cílový modul a potom používá
stejné ověření, zkušební překlad a atomickou náhradu jako instalace.
Bez názvu knihovny `lsl update` spouští [podepsaný updater samotného LSL](updates.md).

`lsl install --config FILE` načte nejvýše 64 KiB a 256 položek. Soubor používá
LF a tisknutelnou ASCII podmnožinu UTF-8, obsahuje přesně jeden validní název na
řádek a může obsahovat prázdné řádky nebo komentáře začínající `#`. Duplicitní či
neplatná položka se odmítne ještě před prvním downloadem. Například:

```text
# Development libraries
textkit
statkit
```

Cíl je:

```text
~/.local/lib/lsl/stdlib/NAME.lsl
```

Zdroj vedle hlavního programu, compiler interní moduly a built-in/system
`stdlib` mají před uživatelským adresářem přednost. Balíček proto nemůže
přepsáním například `time.lsl` zastínit standardní modul.

## Jiný registr

Základní URL lze pro jeden proces změnit:

```text
LSL_REGISTRY=https://example.org/lsl lsl install mylib
```

Vzdálená URL musí být HTTPS a nesmí obsahovat whitespace, řídicí znaky, query
ani fragment. Formát v1 je záměrně jediný `.lsl` soubor bez instalačních skriptů
a bez dependency resolveru.

Registr knihoven v1 není podepsaný. HTTPS a hash pod stejným originem odhalí
poškození nebo nekonzistentní přenos, ale neprokazují identitu vydavatele proti
kompromitovanému registru. Důvěra stojí na HTTPS a řízeném Forgejo/deploy řetězci.
Ed25519 podpisy updateru LSL se nevztahují na zdrojové knihovny.
