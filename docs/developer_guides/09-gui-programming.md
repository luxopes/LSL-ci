# 9. GUI programování

Tato kapitola vysvětluje, jak v LSL vytvářet grafické aplikace — od
otevření okna přes kreslení tvarů a textu až po interaktivní widgety.
Všechny komponenty (X11 protokol, rasterizace, widgety) jsou napsány v
čistém LSL bez nativních knihoven.

## Co budete potřebovat

Od LSL 0.8.2 jsou grafické knihovny volitelná rozšíření:

```text
lsl install ui
lsl install display
lsl install css
```

`ui` automaticky nainstaluje `gfx` a `input`; `display` přidá `x11` a
`input`, `css` vyžaduje `gfx`. Samostatně lze nainstalovat `gfx`, `x11`
nebo `wayland`. Základní LSL grafické moduly neobsahuje, ani po aktualizaci
z 0.8.1. Dříve zkompilované samostatné programy zůstávají funkční.
Grafické moduly obsahují explicitní `unsafe` a nelze je překládat v sandboxu.

- **X11 server** (linuxové desktopové prostředí) — nastavená proměnná
  `DISPLAY`. Aplikace automaticky otevře okno.
- **Nebo framebuffer** (`/dev/fb0`) — pro běh bez grafického prostředí
  (např. na LuxOS). Stejný kód funguje na obou.

## Jak GUI aplikace funguje

Každá GUI aplikace běží v nekonečné smyčce:

1. **Počkej na událost** (klávesa, myš, zavření okna).
2. **Zpracuj událost** — aktualizuj stav aplikace.
3. **Vykresli** — překresli obsah okna podle nového stavu.
4. **Opakuj** — jdi na krok 1.

Tomuto vzoru se říká **event loop** (smyčka událostí). LSL ho
implementuje přes moduly `display` (okno a události), `gfx` (kreslení)
a `ui` (widgety).

## Architektura

GUI stack se skládá z několika modulů:

| Modul | Odpovědnost |
|---|---|
| `display` | Otevření okna (X11 nebo framebuffer), události |
| `gfx` | Pixelová plocha, rasterizace, alpha blending |
| `ui` | Widgety (tlačítka, checkboxy, labely) |
| `css` | Deklarativní stylování |
| `input` | evdev klávesnice (pro framebuffer) |
| `fd` | Raw descriptor/socket I/O (na čem ostatní stojí) |

## Rychlý start: první okno

```lsl
load display
load gfx
load ui
load time

# Otevři okno
d = display.open(640, 400, "Moje první LSL aplikace")

# Vytvoř kreslicí plochu
screen = gfx.surface(d.width, d.height, gfx.rgb(24, 26, 34))

# Smyčka
while not d.should_close():
    # Zpracuj události
    for event in d.poll():
        if event[0] == "close":
            break
        end
    end

    # Vykresli
    call screen.fill_rect(20, 20, 200, 100, gfx.rgb(52, 120, 246))
    call screen.text(40, 50, "Ahoj z LSL!", gfx.rgb(255, 255, 255))

    # Zobraz
    call d.present(screen.pixels, screen.width, screen.height)

    call time.sleep(0.016)
end

call d.close()
```

## Modul display

### Otevření okna

```lsl
d = display.open(640, 400, "Titulek okna")
```

Backend se vybere automaticky:

- Pokud je nastaveno `DISPLAY` a existuje X socket → **X11 okno**.
- Jinak → **Linux framebuffer** (`/dev/fb0`).

Vynucení backendu:

```lsl
# LSL_DISPLAY=x11 ./muj_program.lsl
# LSL_DISPLAY=fb ./muj_program.lsl
```

Framebuffer lze otevřít explicitně:

```lsl
d = display.open_framebuffer()
```

### Rozměry a stav

```lsl
print d.width      # šířka okna
print d.height     # výška okna
d.should_close()   # True pokud uživatel zavřel okno
```

### Události

`d.poll()` vrací List událostí. Každá událost je trojice `(druh, parametr_a, parametr_b)`:

| Druh | Parametry | Význam |
|---|---|---|
| `"key"` | (kód, stisk/uvolnění) | Klávesa stisknuta (1) / uvolněna (0) |
| `"button"` | (číslo, 1/0) | Tlačítko myši |
| `"motion"` | (x, y) | Pohyb myši |
| `"expose"` | (0, 0) | Okno bylo odkryto |
| `"close"` | (0, 0) | Uživatel zavřel okno |

