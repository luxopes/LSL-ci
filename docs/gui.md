# GUI a 2D grafika

LSL staví GUI ze stdlib modulů v čistém LSL bez nativních knihoven:
`gfx` (pixelová plocha, rasterizace, alpha blending, gradienty, zaoblené
anti-aliased tvary), `display` (okno na X11 nebo Linux framebuffer),
`ui` (jednoduché widgety), `css` (deklarativní styl), `input` (evdev
klávesnice) a `fd` (raw descriptor/socket I/O, na kterém ostatní stojí).
Aplikace napsaná proti `display` běží beze změny jako okno na desktopu i
na framebufferu LuxOS. Ukázka „liquid glass" designu (frosted panely,
gradientní tlačítka, měkké stíny) je `examples/gui_glass_calc.lsl`.

## Liquid glass / compositing (gfx)

Pro moderní vzhled má `gfx` compositing primitiva pracující v celo­číselné
fixed-point matematice (žádné boxované Floaty, ~450x rychlejší než naivní
float verze):

- `raster_gradient(pixels, w, h, top, bottom)` — diagonální gradient.
- `raster_round_rect(pixels, w, h, x, y, rw, rh, radius, color, alpha, feather)`
  — anti-aliased zaoblený obdélník s alpha blendingem; `feather` je měkkost
  hrany (1 = ostrá, víc = měkký stín).
- `raster_round_rect_grad(..., top, bottom, alpha, feather)` — s vertikálním
  gradientem (gradientní tlačítka).
- `raster_shadow(..., color, alpha, blur)` — měkký stín.
- `raster_text_aa(pixels, w, h, x, y, text, color, alpha, scale)` —
  anti-aliased škálovaný text (2x2 supersampling).
- `mix_color(bottom, top, alpha)` — alpha blend dvou barev.

Frosted „sklo" se dělá průhledným světlým `raster_round_rect` (alpha ~40)
nad gradientním pozadím — gradient prosvítá a působí jako matné sklo.

## Styl přes CSS (css)

`css.parse(text)` načte podmnožinu CSS do Dictionary `selektor -> {vlastnost:
hodnota}`. Podporuje `.selector { prop: value; }`, barvy `#rgb`/`#rrggbb`/
`rgb(...)`/`rgba(...)`, `background: <barva> | linear-gradient(a, b)` a
číselné `border-radius`/`font-size`/… Přístup: `css.rule(sheet, name)`,
`css.value(rules, key, default)`, a interprety `css.color`, `css.alpha`,
`css.is_gradient`, `css.gradient_top/bottom`, `css.number`. Kalkulačka
`gui_glass_calc.lsl` má celý vzhled popsaný jedním stylesheetem.

## Rychlý start: kompletní aplikace

```lsl
load gfx
load display
load ui
load time

function on_click(widget, state):
    state["count"] = state["count"] + 1
    return None
end

d = display.open(560, 380, "LSL GUI")
screen = gfx.surface(d.width, d.height, 0)
state = ui.new_state()
state["count"] = 0

widgets = []
widgets.append(ui.button(30, 40, 150, 40, "Klikni", on_click))

while state["running"] and not d.should_close():
    call ui.process(widgets, state, d.poll())
    call ui.paint(screen.pixels, screen.width, screen.height, widgets, ui.color_background)
    call screen.text(200, 52, String(state["count"]), ui.color_accent_text)
    call d.present(screen.pixels, screen.width, screen.height)
    call time.sleep(0.016)
end
call d.close()
```

Celá aplikace s tlačítky, checkboxem a počítadlem je
`examples/gui_app.lsl`; `examples/gui_calc.lsl` je kalkulačka s kruhovými
tlačítky v macOS stylu, ovládaná myší i klávesnicí (~0,8 ms na plné
překreslení, ~4 MB RAM, překresluje jen při změně).

## Modul display

