# Kalkulačka v macOS "liquid glass" designu, celá v čistém LSL. Vzhled je
# popsaný CSS (modul css), vykreslení jde přes anti-aliased zaoblené tvary
# s alpha blendingem a gradienty (modul gfx). Zobrazuje celý výraz a
# vyhodnotí ho se správnou prioritou operátorů a závorkami. Ovládá se myší
# i klávesnicí; běží jako okno na desktopu i na framebufferu LuxOS.
#
# Výkon: kreslení jde přes neboxované celočíselné kernely, plocha se
# překresluje jen při změně (dirty), display.present uklízí paměť každý
# snímek (jinak konzervativní GC drží staré snímky) a d.wait_frame()
# stropuje FPS. Paměť tak zůstává konstantní i při plynulém běhu.

load gfx
load display
load css
load input
load time

stylesheet = ".screen { background: linear-gradient(#a78bfa, #8b6ff0); }" + " .panel { background: rgba(255, 255, 255, 0.13); border-radius: 34; }" + " .display { background: rgba(255, 255, 255, 0.20); border-radius: 22; color: #ffffff; }" + " .digit { background: rgba(255, 255, 255, 0.22); border-radius: 20; color: #ffffff; }" + " .paren { background: rgba(255, 255, 255, 0.16); border-radius: 20; color: #ffffff; }" + " .func { background: linear-gradient(#ffb15a, #ff6f61); border-radius: 20; color: #ffffff; }" + " .op { background: linear-gradient(#ff8fa3, #ff5f7e); border-radius: 20; color: #ffffff; }" + " .equals { background: linear-gradient(#5ad1ff, #22aaff); border-radius: 20; color: #ffffff; }"

win_w = 380
win_h = 680
margin = 24
gap = 12
btn = 74
step = 86
grid_y = 150

function make_button(label, style, col, row, span):
    x = margin + col * step
    y = grid_y + row * step
    width = btn
    if span == 2:
        width = btn * 2 + gap
    end
    made = {}
    made["label"] = label
    made["style"] = style
    made["x"] = x
    made["y"] = y
    made["w"] = width
    made["h"] = btn
    made["hover"] = False
    return made
end

function build_buttons():
    created = []
    created.append(make_button("C", "func", 0, 0, 1))
    created.append(make_button("(", "paren", 1, 0, 1))
    created.append(make_button(")", "paren", 2, 0, 1))
    created.append(make_button("/", "op", 3, 0, 1))
    created.append(make_button("7", "digit", 0, 1, 1))
    created.append(make_button("8", "digit", 1, 1, 1))
    created.append(make_button("9", "digit", 2, 1, 1))
    created.append(make_button("*", "op", 3, 1, 1))
    created.append(make_button("4", "digit", 0, 2, 1))
    created.append(make_button("5", "digit", 1, 2, 1))
    created.append(make_button("6", "digit", 2, 2, 1))
    created.append(make_button("-", "op", 3, 2, 1))
    created.append(make_button("1", "digit", 0, 3, 1))
    created.append(make_button("2", "digit", 1, 3, 1))
    created.append(make_button("3", "digit", 2, 3, 1))
    created.append(make_button("+", "op", 3, 3, 1))
    created.append(make_button("0", "digit", 0, 4, 2))
    created.append(make_button(".", "digit", 2, 4, 1))
    created.append(make_button("=", "equals", 0, 5, 2))
    return created
end

# --- výraz: rekurzivní vyhodnocení se správnou prioritou -----------------
function ev_peek(state):
    text = String(state["text"])
    p = state["pos"]
    if p < state["len"]:
        return text[p:p + 1]
    end
    return ""
end

function ev_number(state):
    text = String(state["text"])
    p = state["pos"]
    startp = p
    while p < state["len"]:
        ch = text[p:p + 1]
        code = ord(ch)
        if (code >= 48 and code <= 57) or ch == ".":
            p += 1
        else:
            break
        end
    end
    state["pos"] = p
    if p == startp:
        state["error"] = True
        return 0.0
    end
    return Float(text[startp:p])
end

function ev_factor(state):
    ch = ev_peek(state)
    if ch == "(":
        state["pos"] = state["pos"] + 1
        inner = ev_expr(state)
        if ev_peek(state) == ")":
            state["pos"] = state["pos"] + 1
        end
        return inner
    elif ch == "-":
        state["pos"] = state["pos"] + 1
        return 0.0 - ev_factor(state)
    end
    return ev_number(state)
end

