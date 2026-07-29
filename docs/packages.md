# Instalace LSL knihoven

LSL 0.6 umí instalovat jednosouborové zdrojové moduly bez sudo:

```text
lsl install textkit
lsl update textkit
lsl install --config libraries.conf
lsl server
```

Výchozí endpoint je:

```text
https://luxos-registry-temp-2026.netlify.app/lsl
```

Pro jméno `textkit` klient stáhne `textkit.lsl` a `textkit.sha256`. Jméno musí
odpovídat `[a-z][a-z0-9_]{0,63}`, takže nemůže opustit cílový adresář ani vložit
volbu procesu.

## Instalační postup

Klient:

1. povolí HTTPS; nezabezpečené HTTP přijme pouze pro `127.0.0.1` nebo
   `localhost` při lokálním testu; diskless LuxOS bez curlu smí použít
   certificate-checking BusyBox wget pouze pro přesný dočasný Netlify origin;
2. přes přímé argv volání transportu přijme nejvýše 1 MiB zdroje a SHA-256 sidecar;
3. odmítne prázdný zdroj, NUL byte a neplatný 64znakový lowercase SHA-256;
4. zapíše skrytý staging soubor a ověří jeho hash přes `sha256sum`;
5. spustí `lsl compile` nad staging zdrojem, takže syntakticky nebo linkově
   neplatná knihovna se nenainstaluje;
6. nastaví mód `0644` a atomickým `mv` nahradí cílový soubor.

`lsl update NAME` nejdřív vyžaduje existující cílový modul a potom používá
stejné ověření, zkušební překlad a atomickou náhradu jako instalace.

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

Dočasný registr není podepsaný. HTTPS a hash pod stejným originem odhalí
poškození nebo nekonzistentní přenos, ale neprokazují identitu vydavatele proti
kompromitovanému registru. Produkční katalog bude potřebovat oddělené trust
roots, podpisy, expiraci a metadata závislostí.
