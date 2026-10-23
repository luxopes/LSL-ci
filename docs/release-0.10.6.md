# Release LSL 0.10.6

Vydáno 23. 10. 2026. Backend LuxIR 0.4.3.

Doplňky pro plochu LuxOS v LSL (zadání LuxOS po 0.10.5): opravy tří chyb
cíle `linux-x86_64-gnu`, jazykové drobnosti a podstatně širší moduly
`glib`, `gio`, `gtk` plus nové moduly `cairo` a `pango`.

## Opravy

- `strip`/`objcopy` na programu cíle gnu už nedává „exec format error“:
  LuxIR 0.4.3 zapisuje hlavičky sekcí `.interp`, `.got`, `.dynsym`,
  `.dynstr`, `.hash`, `.rela.dyn` a `.dynamic`, takže BFD interpret a tabulky
  ld.so zachová (makepkg stripuje implicitně).
- `readfile`/`readbytes` čtou soubory bez známé velikosti (`/proc/*/cmdline`,
  `/proc/*/status`, sysfs, roury): dřív prázdný text nebo `FileError`, teď se
  čte po blocích až do konce.
- Program cíle gnu startuje v locale „C“: `glib.setlocale()` nastaví jazyk a
  formáty podle prostředí (`gtk.init()` to dělá sama).

## Jazyk a vestavěné funkce

- `text.strip(znaky)`, `lstrip(znaky)`, `rstrip(znaky)` odstraní uvedené
  znaky; `text.find(hledané, od)` hledá od pozice (záporná od konce).
- `String.find`, `split` a `replace` hledají v runtime (těsná smyčka nad
  bajty): 160 kB prohledá za desítky µs místo 0,7 ms.
- `eprint(hodnota)` zapíše `String(hodnota)` a nový řádek na stderr
  (čekající výstup `print` nejdřív odejde); `listdir(cesta)` vrátí jména
  položek adresáře (dřív jen `__lsl_list_directory` v `unsafe`).

## Moduly cíle `linux-x86_64-gnu`

- `glib`: `setlocale`, `date_time_format`, `format_date`, `format_unix`,
  `local_date`, `days_in_month`, `weekday`, `first_weekday`, `kill`, `exec`,
  `spawn_quiet`, `timeout_add_full`, `timeout_add_seconds_full`,
  `unix_signal_add_full`, `user_cache_dir`, `user_data_dir`, `getenv`,
  `filename_from_uri`, `filename_to_uri`, `shell_quote`, `format_size`.
- `gio`: hodnoty LSL místo textu GVariant (`call_values`,
  `get_property_value`, `get_all_properties`, `set_property`,
  `subscribe_values`, `emit_values`, `variant_to_value`, `value_to_variant`
  podle podpisu včetně `a{sv}`), `call_timeout`, vlastní objekt na sběrnici
  (`register_object`, `return_value`, `return_error`, `unregister_object`;
  agent BlueZ), sledování souborů (`file_monitor`, `file_monitor_cancel`).
- `gtk`: mřížka, posuvníky a číselníky (Float), progress/level bar,
  pixbufy a obrázky, vzhled tlačítek, přepínače, combo, okna bez dekorací a
  jejich typ/poloha/vrstva, RGBA visual, monitory a pracovní plocha,
  GtkSettings přes `g_object_get/set`, čtení událostí klávesnice a myši,
  stavové příznaky, barva z motivu, kurzor, popisky s výpustkou a
  zarovnáním, vstupní pole, posuvné okno, event box, drawing area, fixed,
  overlay, revealer, list box, kalendář, CSS načíst i odebrat.
- Nové moduly `cairo` (cesty, výplně, přechody, text, obrázky PNG) a `pango`
  (rozvržení textu s písmem systému, zalamování, výpustka, značky).
- Interní ABI: argument se statickým typem `Float` jde do C jako `double`
  (`__lsl_qbe_fcallN` vrací `double`), `Float(x)` má vždy statický typ
  `Float`; most zpětných volání `lsl_arch_callback_u8` pro
  `GDBusInterfaceMethodCallFunc`.

## Testy

Nové `tests/gnu/glib_more_conformance.lsl`, `gio_values_conformance.lsl`
(gdbus z jiného procesu, soubory), `gtk_widgets_conformance.lsl` (Xvfb),
`cairo_conformance.lsl` (bez displeje); `tests/dyn_check.py` LuxIR spouští
dynamické programy i po `strip`.
