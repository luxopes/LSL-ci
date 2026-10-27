# GTK, GLib, D-Bus a cairo na Linuxu (cíl `linux-x86_64-gnu`)

Programy LSL jsou na Linuxu normálně statické a volají jen jádro. Cíl
`linux-x86_64-gnu` je dynamicky linkovaný PIE nad glibc: ld.so při startu
naváže systémové knihovny a program je volá přímo, bez mezivrstvy, přes
tabulku PLT/GOT. Moduly `glib`, `gio`, `gtk`, `cairo` a `pango` tak dávají LSL totéž, co
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

Pravidla volání C v interním ABI:

- `__lsl_qbe_callN` vrací celé slovo `rax`. Funkce s návratovým typem C
  `int` (`open`, `poll`, většina OpenSSL) definuje jen spodních 32 bitů,
  proto ji volejte `__lsl_qbe_icallN`, které výsledek znaménkově rozšíří
  (`-1` zůstane `-1`, ne `4294967295`); jednotlivou hodnotu rozšíří
  `__lsl_qbe_s32(x)`.
- Argument se statickým typem `Float` jde do C jako `double`. Parametr typu
  C `float` (`gtk_label_set_xalign`, `pango_layout_set_line_spacing`)
  předejte jako `__lsl_qbe_f32(Float(x))`; tak jde v registru jako
  jednoduchá přesnost. Návratovou hodnotu C `float` `__lsl_qbe_fcallN`
  nečte (čte `double`); vlastnost GObject čtěte přes GValue typu
  `G_TYPE_DOUBLE`, GLib hodnotu převede.
- Uvnitř modulu jsou `None` a celé číslo `0` stejné slovo. Funkce, která
  může vrátit obojí, ať vrací prázdný `List`, `-1` nebo vyhodí chybu.
- Importované symboly mají verzi knihovny hostitele (`.gnu.version_r`) jako
  u GNU ld: `realpath(cesta, NULL)` volá aktuální `realpath@GLIBC_2.3`, ne
  starou kompatibilní variantu. Program pak potřebuje glibc alespoň té
  verze, se kterou byl přeložen.

Síť, TLS, kryptografie a mDNS (moduly `net`, `tls`, `crypto`, `mdns`)
popisuje kapitola [Síť, TLS a kryptografie](network.md).

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
| `glib.timeout_add_full(priorita, ms, f)`, `glib.timeout_add_seconds_full(priorita, s, f)`, `glib.unix_signal_add_full(priorita, signum, f)` | zdroje s prioritou (`glib.PRIORITY_HIGH`, `PRIORITY_DEFAULT`, `PRIORITY_LOW`) |
| `glib.spawn_quiet(argv)` | program na pozadí s výstupem do `/dev/null` (notify-send) |
| `glib.kill(pid, signum)` | signál procesu: 0 odesláno, -1 chyba (proces neběží) |
| `glib.exec(argv)` | nahradí běžící proces programem (`execvp`); vrací jen při chybě |

Pomůcky: `glib.markup_escape(text)`, `glib.find_program_in_path(jméno)`,
`glib.monotonic_time()` (µs), `glib.home_dir()`, `glib.user_config_dir()`,
`glib.user_cache_dir()`, `glib.user_data_dir()`, `glib.user_runtime_dir()`,
`glib.host_name()`, `glib.getpid()`, `glib.getenv(jméno)` (`""` když
není), `glib.set_prgname(jméno)`, `glib.set_application_name(jméno)`,
`glib.filename_from_uri(uri)`, `glib.filename_to_uri(cesta)`,
`glib.shell_quote(text)`, `glib.format_size(bajty)` („1,2 MB“),
`glib.unbuffered()` (výstup `print` hned, bez vyrovnávací paměti; `glib.main()`
a `gtk.main()` ho zapnou samy, aby záznamy služby šly do roury nebo
žurnálu okamžitě).

Místní čas a kalendář (modul `time` počítá jen v UTC bez locale):

