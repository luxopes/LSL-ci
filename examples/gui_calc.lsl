# Kalkulačka s GUI v čistém LSL — design inspirovaný macOS: černé pozadí,
# kruhová tlačítka, oranžové operátory, velký displej. Ovládá se myší i
# klávesnicí. Běží jako okno na desktopu i na framebufferu LuxOS.
#
# Úsporné a rychlé: plocha se překreslí jen když se něco změní (žádné
# alokace ani present v každém snímku), rasterizace jde přes neboxované
# IntArray kernely.

load gfx
load display
load input
load time

color_bg = 0
color_display = 16777215
color_digit = 3355443
color_digit_hover = 7566195
color_func = 10855845
color_func_hover = 12566463
color_func_text = 0
color_op = 16752394
color_op_hover = 16758080
color_op_text = 16777215
color_op_active_bg = 16777215

margin = 16
gap = 13
diameter = 62
display_height = 150

function make_button(label, kind, col, row, span):
    x = margin + col * (diameter + gap)
    y = display_height + row * (diameter + gap)
    width = diameter
    if span == 2:
        width = diameter * 2 + gap
    end
    made = {}
    made["label"] = label
    made["kind"] = kind
    made["x"] = x
    made["y"] = y
    made["w"] = width
    made["h"] = diameter
    made["span"] = span
    made["hover"] = False
    return made
end

function build_buttons():
    created = []
    created.append(make_button("AC", "func", 0, 0, 1))
    created.append(make_button("+/-", "func", 1, 0, 1))
    created.append(make_button("%", "func", 2, 0, 1))
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
    created.append(make_button("=", "equals", 3, 4, 1))
    return created
end

function is_digit(label):
    return label == "0" or label == "1" or label == "2" or label == "3" or label == "4" or label == "5" or label == "6" or label == "7" or label == "8" or label == "9"
end

function apply_op(a, op, b):
    if op == "+":
        return a + b
    elif op == "-":
        return a - b
    elif op == "*":
        return a * b
    elif op == "/":
        if b == 0.0:
            return 0.0 / 0.0
        end
        return a / b
    end
    return b
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

function press_digit(state, digit):
    entry = String(state["entry"])
    if state["fresh"] or entry == "0":
        state["entry"] = digit
        state["fresh"] = False
    else:
        if len(entry) < 12:
            state["entry"] = entry + digit
        end
    end
    return None
end

function press_dot(state):
    entry = String(state["entry"])
    if state["fresh"]:
        state["entry"] = "0."
        state["fresh"] = False
    else:
        if entry.find(".") < 0:
            state["entry"] = entry + "."
        end
    end
    return None
end

function press_operator(state, op):
    value = Float(String(state["entry"]))
    if state["op"] != "" and not state["fresh"]:
        result = apply_op(state["acc"], String(state["op"]), value)
        state["acc"] = result
        state["entry"] = format_number(result)
    else:
        state["acc"] = value
    end
    state["op"] = op
    state["fresh"] = True
    return None
end

function press_equals(state):
    if state["op"] != "":
        value = Float(String(state["entry"]))
        result = apply_op(state["acc"], String(state["op"]), value)
        state["entry"] = format_number(result)
        state["acc"] = result
        state["op"] = ""
        state["fresh"] = True
    end
    return None
end

function press_backspace(state):
    entry = String(state["entry"])
    if len(entry) <= 1:
        state["entry"] = "0"
    elif len(entry) == 2 and entry[0:1] == "-":
        state["entry"] = "0"
    else:
        state["entry"] = entry[0:len(entry) - 1]
    end
    return None
end

function dispatch(state, label):
    if is_digit(label):
        call press_digit(state, label)
    elif label == ".":
        call press_dot(state)
    elif label == "AC":
        state["entry"] = "0"
        state["acc"] = 0.0
        state["op"] = ""
        state["fresh"] = True
    elif label == "+/-":
        state["entry"] = format_number(0.0 - Float(String(state["entry"])))
    elif label == "%":
        state["entry"] = format_number(Float(String(state["entry"])) / 100.0)
    elif label == "=":
        call press_equals(state)
    else:
        call press_operator(state, label)
    end
    return None
