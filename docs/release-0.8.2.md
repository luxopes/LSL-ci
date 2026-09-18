# LSL 0.8.2

- `safe`/`try` zachytí neznámé volání či proměnnou, neexistující metodu
  a podporované statické chyby typů/argumentů. Stejné chyby v tělech funkcí
  se předávají volajícímu. Mimo ochranný blok na nejvyšší úrovni zůstává
  statická diagnostika. Syntaxe, importy a bezpečnostní pravidla se nepotlačují.
- Opravený zásobník po selhání uvnitř seznamu, argumentů či jiného složeného
  výrazu. Obnova běží pouze na chybové cestě. Regresní test kontroluje,
  že úspěšné přímé volání v `safe` nemá další instrukce ani kontroly.
- `last_error()` je použitelný String i pro nativní chyby; například
  `last_error().startswith("IndexError:")` funguje.
- Runtime chyby jsou barevné; compiler zvýrazňuje cestu, caret a nápovědu.
  `NO_COLOR` má přednost, `FORCE_COLOR=1/0` barvy vynutí/zakáže. Bez něj
  pipes a `TERM=dumb` zůstávají prostým textem. Barvy se řeší až při chybě.
- Fontová tabulka `gfx` je rozdělená pod parserový limit, beze změny glyphů.
  Test ověřuje rozměry tabulky i skutečné vykreslení české diakritiky.
- `gfx`, `x11`, `wayland`, `display`, `input`, `ui`, `css` nejsou v základní
  instalaci. Instalují se pomocí `lsl install NAME` z oficiálního registru.
  Závislosti `ui -> gfx/input`, `display -> x11/input`, `css -> gfx` jsou
  součástí ověřovaného zdroje a instalují se automaticky, bez instalačních
  skriptů. Zdrojové vývojové kopie jsou v `extensions/`.
- `lsl list/check` rozlišuje základní a doinstalované balíčky i ve sdíleném
  adresáři starší instalace do `~/.local`, bez duplicitních záznamů.

```lsl
safe:
    call nonexist()
end
print last_error()
print "Pokračuji"
```

`safe` není transakce ani sandbox: nevrací zpět I/O či změny dat, nezachytává
fatální vyčerpání alokátoru, signály OS ani `exit()`. Není přidán JIT.
Základní AOT compiler a runtime zůstávají pouze LSL.

Po aktualizaci z 0.8.1 nainstalujte používané grafické moduly explicitně:
`lsl install ui`, `lsl install display`, případně `lsl install css`.
Samostatné dříve zkompilované ELF zůstávají funkční. Updater ověřuje podpis
a hash jako dříve a uchovává předchozí generaci pro rollback.