| Funkce | Význam |
| --- | --- |
| `glib.setlocale()` | `setlocale(LC_ALL, "")`: jazyk a formáty podle prostředí; vrací název locale. Program cíle gnu startuje v locale „C“; `gtk.init()` ho nastaví sama, služba bez GTK volá `glib.setlocale()` před prvním formátováním |
| `glib.date_time_format(formát)` | teď v místním čase ve formátu `g_date_time_format` (`%H:%M`, `%A %-d. %B`; názvy podle locale) |
| `glib.format_date(rok, měsíc, den, formát)`, `glib.format_unix(sekundy, formát)` | daný den, resp. čas UNIXu v místním čase |
| `glib.local_date()` | `[rok, měsíc, den, hodina, minuta, sekunda, den v týdnu 1–7, den v roce]` |
| `glib.days_in_month(rok, měsíc)`, `glib.weekday(rok, měsíc, den)` | délka měsíce; den v týdnu (1 = pondělí … 7 = neděle) |
| `glib.first_weekday()` | první den týdne podle locale (1 pondělí, 7 neděle) |

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

| `gio.call_timeout(bus, jméno, cesta, rozhraní, metoda, params, ms)` | totéž s časovým limitem v ms (výchozí limit GDBus je 25 s) |

Chyba sběrnice nebo metody je `DBusError` se zprávou GDBus
(`try: … else: print(last_error()) end`).

### Hodnoty LSL místo textu GVariant

Druhá sada funkcí pracuje přímo s hodnotami: `Bool`, `Int` (b y n q i u x
t h), `Float` (d), `String` (s o g), `List` (pole a n-tice), `Dictionary`
(`a{…}`); `v` se rozbalí, `m` dá `None` nebo hodnotu. Opačným směrem
určuje tvar podpis D-Bus: `"i"` z `Int`, `"as"` ze seznamu, `"(su)"` z
`[text, číslo]`, `"a{sv}"` ze slovníku; hodnota pro `v` je buď
`[podpis, hodnota]` (např. `["u", 4]` pro `<uint32 4>`), nebo prostá
hodnota (`Bool` → b, `Int` → x, `Float` → d, `String` → s).

```
load gio
bus = gio.system_bus()
percent = gio.get_property_value(bus, "org.freedesktop.UPower",
    "/org/freedesktop/UPower/devices/DisplayDevice",
    "org.freedesktop.UPower.Device", "Percentage")      # Float
call gio.set_property(bus, "org.xfce.Xfconf", "/org/xfce/Xfconf",
    "org.xfce.Xfconf", "Brightness", 40, "i")
reply = gio.call_values(bus, "org.freedesktop.DBus", "/org/freedesktop/DBus",
    "org.freedesktop.DBus", "GetNameOwner", ["org.freedesktop.DBus"], "(s)", -1)
# reply == ['org.freedesktop.DBus']
```

| Funkce | Význam |
| --- | --- |
| `gio.call_values(bus, jméno, cesta, rozhraní, metoda, hodnoty, podpis, ms)` | volání s argumenty podle podpisu n-tice (`"(su)"`, `""` bez argumentů); vrací seznam hodnot odpovědi; `ms` -1 = výchozí limit |
| `gio.get_property_value(bus, jméno, cesta, rozhraní, vlastnost)` | hodnota vlastnosti |
| `gio.get_all_properties(bus, jméno, cesta, rozhraní)` | slovník všech vlastností rozhraní |
| `gio.set_property(bus, jméno, cesta, rozhraní, vlastnost, hodnota, podpis)` | nastavení vlastnosti |
| `gio.subscribe_values(bus, odesílatel, rozhraní, člen, cesta, f)` | odběr signálu; `f(sender, path, interface, signal, values)`, `values` je seznam argumentů (`PropertiesChanged`: `[rozhraní, {změněné}, [neplatné]]`) |
| `gio.emit_values(bus, cesta, rozhraní, signál, hodnoty, podpis)` | vyslání signálu s hodnotami |
| `gio.variant_to_value(v)`, `gio.value_to_variant(hodnota, podpis)` | převody pro přímou práci s GVariant |