function ev_term(state):
    value = ev_factor(state)
    loop:
        ch = ev_peek(state)
        if ch == "*":
            state["pos"] = state["pos"] + 1
            value = value * ev_factor(state)
        elif ch == "/":
            state["pos"] = state["pos"] + 1
            divisor = ev_factor(state)
            if divisor == 0.0:
                state["error"] = True
                return 0.0
            end
            value = value / divisor
        else:
            break
        end
    end
    return value
end

function ev_expr(state):
    value = ev_term(state)
    loop:
        ch = ev_peek(state)
        if ch == "+":
            state["pos"] = state["pos"] + 1
            value = value + ev_term(state)
        elif ch == "-":
            state["pos"] = state["pos"] + 1
            value = value - ev_term(state)
        else:
            break
        end
    end
    return value
end

function evaluate(text):
    parsed_state = {}
    parsed_state["text"] = text
    parsed_state["len"] = len(text)
    parsed_state["pos"] = 0
    parsed_state["error"] = False
    result = ev_expr(parsed_state)
    if parsed_state["error"] or parsed_state["pos"] < parsed_state["len"]:
        return 0.0 / 0.0
    end
    return result
end

function format_number(value):
    if value != value:
        return "Error"
    end
    whole = Int(value)
    if __lsl_float_from_int(whole) == value and value < 1000000000000.0 and value > 0.0 - 1000000000000.0:
        return String(whole)
    end
    text = String(value)
    if len(text) > 11:
        text = text[0:11]
    end
    return text
end

function press(state, label):
    current_entry = String(state["entry"])
    if label == "C":
        state["entry"] = ""
    elif label == "=":
        state["entry"] = format_number(evaluate(current_entry))
    else:
        if current_entry == "Error":
            current_entry = ""
        end
        if len(current_entry) < 24:
            state["entry"] = current_entry + label
        end
    end
    return None
end

# --- vykreslení přes CSS -------------------------------------------------
# Resolve each button's CSS class into concrete numbers once, so the hot
# draw path never re-parses stylesheet strings.
function resolve_styles(buttons, sheet):
    for button in buttons:
        props = css.rule(sheet, String(button["style"]))
        background = css.value(props, "background", "")
        button["radius"] = css.number(css.value(props, "border-radius", "20"))
        button["text_color"] = css.color(css.value(props, "color", "#ffffff"))
        if css.is_gradient(background):
            button["gradient"] = True
            button["top"] = css.gradient_top(background)
            button["bottom"] = css.gradient_bottom(background)
        else:
            button["gradient"] = False
            button["fill"] = css.color(background)
            button["fill_alpha"] = css.alpha(background)
        end
    end
    return None
end

function draw_button(pixels, width, height, button):
    button_x = button["x"]
    button_y = button["y"]
    bw = button["w"]
    bh = button["h"]
    radius = button["radius"]
    if button["gradient"]:
        top = button["top"]
        bottom = button["bottom"]
        call gfx.raster_round_rect(pixels, width, height, button_x + 2, button_y + 6, bw, bh, radius, bottom, 70, 10)
        call gfx.raster_round_rect_grad(pixels, width, height, button_x, button_y, bw, bh, radius, top, bottom, 255, 1.4)
    else:
        call gfx.raster_round_rect(pixels, width, height, button_x, button_y, bw, bh, radius, button["fill"], button["fill_alpha"], 1.4)
    end
    caption = String(button["label"])
    label_x = button_x + (bw - len(caption) * 16) // 2
    label_y = button_y + (bh - 32) // 2
    call gfx.raster_text_aa(pixels, width, height, label_x, label_y, caption, button["text_color"], 255, 2)
    return None
end

# The static scene (gradient, frosted panels, shadows, all buttons) —
# drawn once into a backdrop surface, then reused every frame.
function draw_backdrop(pixels, width, height, sheet, buttons):
    screen_props = css.rule(sheet, "screen")
    screen_bg = css.value(screen_props, "background", "")
    call gfx.raster_gradient(pixels, width, height, css.gradient_top(screen_bg), css.gradient_bottom(screen_bg))
    panel_props = css.rule(sheet, "panel")
    panel_radius = css.number(css.value(panel_props, "border-radius", "34"))
    panel_alpha = css.alpha(css.value(panel_props, "background", ""))
    call gfx.raster_shadow(pixels, width, height, 12, 22, 356, 648, panel_radius, gfx.rgb(60, 40, 100), 80, 22)
    call gfx.raster_round_rect(pixels, width, height, 12, 16, 356, 648, panel_radius, 16777215, panel_alpha, 1.4)
    display_props = css.rule(sheet, "display")
    display_radius = css.number(css.value(display_props, "border-radius", "22"))
    display_alpha = css.alpha(css.value(display_props, "background", ""))
    call gfx.raster_round_rect(pixels, width, height, 32, 40, 316, 84, display_radius, 16777215, display_alpha, 1.4)
    for button in buttons:
        call draw_button(pixels, width, height, button)
    end
    return None
