# lsl: internal-abi
# lsl: link libpangocairo-1.0.so.0 libpango-1.0.so.0 libgobject-2.0.so.0 libglib-2.0.so.0 libcairo.so.2
# Pango přes cairo přímo z LSL (cíl linux-x86_64-gnu): text s fontem
# systému, zalamováním, výpustkou a značkami v kreslené ploše (obsluha
# draw). Rozměry v pixelech; písmo jako text "Sans Bold 12". Pravidla psaní
# modulu viz glib.lsl.
load glib

SCALE = 1024
# PangoEllipsizeMode, PangoAlignment, PangoWrapMode
ELLIPSIZE_NONE = 0
ELLIPSIZE_START = 1
ELLIPSIZE_MIDDLE = 2
ELLIPSIZE_END = 3
ALIGN_LEFT = 0
ALIGN_CENTER = 1
ALIGN_RIGHT = 2
WRAP_WORD = 0
WRAP_CHAR = 1
WRAP_WORD_CHAR = 2

function ptr(value):
    return __lsl_unbox_int(value)
end

# Rozvržení textu pro cairo kontext; uvolnění layout_unref (nebo nové
# rozvržení v každé obsluze draw a unref na konci).
function cairo_create_layout(cr):
    return __lsl_qbe_call1(__lsl_symbol("pango_cairo_create_layout"), ptr(cr))
end

function layout_unref(layout):
    return glib.object_unref(layout)
end

function layout_set_text(layout, text):
    return __lsl_qbe_call3(__lsl_symbol("pango_layout_set_text"), ptr(layout), glib.cstr(text), -1)
end

function layout_set_markup(layout, markup):
    return __lsl_qbe_call3(__lsl_symbol("pango_layout_set_markup"), ptr(layout), glib.cstr(markup), -1)
end

# Písmo z popisu ("Sans 11", "Cantarell Bold 14", "monospace 9").
function layout_set_font(layout, description):
    font = __lsl_qbe_call1(__lsl_symbol("pango_font_description_from_string"), glib.cstr(description))
    call __lsl_qbe_call2(__lsl_symbol("pango_layout_set_font_description"), ptr(layout), font)
    return __lsl_qbe_call1(__lsl_symbol("pango_font_description_free"), font)
end

# Šířka/výška pro zalamování a výpustku v pixelech (-1 = bez omezení).
function layout_set_width(layout, pixels):
    width = ptr(pixels)
    if width >= 0:
        width = width * 1024
    end
    return __lsl_qbe_call2(__lsl_symbol("pango_layout_set_width"), ptr(layout), width)
end

function layout_set_height(layout, pixels):
    height = ptr(pixels)
    if height >= 0:
        height = height * 1024
    end
    return __lsl_qbe_call2(__lsl_symbol("pango_layout_set_height"), ptr(layout), height)
end

function layout_set_ellipsize(layout, mode):
    return __lsl_qbe_call2(__lsl_symbol("pango_layout_set_ellipsize"), ptr(layout), ptr(mode))
end

function layout_set_alignment(layout, alignment):
    return __lsl_qbe_call2(__lsl_symbol("pango_layout_set_alignment"), ptr(layout), ptr(alignment))
end

function layout_set_wrap(layout, mode):
    return __lsl_qbe_call2(__lsl_symbol("pango_layout_set_wrap"), ptr(layout), ptr(mode))
end

function layout_set_justify(layout, justify):
    return __lsl_qbe_call2(__lsl_symbol("pango_layout_set_justify"), ptr(layout), ptr(justify))
end

function layout_set_single_paragraph_mode(layout, single):
    return __lsl_qbe_call2(__lsl_symbol("pango_layout_set_single_paragraph_mode"), ptr(layout), ptr(single))
end

# Mezera mezi řádky v pixelech, nebo násobek výšky řádku (Float, 0 = vypnuto).
function layout_set_spacing(layout, pixels):
    return __lsl_qbe_call2(__lsl_symbol("pango_layout_set_spacing"), ptr(layout), ptr(pixels) * 1024)
end

function layout_set_line_spacing(layout, factor):
    return __lsl_qbe_call2(__lsl_symbol("pango_layout_set_line_spacing"), ptr(layout), __lsl_qbe_f32(Float(factor)))
end

# [šířka, výška] textu v pixelech.
function layout_get_pixel_size(layout):
    cells = __lsl_byte_zeros(16)
    data = glib.array_data(cells)
    call __lsl_qbe_call3(__lsl_symbol("pango_layout_get_pixel_size"), ptr(layout), data, data + 8)
    return [__lsl_qbe_s32(__lsl_qbe_load32(data)), __lsl_qbe_s32(__lsl_qbe_load32(data + 8))]
end

# Účaří prvního řádku v pixelech od horního okraje.
function layout_get_baseline(layout):
    return __lsl_qbe_s32(__lsl_qbe_call1(__lsl_symbol("pango_layout_get_baseline"), ptr(layout))) // 1024
end

function layout_get_line_count(layout):
    return __lsl_qbe_s32(__lsl_qbe_call1(__lsl_symbol("pango_layout_get_line_count"), ptr(layout)))
end

function layout_is_ellipsized(layout):
    return __lsl_qbe_call1(__lsl_symbol("pango_layout_is_ellipsized"), ptr(layout)) != 0
end

# Vykreslení na aktuální pozici (cairo.move_to) aktuální barvou.
function cairo_show_layout(cr, layout):
    return __lsl_qbe_call2(__lsl_symbol("pango_cairo_show_layout"), ptr(cr), ptr(layout))
end

# Obrys textu jako cesta (fill/stroke v cairo).
function cairo_layout_path(cr, layout):
    return __lsl_qbe_call2(__lsl_symbol("pango_cairo_layout_path"), ptr(cr), ptr(layout))
end

function cairo_update_layout(cr, layout):
    return __lsl_qbe_call2(__lsl_symbol("pango_cairo_update_layout"), ptr(cr), ptr(layout))
end

# Pohodlně: text písmem na pozici; vrací [šířka, výška].
function draw_text(cr, x, y, text, font):
    layout = cairo_create_layout(cr)
    call layout_set_font(layout, font)
    call layout_set_text(layout, text)
    call __lsl_qbe_call3(__lsl_symbol("cairo_move_to"), ptr(cr), Float(x), Float(y))
    call cairo_show_layout(cr, layout)
    size = layout_get_pixel_size(layout)
    call layout_unref(layout)
    return size
end

# Rozměry textu daným písmem bez kreslení: [šířka, výška].
function text_size(cr, text, font):
    layout = cairo_create_layout(cr)
    call layout_set_font(layout, font)
    call layout_set_text(layout, text)
    size = layout_get_pixel_size(layout)
    call layout_unref(layout)
    return size
end