### Vlastní objekt na sběrnici

`gio.register_object(bus, cesta, xml, f)` zaregistruje objekt s prvním
rozhraním z introspekčního XML. Při volání metody dostane `f(sender, path,
interface, method, values, invocation)` a odpoví `gio.return_value(invocation,
hodnoty, podpis)` (`""` bez návratové hodnoty) nebo
`gio.return_error(invocation, "org.example.Error.Name", zpráva)` – hned, nebo
později z jiné obsluhy (`invocation` platí, dokud se neodpoví). Vrací id
pro `gio.unregister_object(bus, id)`. Vlastní jméno na sběrnici zajistí
`gio.own_name(bus, jméno)`. Takto se píše agent BlueZ (`org.bluez.Agent1`:
`RequestPinCode`, `RequestConfirmation`, …) nebo služba, kterou volají
ostatní programy plochy.

```
XML = "<node><interface name='cz.example.Hub'><method name='Toggle'><arg type='s' name='what' direction='in'/><arg type='b' direction='out'/></method></interface></node>"

function on_method(sender, path, interface, method, values, invocation):
    if method == "Toggle":
        call gio.return_value(invocation, [toggle(values[0])], "(b)")
    else:
        call gio.return_error(invocation, "cz.example.Hub.Error", "unknown method")
    end
end

call gio.own_name(bus, "cz.example.Hub")
call gio.register_object(bus, "/cz/example/Hub", XML, on_method)
```

### Sledování souborů

`gio.file_monitor(cesta, f)` sleduje soubor nebo adresář (GFileMonitor,
inotify): `f(cesta, událost, jiná_cesta)`, událost je `gio.FILE_CHANGED`,
`FILE_CHANGES_DONE_HINT`, `FILE_DELETED`, `FILE_CREATED`,
`FILE_ATTRIBUTE_CHANGED`, `FILE_MOVED_IN`, `FILE_MOVED_OUT`, `FILE_RENAMED`
(u přesunů je `jiná_cesta` cíl, jinak `""`). Vrací monitor pro
`gio.file_monitor_cancel(monitor)`; nesledovatelná cesta je `DBusError`.

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
funkcím GTK bez předpony `gtk_` (desetinné parametry GTK berou `Float`
i `Int`):

- Okna: `window_new(titulek)`, `window_new_popup()` (bez správce oken),
  `window_set_default_size`, `window_set_title`, `window_set_type_hint`
  (`gtk.TYPE_HINT_DOCK`, `TYPE_HINT_DIALOG`, …), `window_set_decorated`,
  `window_set_keep_above/below`, `window_set_skip_taskbar_hint`,
  `window_set_skip_pager_hint`, `window_set_accept_focus`,
  `window_set_resizable`, `window_set_modal`, `window_set_transient_for`,
  `window_set_position` (`gtk.WIN_POS_*`), `window_set_icon_name`,
  `window_move(okno, x, y)`, `window_resize`, `window_get_size`,
  `window_get_position`, `window_present`, `window_present_with_time(okno,
  gtk.get_current_event_time())`, `window_stick`, `window_close`,
  `window_fullscreen/unfullscreen`, `window_maximize`, `window_iconify`,
  `window_is_active`, `window_set_default`; průhledné pozadí
  `widget_set_rgba_visual(okno)` + `widget_set_app_paintable`
  (`screen_is_composited()` říká, zda kompozitor běží).