```lsl
for event in d.poll():
    kind = event[0]
    if kind == "key":
        code = event[1]
        pressed = event[2]    # 1 = stisk, 0 = uvolnění
        if pressed and code == input.key_esc:
            print "Escape stisknuto!"
        end
    elif kind == "button":
        button = event[1]
        pressed = event[2]
        print "Tlačítko", button, "stisk:" if pressed else "uvolněno:"
    elif kind == "motion":
        x = event[1]
        y = event[2]
        print "Myš na:", x, y
    elif kind == "close":
        print "Zavírám..."
    end
end
```

Klávesové kódy jsou linuxové (evdev) — shodné pro X11 i framebuffer.
Modul `input` definuje konstanty: `input.key_esc`, `input.key_enter`,
`input.key_left`, `input.key_up`, `input.key_right`, `input.key_down` atd.

### Vykreslení

```lsl
call d.present(screen.pixels, screen.width, screen.height)
```

`present` překreslí celé okno na každý snímek (žádné dirty rectangles).

## Modul gfx — grafické primitivy

### Surface

```lsl
screen = gfx.surface(640, 480, gfx.rgb(0, 0, 0))  # černé pozadí
```

`Surface` drží pixely jako `IntArray` — jeden pixel je jeden Int
(`0xRRGGBB`). Metody:

#### Barvy

```lsl
red = gfx.rgb(255, 0, 0)      # složí barvu z R,G,B
r = gfx.red(color)             # extrahuje červenou složku
g = gfx.green(color)           # extrahuje zelenou složku
b = gfx.blue(color)            # extrahuje modrou složku
```

#### Kreslení

```lsl
# Celá plocha
call screen.clear(gfx.rgb(30, 30, 40))   # vyplní celou plochu barvou

# Obdélníky
call screen.fill_rect(10, 10, 100, 50, gfx.rgb(52, 120, 246))   # vyplněný
call screen.rect(10, 10, 100, 50, gfx.rgb(255, 255, 255))       # obrys

# Čáry
call screen.hline(0, 300, 640, gfx.rgb(100, 100, 100))  # horizontální
call screen.vline(320, 0, 480, gfx.rgb(100, 100, 100))  # vertikální
call screen.line(0, 0, 639, 479, gfx.rgb(255, 255, 255))# Bresenham

# Pixely
color = screen.get(x, y)    # přečte pixel
call screen.set(x, y, color)  # nastaví pixel
```

#### Text

```lsl
width = screen.text(20, 20, "Ahoj světe!", gfx.rgb(255, 255, 255))
print "Text zabral:", width, "pixelů"

# Samostatný znak
call screen.glyph(100, 100, 65, gfx.rgb(255, 0, 0))  # ASCII 65 = 'A'

# Měření
w = gfx.text_width("Ahoj")
h = gfx.text_height()
print "Velikost textu:", w, "×", h
```

Vestavěný font je 8×16 bitmapový (Uni2-Fixed16, ASCII + česká diakritika).

#### Blit (kopírování ploch)

```lsl
# Vytvoř sprite
sprite = gfx.surface(32, 32, gfx.rgb(0, 0, 0))
call sprite.fill_rect(0, 0, 32, 32, gfx.rgb(255, 0, 0))

# Kopíruj na hlavní plochu
call screen.blit(sprite.pixels, sprite.width, sprite.height, 100, 50)
```

#### Uložení do souboru

```lsl
call screen.save_ppm("screenshot.ppm")  # binární P6 PPM formát
```

### Compositing (liquid glass design)

Pro moderní vzhled poskytuje `gfx` pokročilá compositing primitiva s
anti-aliasingem a alpha blendingem. Všechna pracují v celočíselné
fixed-point aritmetice (žádné boxované Floaty — ~450× rychlejší):