end

function key_label(code):
    if code >= 2 and code <= 10:
        return String(code - 1)
    elif code == 11:
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

function draw(pixels, width, height, buttons, state):
    call gfx.raster_clear(pixels, width, height, color_bg)
    entry = String(state["entry"])
    scale = 4
    if len(entry) * 32 > 320 - 2 * margin:
        scale = 3
    end
    if len(entry) * 24 > 320 - 2 * margin:
        scale = 2
    end
    text_w = len(entry) * 8 * scale
    text_x = 320 - margin - text_w
    text_y = display_height - 24 - 16 * scale
    call gfx.raster_text_scaled(pixels, width, height, text_x, text_y, entry, color_display, scale)

    for button in buttons:
        kind = button["kind"]
        caption = String(button["label"])
        fill = color_digit
        text_color = color_display
        if kind == "digit":
            fill = color_digit
            if button["hover"]:
                fill = color_digit_hover
            end
        elif kind == "func":
            fill = color_func
            text_color = color_func_text
            if button["hover"]:
                fill = color_func_hover
            end
        else:
            fill = color_op
            text_color = color_op_text
            if kind == "op" and String(state["op"]) == caption:
                fill = color_op_active_bg
                text_color = color_op
            elif button["hover"]:
                fill = color_op_hover
            end
        end
        button_x = button["x"]
        button_y = button["y"]
        bw = button["w"]
        radius = diameter // 2
        if button["span"] == 2:
            call gfx.raster_fill_pill(pixels, width, height, button_x, button_y, bw, diameter, fill)
        else:
            call gfx.raster_fill_circle(pixels, width, height, button_x + radius, button_y + radius, radius, fill)
        end
        label_scale = 2
        label_w = len(caption) * 8 * label_scale
        label_x = button_x + radius - label_w // 2
        label_y = button_y + radius - 8 * label_scale
        call gfx.raster_text_scaled(pixels, width, height, label_x, label_y, caption, text_color, label_scale)
    end
    return None
end

d = display.open(320, 528, "Kalkulačka")
screen = gfx.surface(d.width, d.height, color_bg)
buttons = build_buttons()

state = {}
state["entry"] = "0"
state["acc"] = 0.0
state["op"] = ""
state["fresh"] = True
state["running"] = True

mouse_x = 0
mouse_y = 0
dirty = True

while state["running"] and not d.should_close():
    events = d.poll()
    for event in events:
        name = event[0]
        a = event[1]
        b = event[2]
        if name == "motion":
            mouse_x = a
            mouse_y = b
            for button in buttons:
                bx = button["x"]
                by = button["y"]
                inside = a >= bx and b >= by and a < bx + button["w"] and b < by + button["h"]
                button["hover"] = inside
            end
            dirty = True
        elif name == "button" and a == 1 and b == 0:
            for button in buttons:
                bx = button["x"]
                by = button["y"]
                if mouse_x >= bx and mouse_y >= by and mouse_x < bx + button["w"] and mouse_y < by + button["h"]:
                    call dispatch(state, String(button["label"]))
                end
            end
            dirty = True
        elif name == "key" and b == input.press:
            if a == input.key_esc:
                call dispatch(state, "AC")
            elif a == 14:
                call press_backspace(state)
            else:
                label = key_label(a)
                if label != "":
                    call dispatch(state, label)
                end
            end
            dirty = True
        elif name == "close":
            state["running"] = False
        end
    end
    if dirty:
        call draw(screen.pixels, screen.width, screen.height, buttons, state)
        call d.present(screen.pixels, screen.width, screen.height)
        dirty = False
    end
    call time.sleep(0.012)
end

call d.close()
print "hotovo"
