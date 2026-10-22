# GTK, GLib a D-Bus na Linuxu (cíl `linux-x86_64-gnu`)

Programy LSL jsou na Linuxu normálně statické a volají jen jádro. Cíl
`linux-x86_64-gnu` je dynamicky linkovaný PIE nad glibc: ld.so při startu
naváže systémové knihovny a program je volá přímo, bez mezivrstvy, přes
tabulku PLT/GOT. Moduly `glib`, `gio` a `gtk` tak dávají LSL totéž, co
dává Pythonu PyGObject - okna GTK 3, hlavní smyčku GLib a D-Bus - ale
s pamětí a startem programu v C: okno GTK startuje stejně rychle a se
stejnou pamětí jako tentýž program v C (~150 ms a 88 MB RSS pod Xvfb, z
toho LSL samo ~2 MB), zatímco Python + gi potřebuje ~240 ms a 112 MB.

```
lslc --target linux-x86_64-gnu program.lsl program
```

Runtime cíle používá glibc i pro vlákna (`pthread_create`) a TLS (`gs`),
takže knihovny mohou volat zpět do LSL z hlavní smyčky. Ostatní moduly
a jazyk jsou stejné jako na statickém cíli `linux-x86_64`.

## Knihovny: pragma `# lsl: link`

Modul, který volá sdílenou knihovnu, ji uvede v hlavičce:

```
# lsl: internal-abi
# lsl: link libgtk-3.so.0 libgobject-2.0.so.0 libglib-2.0.so.0
```

Překladač seznam knihoven sebere ze všech načtených modulů a LuxIR je
zapíše jako `DT_NEEDED` (vždy navíc `libc.so.6`). Linker při překladu
ověří, že každý použitý symbol některá z knihoven na stroji definuje;
chybějící funkce je chyba překladu, ne pád při startu. Volání knihovny
píše modul pomocí interního ABI (`__lsl_qbe_callN(__lsl_symbol("jméno"),
…)`), které je dostupné jen důvěryhodným modulům standardní knihovny.
Běžný program knihovny nevolá přímo, používá moduly níže.

## Modul `glib`

Hlavní smyčka a zdroje událostí:

| Funkce | Význam |
| --- | --- |
| `glib.main()`, `glib.main_quit()` | hlavní smyčka GLib (program bez GTK) |
| `glib.pump()` | jeden průchod čekajícími událostmi bez blokování |
| `glib.timeout_add(ms, f)`, `glib.timeout_add_seconds(s, f)` | `f()` opakovaně, dokud vrací `True`; vrací id zdroje |
| `glib.idle_add(f)` | `f()` při volné smyčce, dokud vrací `True` |
| `glib.source_remove(id)` | zrušení zdroje |
| `glib.unix_signal_add(signum, f)` | signál UNIXu (SIGUSR1 = 10, SIGUSR2 = 12, SIGTERM = 15) obsloužený v hlavní smyčce |
| `glib.spawn(argv)` | program na pozadí (hledá se v PATH); vrací PID, 0 když program není |
| `glib.spawn_watched(argv, f)` | totéž a po skončení `f(pid, status)`; `status` jako z `waitpid` (kód 3 = 768) |
| `glib.signal_connect(objekt, "signál", f, počet_argumentů)` | signál GObject; obsluha dostane argumenty signálu a nakonec instanci |

Pomůcky: `glib.markup_escape(text)`, `glib.find_program_in_path(jméno)`,
`glib.monotonic_time()` (µs), `glib.home_dir()`, `glib.user_config_dir()`,
`glib.user_runtime_dir()`, `glib.host_name()`, `glib.getpid()`,
`glib.set_prgname(jméno)`, `glib.set_application_name(jméno)`,
`glib.unbuffered()` (výstup `print` hned, pro záznamy démona).

Obsluhy jsou běžné funkce LSL. Chyba v obsluze program neukončí:
vypíše se na stderr jako `LSL callback error: …` a obsluha vrátí 0
(časovač tím skončí, signál je „neobsloužen“) - stejně jako výjimka v
obsluze PyGObject. Návratová hodnota obsluhy se knihovně předá jako
`gboolean`: `True`/`False`, celé číslo, nebo 0 pro `None`.

## Modul `gio`: D-Bus

Parametry a odpovědi jsou texty GVariant, program nepotřebuje typy GLib:

```
load gio
bus = gio.session_bus()                 # nebo gio.system_bus()
reply = gio.call(bus, "org.freedesktop.DBus", "/org/freedesktop/DBus",
                 "org.freedesktop.DBus", "GetNameOwner", "('org.freedesktop.DBus',)")
# reply == "('org.freedesktop.DBus',)"
```