- Kontejnery: `box_new(orientace, mezera)`, `box_pack_start/end(box, dítě,
  expand, fill, padding)`, `box_set_homogeneous`, `box_set_spacing`,
  `box_reorder_child`, `grid_new`, `grid_attach(mřížka, dítě, sloupec,
  řádek, šířka, výška)`, `grid_set_row/column_spacing`,
  `grid_set_column/row_homogeneous`, `container_add`, `container_remove`,
  `container_get_children`, `container_set_border_width`,
  `scrolled_window_new`, `scrolled_window_set_policy` (`gtk.POLICY_*`),
  `scrolled_window_set_min/max_content_height`, `event_box_new`,
  `event_box_set_visible_window`, `event_box_set_above_child`, `frame_new`,
  `separator_new`, `fixed_new`, `fixed_put/move`, `overlay_new`,
  `overlay_add_overlay`, `revealer_new`, `revealer_set_reveal_child`,
  `revealer_set_transition_type/duration`, `list_box_new`,
  `list_box_insert`, `list_box_set_selection_mode`,
  `list_box_row_get_index`.
- Popisky a vstup: `label_new`, `label_set_text`, `label_set_markup`,
  `label_get_text`, `label_set_ellipsize` (`gtk.ELLIPSIZE_END`),
  `label_set_xalign/yalign`, `label_set_max_width_chars`,
  `label_set_width_chars`, `label_set_line_wrap`, `label_set_justify`,
  `label_set_selectable`, `label_set_use_markup`, `entry_new`,
  `search_entry_new`, `entry_get_text`, `entry_set_text`,
  `entry_set_placeholder_text`, `entry_set_icon_from_icon_name(entry,
  gtk.ENTRY_ICON_SECONDARY, jméno)`, `entry_set_max_length`,
  `entry_set_visibility`, `entry_set_activates_default`,
  `entry_grab_focus_without_selecting` (signály `activate`, `changed`,
  `icon-press`).
- Tlačítka a volby: `button_new(text)`, `button_new_empty()`,
  `button_new_from_icon_name`, `button_set_label`, `button_set_image`,
  `button_set_always_show_image`, `button_set_image_position`,
  `button_set_relief(tlačítko, gtk.RELIEF_NONE)`, `button_clicked`,
  `toggle_button_new`, `check_button_new`, `toggle_button_get/set_active`,
  `switch_new`, `switch_get/set_active`, `combo_box_text_new`,
  `combo_box_text_append(combo, id, text)`, `combo_box_get/set_active`,
  `combo_box_text_get_active_text`, `scale_new_with_range(orientace, min,
  max, krok)`, `scale_set_draw_value`, `range_get_value` (Float),
  `range_set_value`, `range_set_increments`, `spin_button_new_with_range`,
  `spin_button_get/set_value`, `progress_bar_new`,
  `progress_bar_set_fraction`, `progress_bar_set_text`, `level_bar_new`,
  `level_bar_set_value`, `calendar_new`, `calendar_get_date` (`[rok,
  měsíc, den]`), `calendar_select_day(kalendář, rok, měsíc, den)`,
  `calendar_mark_day`, `calendar_clear_marks`.
- Obrázky: `image_new_from_icon_name(jméno, velikost)`,
  `image_new_from_file`, `image_new_from_pixbuf`,
  `image_set_from_icon_name`, `image_set_from_pixbuf`,
  `image_set_pixel_size`, `image_clear`, `icon_theme_has_icon(jméno)`,
  `pixbuf_new_from_file(cesta)`, `pixbuf_new_from_file_at_scale(cesta,
  šířka, výška, zachovat_poměr)` (0 při chybě), `pixbuf_get_width/height`,
  `cairo_set_source_pixbuf(cr, pixbuf, x, y)` pro kreslení v `draw`.
