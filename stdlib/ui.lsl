# Widget toolkit on top of gfx + display. Widgets are Dictionaries and
# every entry point is a free function, because LSL only dispatches
# methods on statically typed locals — a Surface or Display reached
# through a parameter cannot have its methods called. So drawing goes
# through gfx.raster_* free functions on the raw pixel buffer, and the
# application owns the display/surface locals and the frame loop.
#
# Click callbacks receive (widget, state). state is a shared Dictionary
# the app and callbacks both read and write (callbacks cannot touch an
# instance's fields, but Dictionary mutation through a parameter works).

load gfx
load input

# Default theme (0xRRGGBB).
color_background = 2500900
color_text = 15921906
color_muted = 9081025
color_accent = 3438838
color_accent_hover = 4491526
color_accent_text = 16777215
color_border = 5197647
color_field = 1447446

function label(x, y, text):
    widget = {}
    widget["type"] = "label"
    widget["x"] = Int(x)
    widget["y"] = Int(y)
    widget["w"] = gfx.text_width(text)
    widget["h"] = 16
    widget["text"] = text
    return widget
end

function button(x, y, w, h, text, on_click):
    widget = {}
    widget["type"] = "button"
    widget["x"] = Int(x)
    widget["y"] = Int(y)
    widget["w"] = Int(w)
    widget["h"] = Int(h)
    widget["text"] = text
    widget["on_click"] = on_click
    widget["hover"] = False
    return widget
end

function checkbox(x, y, text, checked):
    widget = {}
    widget["type"] = "checkbox"
    widget["x"] = Int(x)
    widget["y"] = Int(y)
    widget["w"] = gfx.text_width(text) + 26
    widget["h"] = 18
    widget["text"] = text
    widget["checked"] = checked
    return widget
end

function new_state():
    state = {}
    state["running"] = True
    state["key"] = 0
    state["mouse_x"] = 0
    state["mouse_y"] = 0
    return state
end

function contains(widget, px, py):
    wx = widget["x"]
    wy = widget["y"]
    return px >= wx and py >= wy and px < wx + widget["w"] and py < wy + widget["h"]
end

# Apply one batch of display events to the widgets and shared state:
# update hover, fire button callbacks on release, toggle checkboxes, and
# record the last key / running flag. Pure data — no surface needed.
function process(widgets, state, events):
    for event in events:
        name = event[0]
        a = event[1]
        b = event[2]
        if name == "motion":
            state["mouse_x"] = a
            state["mouse_y"] = b
            for widget in widgets:
                if widget["type"] == "button":
                    widget["hover"] = contains(widget, a, b)
                end
            end
        elif name == "button" and a == 1 and b == 0:
            mx = state["mouse_x"]
            my = state["mouse_y"]
            for widget in widgets:
                if contains(widget, mx, my):
                    kind = widget["type"]
                    if kind == "button":
                        handler = widget["on_click"]
                        call handler(widget, state)
                    elif kind == "checkbox":
                        widget["checked"] = not widget["checked"]
                    end
                end
            end
        elif name == "key" and b == input.press:
            state["key"] = a
            if a == input.key_esc:
                state["running"] = False
            end
        elif name == "close":
            state["running"] = False
        end
    end
    return None
end

# Draw every widget onto a raw pixel buffer (surface.pixels/width/height).
function paint(pixels, width, height, widgets, background):
    call gfx.raster_clear(pixels, width, height, background)
    for widget in widgets:
        call paint_widget(pixels, width, height, widget)
    end
    return None
end

function paint_widget(pixels, width, height, widget):
    kind = widget["type"]
    x = widget["x"]
    y = widget["y"]
    if kind == "label":
        call gfx.raster_text(pixels, width, height, x, y, widget["text"], color_text)
    elif kind == "button":
        fill = color_accent
        if widget["hover"]:
            fill = color_accent_hover
        end
        call gfx.raster_fill_rect(pixels, width, height, x, y, widget["w"], widget["h"], fill)
        call gfx.raster_rect(pixels, width, height, x, y, widget["w"], widget["h"], color_border)
        text_x = x + (widget["w"] - gfx.text_width(widget["text"])) // 2
        text_y = y + (widget["h"] - 16) // 2
        call gfx.raster_text(pixels, width, height, text_x, text_y, widget["text"], color_accent_text)
    elif kind == "checkbox":
        call gfx.raster_fill_rect(pixels, width, height, x, y, 18, 18, color_field)
        call gfx.raster_rect(pixels, width, height, x, y, 18, 18, color_border)
        if widget["checked"]:
            call gfx.raster_line(pixels, width, height, x + 4, y + 9, x + 8, y + 13, color_accent_text)
            call gfx.raster_line(pixels, width, height, x + 8, y + 13, x + 14, y + 4, color_accent_text)
        end
        call gfx.raster_text(pixels, width, height, x + 26, y + 1, widget["text"], color_text)
    end
    return None
end