| Funkce | Význam |
| --- | --- |
| `gio.call(bus, jméno, cesta, rozhraní, metoda, params)` | synchronní volání; `params` text n-tice (`"('a', uint32 1)"`) nebo `""`; vrací text odpovědi |
| `gio.get_property(bus, jméno, cesta, rozhraní, vlastnost)` | hodnota vlastnosti jako text |
| `gio.subscribe(bus, odesílatel, rozhraní, člen, cesta, f)` | odběr signálu; prázdný String = bez filtru; `f(sender, path, interface, signal, params)` |
| `gio.unsubscribe(bus, id)` | konec odběru |
| `gio.watch_name(bus, jméno, appeared, vanished)` | `appeared(jméno, vlastník)`, `vanished(jméno)` |
| `gio.own_name(bus, jméno)` | vlastní jméno na sběrnici |
| `gio.emit_signal(bus, cesta, rozhraní, signál, params)` | vyslání signálu |
| `gio.variant_parse(text)`, `gio.variant_text(v)`, `gio.variant_unref(v)` | přímá práce s GVariant |

Chyba sběrnice nebo metody je `DBusError` se zprávou GDBus
(`try: … else: print(last_error()) end`).

## Modul `gtk`: GTK 3

```
load gtk

function on_click(button):
    call gtk.label_set_text(label, "Kliknuto")
end

call gtk.init()
window = gtk.window_new("Ahoj")
box = gtk.box_new(gtk.VERTICAL, 8)
label = gtk.label_new("Zatím nic")
button = gtk.button_new("Klikni")
call gtk.box_pack_start(box, label, True, True, 0)
call gtk.box_pack_start(box, button, False, False, 0)
call gtk.container_add(window, box)
call gtk.connect(button, "clicked", on_click)
call gtk.connect(window, "delete-event", gtk.main_quit)
call gtk.widget_show_all(window)
call gtk.main()
```

Widgety jsou surové ukazatele GTK (`Int`); funkce modulu odpovídají
funkcím GTK bez předpony `gtk_`: `window_new(titulek)`,
`window_set_default_size`, `window_set_title`, `box_new(orientace,
mezera)`, `box_pack_start/end(box, dítě, expand, fill, padding)`,
`container_add`, `container_set_border_width`, `label_new`,
`label_set_text`, `label_set_markup`, `label_get_text`, `button_new(text)`,
`button_set_label`, `button_clicked`, `image_new_from_icon_name(jméno,
velikost)`, `entry_new`, `entry_get_text`, `entry_set_text`, `switch_new`,
`switch_get_active`, `switch_set_active`, `widget_show_all`, `widget_show`,
`widget_hide`, `widget_destroy`, `widget_set_size_request`,
`widget_set_halign/valign` (`gtk.ALIGN_*`), `widget_set_margin`,
`widget_set_sensitive`, `widget_set_tooltip`, `widget_set_name`,
`widget_add_class`, `widget_remove_class`, `css_load(css)` (styl pro
celou obrazovku), `main()`, `main_quit()`, `pump()`, `timeout_add`,
`idle_add`, `source_remove`, `version()`.

`gtk.connect(widget, "signál", f)`: obsluha dostane argumenty signálu
a nakonec widget, tedy `on_click(button)`, `on_draw(cr, area)`,
`on_key(event, window)`, `on_delete(event, window)`, `on_state(state,
switch)`. Argumenty jsou surová slova (ukazatele GTK, `gboolean`,
celá čísla).

Další funkce GTK se přidávají do `stdlib/gtk.lsl` jednou řádkou podle
stejného vzoru: `return __lsl_qbe_callN(__lsl_symbol("gtk_…"),
ptr(widget), cstr(text), …)`. Uvnitř modulu platí: argumenty z běžného
kódu a globální proměnné modulu jsou zabalené, před předáním do C je
rozbalí `ptr()`; parametry se nepřepisují (přepsaný parametr by se zabalil
znovu); text z C vrací `glib.from_c(adresa)` (kopie) nebo
`glib.take_c(adresa)` (navíc `g_free`).

## Testy

`tests/gnu/glib_conformance.lsl`, `gio_conformance.lsl` a
`gtk_conformance.lsl` běží jen na cíli `linux-x86_64-gnu`
(`tools/ci/target_tests.py`, `tests/cross_targets.py`); bez sběrnice
relace a displeje se spustí znovu pod `dbus-run-session` a `xvfb-run`,
bez těchto nástrojů vypíší `SKIP: …` a runner je přeskočí.