- Widgety obecně: `widget_show_all`, `widget_show`, `widget_hide`,
  `widget_set_visible`, `widget_get_visible`, `widget_is_visible`,
  `widget_destroy`, `widget_realize`, `widget_set_size_request`,
  `widget_get_allocated_width/height`, `widget_get_allocation`,
  `widget_queue_draw`, `widget_set_opacity`, `widget_set_halign/valign`
  (`gtk.ALIGN_*`), `widget_set_hexpand/vexpand`, `widget_set_margin`,
  `widget_set_margins(widget, začátek, konec, nahoře, dole)`,
  `widget_set_sensitive`, `widget_set_tooltip`, `widget_set_tooltip_markup`,
  `widget_set_name`, `widget_add_class`, `widget_remove_class`,
  `widget_grab_focus`, `widget_set_can_focus`, `widget_set_can_default`,
  `widget_get_parent`, `widget_get_toplevel`, `widget_get_window`,
  `widget_add_events(widget, gtk.BUTTON_PRESS_MASK + gtk.SCROLL_MASK)`,
  `widget_set_state_flags(widget, gtk.STATE_FLAG_CHECKED, False)`,
  `widget_unset_state_flags`, `widget_get_state_flags`,
  `widget_get_color(widget, stav)` (barva popředí z motivu `[r, g, b, a]`
  pro cairo), `widget_set_cursor(widget, "pointer")` (realizovaný widget;
  `""` výchozí kurzor).
- Styl: `css_load(css)` vrací provider, `css_remove(provider)` ho zase
  odebere (přepnutí světlý/tmavý za běhu), `css_load_file(cesta)` (0 při
  chybě). `settings_get_default()` a `object_get_string/int/bool(objekt,
  vlastnost)`, `object_set_string/int/bool` čtou a mění vlastnosti GObject
  (`"gtk-theme-name"`, `"gtk-application-prefer-dark-theme"`,
  `"gtk-font-name"`).
- Monitory: `monitor_count()`, `monitor_workarea(index)`,
  `primary_monitor_workarea()`, `monitor_at_point_workarea(x, y)`
  (`[x, y, šířka, výška]` bez panelů, pro umístění okna k liště),
  `monitor_geometry(index)`, `monitor_scale_factor(index)`.
- Smyčka: `main()`, `main_quit()`, `pump()`, `timeout_add`, `idle_add`,
  `source_remove`, `version()`, `get_current_event_time()`.

`gtk.connect(widget, "signál", f)`: obsluha dostane argumenty signálu
a nakonec widget, tedy `on_click(button)`, `on_draw(cr, area)`,
`on_key(event, window)`, `on_delete(event, window)`, `on_state(state,
switch)`. Argumenty jsou surová slova (ukazatele GTK, `gboolean`,
celá čísla). Události čtou pomocné funkce: `event_key_keyval(event)`
(`gtk.KEY_Escape`, `KEY_Return`, `KEY_Up`, …), `event_key_state`
(`gtk.CONTROL_MASK`, `SHIFT_MASK`, `MOD1_MASK`, `SUPER_MASK`),
`event_key_name`, `event_key_text`; pro `button-press-event`,
`motion-notify-event` a `scroll-event` `event_x/y(event)` (Float),
`event_button`, `event_button_state`, `event_is_double_click`,
`event_time`, `event_scroll_direction` (`gtk.SCROLL_UP/DOWN/SMOOTH`),
`event_scroll_deltas`. Obsluha, která událost vyřídila, vrátí `True`.

## Moduly `cairo` a `pango`: kreslení

Obsluha signálu `draw` dostane `cr` (cairo kontext) a kreslí modulem
`cairo`; text s písmem systému, zalamováním a výpustkou dává `pango`.
Souřadnice a barvy jsou `Float` (`Int` se převede). Tytéž funkce kreslí
i mimo okno do obrázku (`image_surface_create` + `create`, PNG přes
`surface_write_to_png`) – tak běží i test bez displeje.

```
load gtk
load cairo
load pango

function on_draw(cr, area):
    width = gtk.widget_get_allocated_width(area)
    color = gtk.widget_get_color(area, 0)
    call cairo.set_source_rgba(cr, 0.2, 0.5, 0.9, 1.0)
    call cairo.rounded_rectangle(cr, 4, 4, width - 8, 40, 6)
    call cairo.fill(cr)
    call cairo.set_source_color(cr, color)
    call pango.draw_text(cr, 12, 12, "pátek 23.", "Sans Bold 11")
    return True
end

area = gtk.drawing_area_new()
call gtk.connect(area, "draw", on_draw)
```