```lsl
# Zaoblený obdélník
call gfx.raster_round_rect(
    pixels, w, h,
    x, y, rw, rh,       # pozice a rozměry
    radius,              # zaoblení rohů
    color, alpha,        # barva a průhlednost (0-255)
    feather              # měkkost hrany (1 = ostrá, více = měkký stín)
)

# Gradientní pozadí
call gfx.raster_gradient(pixels, w, h, top_color, bottom_color)

# Zaoblený obdélník s gradientem
call gfx.raster_round_rect_grad(pixels, w, h, x, y, rw, rh,
    top_color, bottom_color, alpha, feather)

# Měkký stín
call gfx.raster_shadow(pixels, w, h, x, y, rw, rh, color, alpha, blur)

# Anti-aliased škálovaný text (2×2 supersampling)
call gfx.raster_text_aa(pixels, w, h, x, y, text, color, alpha, scale)

# Alpha blend dvou barev
result = gfx.mix_color(bottom_color, top_color, alpha)
```

"Liquid glass" efekt se vytvoří průhledným světlým obdélníkem (alpha ~40)
přes gradientním pozadí — gradient prosvítá a vytváří dojem matného skla.

### Další rasterizéry

```lsl
# Souvislé vyplnění
call gfx.raster_clear(pixels, w, h, color)

# Kruh a pill (zaoblený obdélník pro tlačítka)
call gfx.raster_fill_circle(pixels, w, h, cx, cy, radius, color)
call gfx.raster_fill_pill(pixels, w, h, x, y, rw, rh, color)
```

Všechny rasterizéry pracují nad raw `IntArray` bufferem a lze je volat
přímo — nemusíte vytvářet `Surface` objekt.

## Modul ui — widgety

### Vytvoření widgetů

```lsl
load ui

# Stav
state = ui.new_state()
state["counter"] = 0

# Widgety
widgets = []
widgets.append(ui.label(30, 20, "Počítadlo:"))
widgets.append(ui.button(30, 50, 150, 40, "Klikni!", on_button_click))
widgets.append(ui.checkbox(30, 100, "Povolit", True))
```

### Callback tlačítka

```lsl
function on_button_click(widget, state):
    state["counter"] = state["counter"] + 1
    if state["counter"] >= 10:
        state["running"] = False   # ukončí smyčku
    end
    return None
end
```

Callback má signaturu `function(widget, state)`. Nesmí sahat na pole
instancí, ale smí měnit sdílený `state` Dictionary.

### Zpracování událostí

```lsl
function main_loop(d, screen, widgets, state):
    while state["running"] and not d.should_close():
        # Zpracuj události
        call ui.process(widgets, state, d.poll())

        # Vykresli
        call ui.paint(screen.pixels, screen.width, screen.height,
                     widgets, ui.color_background)

        # Vlastní kreslení nad widgety
        call screen.text(200, 20, String(state["counter"]),
                        ui.color_accent_text)

        # Zobraz
        call d.present(screen.pixels, screen.width, screen.height)
        call time.sleep(0.016)
    end
end
```

`ui.process` zpracuje: hover, kliknutí tlačítek, přepnutí checkboxu, Esc
(nastaví `state["running"] = False`) a zavření okna.

### Barvy tématu

```lsl
ui.color_background      # pozadí okna
ui.color_text            # text
ui.color_muted           # tlumený text
ui.color_accent          # zvýrazňovací barva
ui.color_accent_text     # text na zvýraznění
ui.color_border          # okraje
ui.color_field           # vstupní pole
```

## Modul css — deklarativní stylování

```lsl
load css

stylesheet = css.parse("""
    .button {
        background: #3478F6;
        color: #FFFFFF;
        border-radius: 8;
        font-size: 14;
    }
    .panel {
        background: linear-gradient(#1C1E22, #2A2D35);
        border-radius: 12;
    }
""")

# Získání pravidel pro selektor
rules = css.rule(stylesheet, ".button")
bg = css.value(rules, "background", "#000000")
radius = css.number(css.value(rules, "border-radius", "0"))

# Parsování barev
color = css.color("#3478F6")
color = css.color("rgb(52, 120, 246)")
color = css.color("rgba(52, 120, 246, 0.5)")
alpha = css.alpha("rgba(52, 120, 246, 0.5)")  # 0.5
```

Podporované CSS vlastnosti: `background` (barva i `linear-gradient`),
`color`, `border-radius`, `font-size`, `padding`, `margin`.

## Kompletní aplikace — kalkulačka

Struktura typické GUI aplikace:

