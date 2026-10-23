# Release LSL 0.10.4

GTK 3, GLib a D-Bus na Linuxu: nový cíl `linux-x86_64-gnu` překládá
programy nad glibc, které volají sdílené knihovny systému přímo, s pamětí
a startem programu jako v C. Vzniklo pro desktop LuxOS, kde LSL nahrazuje
Python; manuál je ve stránce `lsl man gtk`.

## Změny

- Cíl `linux-x86_64-gnu`: dynamicky linkovaný PIE nad glibc (ld.so,
  PLT/GOT, `BIND_NOW`, `DT_NEEDED`), který linkuje LuxIR 0.4.1 sám; vlákna
  jsou pthread a TLS glibc, takže knihovny volají zpět do LSL z hlavní
  smyčky. Modul uvede knihovny pragmatem `# lsl: link libX.so.N …`; každý
  import se ověří proti knihovnám hostitele, chybějící funkce je chyba
  překladu, ne pád při startu. Statické programy a ostatní cíle beze změny.
- Modul `glib`: hlavní smyčka, `timeout_add`, `idle_add`, signály UNIXu,
  `spawn`/`spawn_watched` s hlídáním potomka, signály GObject
  (`signal_connect`), převody textu z C, adresáře XDG.
- Modul `gio`: D-Bus na session i system bus — volání metod, vlastnosti,
  odběr signálů, sledování jmen (`watch_name`), vlastnictví jména
  (`own_name`), vysílání signálů; parametry a odpovědi jako text GVariant,
  chyby jako `DBusError`.
- Modul `gtk`: okna GTK 3, boxy, labely, tlačítka, entry, přepínače, ikony,
  CSS, obsluhy signálů (`clicked`, `draw`, `delete-event`, `state-set`, …).
  Chyba v obsluze program neshodí: vypíše se `LSL callback error: …` na
  stderr a smyčka běží dál.
- `lsl list` a `help()` znají `gtk`, `glib` a `gio`; `lsl man gtk` popisuje
  API i pravidla psaní vlastních vazeb na knihovny C.
- Výkon: okno GTK v LSL startuje stejně rychle a se stejnou pamětí jako
  tentýž program v C (~150 ms a 88 MB RSS pod Xvfb, z toho LSL samo ~2 MB);
  Python s PyGObject potřebuje ~240 ms a 112 MB. Démon s hlavní smyčkou,
  D-Bus a signály: 43 MB Pss místo 60 MB v Pythonu, polovina času CPU.
- LuxIR 0.4.1: `luxir -l` se vstupem `.libs` vytvoří dynamický PIE pro
  x86-64; generování kódu beze změny.

## Ověření

- Testy cíle `tests/gnu/{glib,gio,gtk}_conformance.lsl` (hlavní smyčka,
  časovače, signály UNIXu, spouštění procesů, D-Bus přes
  `dbus-run-session`, okno GTK pod `xvfb-run`) v sadě cílů i v CI na
  Ubuntu 24.04; bundle `linux-x86_64-gnu` překládá a spouští celou sadu
  samostatných testů (110 z 110) jako statický cíl.
- LuxIR `make check-ld`: `tests/run` slinkované proti glibc hostitele,
  spuštěné a porovnané s očekávaným výstupem, smlouva obrazu (ET_DYN,
  `PT_INTERP`, `PT_DYNAMIC`, `BIND_NOW`, žádný RWX segment).