end

# Fast per-frame draw: copy the cached backdrop, then only the display
# text and any hover highlight change.
function draw_frame(pixels, width, height, backdrop_pixels, buttons, state):
    call gfx.raster_blit(pixels, width, height, backdrop_pixels, width, height, 0, 0)
    shown = String(state["entry"])
    if shown == "":
        shown = "0"
    end
    scale = 3
    if len(shown) * 24 > 296:
        scale = 2
    end
    if len(shown) * 16 > 296:
        scale = 1
    end
    text_x = 348 - 16 - len(shown) * 8 * scale
    text_y = 40 + (84 - 16 * scale) // 2
    call gfx.raster_text_aa(pixels, width, height, text_x, text_y, shown, 16777215, 255, scale)
    for button in buttons:
        if button["hover"]:
            call gfx.raster_round_rect(pixels, width, height, button["x"], button["y"], button["w"], button["h"], button["radius"], 16777215, 45, 1.4)
        end
    end
    return None
end

# --- aplikace ------------------------------------------------------------
sheet = css.parse(stylesheet)
d = display.open(win_w, win_h, "Kalkulačka")
screen = gfx.surface(d.width, d.height, 0)
buttons = build_buttons()
call resolve_styles(buttons, sheet)
backdrop = gfx.surface(d.width, d.height, 0)
call draw_backdrop(backdrop.pixels, backdrop.width, backdrop.height, sheet, buttons)

state = {}
state["entry"] = ""
state["running"] = True

mouse_x = 0
mouse_y = 0
dirty = True

function key_label(code):
    # Top-row digits (2..11) and the numeric keypad have different evdev
    # codes; map both. Keypad: 7/8/9=71/72/73, 4/5/6=75/76/77,
    # 1/2/3=79/80/81, 0=82, and the keypad operators/enter/dot below.
    if code >= 2 and code <= 10:
        return String(code - 1)
    elif code == 11:
        return "0"
    elif code == 71 or code == 72 or code == 73:
        return String(code - 64)
    elif code == 75 or code == 76 or code == 77:
        return String(code - 71)
    elif code == 79 or code == 80 or code == 81:
        return String(code - 78)
    elif code == 82:
        return "0"
    elif code == 52 or code == 83:
        return "."
    elif code == 28 or code == 96 or code == 13:
        return "="
    elif code == 78:
        return "+"
    elif code == 74 or code == 12:
        return "-"
    elif code == 55:
        return "*"
    elif code == 98 or code == 53:
        return "/"
    end
    return ""
end

while state["running"] and not d.should_close():
    for event in d.poll():
        name = event[0]
        a = event[1]
        b = event[2]
        if name == "motion":
            mouse_x = a
            mouse_y = b
            for button in buttons:
                bx = button["x"]
                by = button["y"]
                button["hover"] = a >= bx and b >= by and a < bx + button["w"] and b < by + button["h"]
            end
            dirty = True
        elif name == "button" and a == 1 and b == 0:
            for button in buttons:
                bx = button["x"]
                by = button["y"]
                if mouse_x >= bx and mouse_y >= by and mouse_x < bx + button["w"] and mouse_y < by + button["h"]:
                    call press(state, String(button["label"]))
                end
            end
            dirty = True
        elif name == "key" and b == input.press:
            if a == input.key_esc:
                call press(state, "C")
            elif a == 14:
                entry = String(state["entry"])
                if len(entry) > 0:
                    state["entry"] = entry[0:len(entry) - 1]
                end
            else:
                label = key_label(a)
                if label != "":
                    call press(state, label)
                end
            end
            dirty = True
        elif name == "close":
            state["running"] = False
        end
    end
    # Redraw and present only when something changed. An idle calculator
    # then does almost no per-frame work, which keeps memory flat without
    # relying on the collector (running gc() inside the loop drops X input
    # events, so it is deliberately avoided).
    if dirty:
        call draw_frame(screen.pixels, screen.width, screen.height, backdrop.pixels, buttons, state)
        call d.present(screen.pixels, screen.width, screen.height)
        dirty = False
    end
    call d.wait_frame()
end

call d.close()
print "hotovo"