Cairo: `set_source_rgb/rgba`, `set_source_color([r, g, b, a])`,
`set_line_width`, `get_line_width`, `set_line_cap/join`, `set_operator`,
`set_antialias`, `set_dash(cr, [délky], posun)`, cesty `new_path`,
`close_path`, `move_to`, `line_to`, `rel_move_to`, `rel_line_to`,
`curve_to`, `rectangle`, `rounded_rectangle(cr, x, y, šířka, výška,
poloměr)`, `arc`, `arc_negative`, `fill`, `fill_preserve`, `stroke`,
`stroke_preserve`, `paint`, `paint_with_alpha`, `clip`, `reset_clip`,
`save`, `restore`, `translate`, `scale`, `rotate`; přechody
`pattern_create_linear/radial`, `pattern_add_color_stop_rgba`,
`set_source`, `pattern_destroy`; jednoduchý text `select_font_face`,
`set_font_size`, `show_text`, `text_extents`; obrázky
`image_surface_create(cairo.FORMAT_ARGB32, šířka, výška)`,
`image_surface_create_from_png`, `image_surface_get_width/height`,
`image_surface_pixel(surface, x, y)`, `surface_write_to_png`,
`surface_status`, `surface_destroy`, `set_source_surface`, `create`,
`destroy`, `status`; konstanta `cairo.PI`.

Pango: `cairo_create_layout(cr)`, `layout_set_text`, `layout_set_markup`,
`layout_set_font(layout, "Sans Bold 12")`, `layout_set_width/height`
(pixely, -1 bez omezení), `layout_set_ellipsize` (`pango.ELLIPSIZE_END`),
`layout_set_alignment` (`pango.ALIGN_CENTER`), `layout_set_wrap`,
`layout_set_justify`, `layout_set_single_paragraph_mode`,
`layout_set_spacing`, `layout_set_line_spacing`, `layout_get_pixel_size`
(`[šířka, výška]`), `layout_get_baseline`, `layout_get_line_count`,
`layout_is_ellipsized`, `cairo_show_layout(cr, layout)`,
`cairo_layout_path`, `cairo_update_layout`, `layout_unref`; zkratky
`draw_text(cr, x, y, text, písmo)` a `text_size(cr, text, písmo)`.

Další funkce GTK se přidávají do `stdlib/gtk.lsl` jednou řádkou podle
stejného vzoru: `return __lsl_qbe_callN(__lsl_symbol("gtk_…"),
ptr(widget), cstr(text), …)`. Uvnitř modulu platí: argumenty z běžného
kódu, globální proměnné modulu i návratové hodnoty funkcí LSL jsou
zabalené, před předáním do C je rozbalí `ptr()`; parametry se nepřepisují
(přepsaný parametr by se zabalil znovu); `__lsl_symbol` chce doslovný
řetězec; text z C vrací `glib.from_c(adresa)` (kopie) nebo
`glib.take_c(adresa)` (navíc `g_free`). Argument se statickým typem
`Float` (`Float(x)`, desetinný literál, výsledek výpočtu s Float) se do C
předá jako `double` v registru SSE, `__lsl_qbe_fcallN` vrací `double` jako
`Float`; `gfloat` dává `__lsl_qbe_f32(Float(x))`. Double ve variadické
funkci (`g_object_set` s vlastností typu double) takto předat nelze.

## Testy

`tests/gnu/glib_conformance.lsl`, `glib_more_conformance.lsl`,
`gio_conformance.lsl`, `gio_values_conformance.lsl`, `gtk_conformance.lsl`,
`gtk_widgets_conformance.lsl` a `cairo_conformance.lsl` (bez displeje)
běží jen na cíli `linux-x86_64-gnu`
(`tools/ci/target_tests.py`, `tests/cross_targets.py`); bez sběrnice
relace a displeje se spustí znovu pod `dbus-run-session` a `xvfb-run`,
bez těchto nástrojů vypíší `SKIP: …` a runner je přeskočí.