```lsl
d = display.open(640, 400, "Okno")     # X11 okno, nebo framebuffer
call d.present(surface.pixels, surface.width, surface.height)
for event in d.poll():
    ...
end
if d.should_close():
    ...
end
call d.close()
```

`display.open(width, height, title)` vybere backend: je-li nastaveno
`DISPLAY` a existuje X socket, otevře **X11 okno**; jinak spadne na
**framebuffer** (`/dev/fb0`). `LSL_DISPLAY=fb` nebo `=x11` volbu vynutí.
`display.open_framebuffer()` otevře framebuffer napřímo a respektuje
`LSL_FB_DEV`/`LSL_FB_MODE` (`WIDTHxHEIGHTxSTRIDE`) pro zápis do souboru.

Obě větve dávají stejné události jako List trojic `(druh, a, b)`:
`("key", kód, 1/0)`, `("button", číslo, 1/0)`, `("motion", x, y)`,
`("expose", 0, 0)` a `("close", 0, 0)`. Klávesové kódy jsou linuxové
(evdev), shodné pro oba backendy, takže kód pracuje s `input.key_esc`
apod. bez ohledu na backend. `d.width`/`d.height` jsou rozměry plochy.

Smyčka aplikace volá po `d.present(...)` ještě `d.wait_frame()`, které
stropuje snímkovou frekvenci (~60 Hz) — tím je CPU omezené, i když
smyčka jinak nespí. `present` navíc každý snímek uklízí paměť, takže
konzervativní GC nedrží staré snímkové buffery a paměť zůstává konstantní
(viz Známé mezery).

X11 backend je čistě-LSL klient X protokolu přes unix socket: handshake
s MIT-MAGIC-COOKIE-1 z `~/.Xauthority`, jedno InputOutput okno, ZPixmap
PutImage po pruzích a WM_DELETE_WINDOW pro zavření. Žádná libX11.

## Modul ui

Widgety jsou Dictionary a všechny funkce jsou volné (LSL volá metody jen
na staticky typovaných lokálech, ne na objektech předaných parametrem —
proto aplikace vlastní `display`/`surface` a smyčku, a `ui` kreslí přes
`gfx.raster_*` do raw pixel bufferu).

- `ui.label(x, y, text)`, `ui.button(x, y, w, h, text, on_click)`,
  `ui.checkbox(x, y, text, checked)` — vrací widget Dictionary.
- `ui.new_state()` — sdílený stav `{running, key, mouse_x, mouse_y}`;
  přidej si vlastní klíče.
- `ui.process(widgets, state, events)` — zpracuje dávku událostí:
  hover, kliknutí tlačítek (spustí callback), přepnutí checkboxu, Esc a
  zavření okna nastaví `state["running"] = False`.
- `ui.paint(pixels, width, height, widgets, background)` — vykreslí vše.
- Barvy tématu: `ui.color_background`, `color_text`, `color_muted`,
  `color_accent`, `color_accent_text`, `color_border`, `color_field`.

Callback tlačítka má tvar `on_click(widget, state)`. Nesmí sahat na pole
instancí, ale smí měnit sdílený `state` Dictionary — tak předává výsledek
zpět do smyčky (počítadlo, `state["running"] = False`, …).

## Modul gfx

```lsl
screen = gfx.surface(640, 360, gfx.rgb(24, 26, 34))
call screen.fill_rect(40, 40, 360, 180, gfx.rgb(52, 120, 246))
call screen.text(64, 64, "Ahoj z LSL!", gfx.rgb(255, 255, 255))
call screen.save_ppm("okno.ppm")
```

`Surface` drží pixely jako `IntArray` s jedním `0xRRGGBB` Int na pixel.
`gfx.rgb(r, g, b)` skládá barvu, `gfx.red/green/blue(color)` ji rozkládá.
Metody: `clear`, `get`, `set`, `hline`, `vline`, `fill_rect`, `rect`,
`line` (Bresenham), `blit`, `text`, `glyph`, `save_ppm` (binární P6 PPM).
`text` kreslí vestavěným 8x16 fontem (Uni2-Fixed16, ASCII + česká
diakritika) a vrací šířku; `gfx.text_width(value)`/`gfx.text_height()`
dají rozměry předem.