```lsl
load display
load gfx
load ui
load input
load time

# Stav aplikace
state = ui.new_state()
state["display"] = "0"
state["operation"] = None
state["previous"] = 0
state["clear_next"] = False

# Callbacky tlačítek
function digit_click(button, state):
    digit = button["digit"]
    if state["clear_next"]:
        state["display"] = String(digit)
        state["clear_next"] = False
    else:
        if state["display"] == "0":
            state["display"] = String(digit)
        else:
            state["display"] = state["display"] + String(digit)
        end
    end
end

function operator_click(button, state):
    op = button["operation"]
    current = Int(state["display"])
    if state["operation"] != None:
        if state["operation"] == "+":
            current = state["previous"] + current
        elif state["operation"] == "-":
            current = state["previous"] - current
        end
    end
    state["previous"] = current
    state["operation"] = op
    state["display"] = String(current)
    state["clear_next"] = True
end

function equals_click(button, state):
    if state["operation"] != None:
        call operator_click({"operation": state["operation"]}, state)
        state["operation"] = None
        state["clear_next"] = True
    end
end

# Inicializace
d = display.open(320, 460, "Kalkulačka")
screen = gfx.surface(d.width, d.height, gfx.rgb(24, 26, 34))

# Vytvoření widgetů
widgets = []

# Displej
widgets.append(ui.label(20, 20, ""))  # placeholder — kreslíme ručně

# Tlačítka
buttons = [
    ["7","8","9","+"],
    ["4","5","6","-"],
    ["1","2","3","="],
    ["0",".","C",""]
]

for row in rang(4):
    for col in rang(4):
        label = buttons[row][col]
        if label == "":
            continue
        end
        x = 20 + col * 74
        y = 80 + row * 70

        if label in "+-":
            btn = {"kind": "button", "text": label, "x": x, "y": y,
                   "w": 64, "h": 60, "operation": label}
            btn["callback"] = operator_click
        elif label == "=":
            btn = {"kind": "button", "text": label, "x": x, "y": y,
                   "w": 64, "h": 60}
            btn["callback"] = equals_click
        elif label == "C":
            btn = {"kind": "button", "text": label, "x": x, "y": y,
                   "w": 64, "h": 60}
            # Vyčistit
        else:
            btn = {"kind": "button", "text": label, "x": x, "y": y,
                   "w": 64, "h": 60, "digit": Int(label)}
            btn["callback"] = digit_click
        end
        widgets.append(btn)
    end
end

# Hlavní smyčka
while state["running"] and not d.should_close():
    # Zpracuj události
    call ui.process(widgets, state, d.poll())

    # Vykresli pozadí
    call ui.paint(screen.pixels, screen.width, screen.height,
                 widgets, ui.color_background)

    # Vlastní displej
    call screen.fill_rect(20, 20, 280, 50, gfx.rgb(40, 44, 52))
    display_text = state["display"]
    text_w = gfx.text_width(display_text)
    call screen.text(300 - text_w - 10, 32, display_text,
                    gfx.rgb(255, 255, 255))

    # Zobraz
    call d.present(screen.pixels, screen.width, screen.height)
    call time.sleep(0.016)
end

call d.close()
```

## Výkon a optimalizace

### Časování

- `fill_rect` 640×360: ~0.18 ms
- `clear` 1920×1080: ~3.7 ms
- `text` 33 znaků: ~0.18 ms
- `blit` 1920×1080 (celý): ~5.6 ms
- `raster_round_rect` 74×74 (AA + alpha): ~0.45 ms
- `present` framebuffer 1920×1080: ~6.3 ms
- `present` X11 640×400: pod 2 ms

### Tipy pro výkon

1. **Int, ne Float** — v horkých smyčkách používejte Int a checked casty.
2. **Překreslujte jen při změně** — pokud se nic nemění, nevolejte
   `present`.
3. **Používejte bulk kernely** — `raster_fill`, `raster_copy`, `raster_pack`.
4. **Spěte rozumně** — `time.sleep(0.016)` pro ~60 FPS.
5. **`present` každý snímek volá GC** — paměť zůstává konstantní.

## Omezení

- Myší kolečko a dvojklik nejsou zpracovávány.
- X11 backend překresluje celé okno, bez dirty rectangles.
- Okno má pevnou velikost — resize není podporován.
- Textové pole / edit widget zatím není v `ui`.
- Font je 8×16 bitmapový — pro vektorový text by byl potřeba TrueType
  renderer.

## Kam dál

- [10 — AI aplikace](10-ai-applications.md): integrace AI do GUI
- [11 — Výkon a optimalizace](11-performance-and-optimization.md): podrobné techniky optimalizace