Každá metoda deleguje na volnou `gfx.raster_*(pixels, width, height, …)`
funkci nad raw bufferem — ty používá i `ui` a lze je volat přímo, když
pracuješ mimo objekt `Surface` (např. vlastní widgety, které dostávají
`surface.pixels` parametrem). Kopie mezi plochami předává zdroj polem:
`screen.blit(sprite.pixels, sprite.width, sprite.height, x, y)`.

Volné rasterizéry: `raster_clear`, `raster_set`, `raster_hline`,
`raster_vline`, `raster_fill_rect`, `raster_rect`, `raster_line`,
`raster_blit`, `raster_fill_circle(…, cx, cy, radius, color)`,
`raster_fill_pill(…, x, y, w, h, color)` (zaoblený obdélník) a
`raster_text_scaled(…, x, y, text, color, scale)` (font zvětšený
celočíselným faktorem pro velké nadpisy). Kruh a pill dávají hladká
tlačítka; scaled text velký displej z jednoho vestavěného fontu.

## Modul input a fd

`input` čte klávesnici z `/dev/input` (`input.key_esc`, `key_enter`,
šipky, …; hodnoty `press`/`release`/`repeat`). `display` ho pro
framebuffer používá sám; pro X11 chodí klávesy od serveru. `fd` obaluje
raw descriptor a socket builtiny (`__lsl_fd_open/read/write/seek/close/
socket/connect`) na catchable `FileError` a přidává `fd.connect_unix`,
`fd.read_all`/`read_text` (i procfs/sysfs/devices) a flag konstanty.

## Výkon

Horké smyčky používají checked casty (`IntArray(pixels)`, `Int(...)`),
aby běžely nad neboxovanými poli místo tagged dispatchu (~400x rozdíl).
Orientační časy na x86_64 (LSL-generovaný ELF, bez nativních kernelů):

- `fill_rect` 640x360: ~0.6 ms; `clear` 640x360: ~0.7 ms
- `text` 33 znaků: ~0.18 ms; `blit` 32x32: ~4 us
- `raster_round_rect` 74x74 (AA + alpha, fixed-point): ~0.45 ms
- `present`: framebuffer 1920x1080 ~19 ms; X11 okno 640x400 pod 2 ms

Compositing kernely počítají v celočíselném fixed-pointu; naivní float
verze byla ~450x pomalejší a alokovala boxované Floaty. Vzor: v horké
smyčce nikdy nepočítej s Float a přetypuj barvy/rozměry na `Int` lokály.

## Známé mezery

- Myš je hlášená přes `("button", …)` a `("motion", …)`; kolečko a
  dvojklik zpracované nejsou.
- X11 backend překresluje celé okno na každý `present` (žádné dirty
  rectangles) a nezpracovává resize (okno má pevnou velikost).
- Textové pole / edit widget zatím v `ui` není; jsou label, button a
  checkbox.
- Paměť: konzervativní GC by v render smyčce falešně držel krátkodobé
  snímkové buffery (ukazatele zůstanou na zásobníku), a paměť by lineárně
  rostla. `present` to řeší voláním `gc()` každý snímek, takže paměť je
  konstantní; RSS okna ale odráží startovní peak alokátoru (ten paměť
  nevrací OS), takže větší okno drží desítky MB i v klidu. Skutečně živá
  data jsou malá. Přesnější GC (stack mapy / free-list snímkových bufferů)
  je budoucí runtime úloha.
- Font je 8x16 bitmapový (byť anti-aliased) — pro plně hladký vektorový
  text by byl potřeba TrueType renderer.
