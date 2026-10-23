# lsl: internal-abi
# lsl: link libcairo.so.2
# Cairo přímo z LSL (cíl linux-x86_64-gnu): kreslení v obsluze signálu
# draw (cr je cairo_t z GTK) nebo do obrázku (image_surface_create +
# create). Souřadnice a barvy jsou Float (Int se převede); pravidla psaní
# modulu viz glib.lsl.

# cairo_line_cap_t, cairo_line_join_t, cairo_operator_t, cairo_format_t
LINE_CAP_BUTT = 0
LINE_CAP_ROUND = 1
LINE_CAP_SQUARE = 2
LINE_JOIN_MITER = 0
LINE_JOIN_ROUND = 1
LINE_JOIN_BEVEL = 2
OPERATOR_CLEAR = 0
OPERATOR_SOURCE = 1
OPERATOR_OVER = 2
FORMAT_ARGB32 = 0
FORMAT_RGB24 = 1
ANTIALIAS_DEFAULT = 0
ANTIALIAS_NONE = 1
FONT_SLANT_NORMAL = 0
FONT_SLANT_ITALIC = 1
FONT_WEIGHT_NORMAL = 0
FONT_WEIGHT_BOLD = 1
PI = 3.141592653589793

function cstr(text):
    return __lsl_address(text) + 16
end

function ptr(value):
    return __lsl_unbox_int(value)
end

# --- zdroj barvy, čáry ---

function set_source_rgb(cr, red, green, blue):
    return __lsl_qbe_call4(__lsl_symbol("cairo_set_source_rgb"), ptr(cr), Float(red), Float(green), Float(blue))
end

function set_source_rgba(cr, red, green, blue, alpha):
    return __lsl_qbe_call5(__lsl_symbol("cairo_set_source_rgba"), ptr(cr), Float(red), Float(green), Float(blue), Float(alpha))
end

# Barva ze seznamu [r, g, b, a] (gtk.widget_get_color).
function set_source_color(cr, color):
    return set_source_rgba(cr, color[0], color[1], color[2], color[3])
end

function set_line_width(cr, width):
    return __lsl_qbe_call2(__lsl_symbol("cairo_set_line_width"), ptr(cr), Float(width))
end

function get_line_width(cr):
    return __lsl_qbe_fcall1(__lsl_symbol("cairo_get_line_width"), ptr(cr))
end

function set_line_cap(cr, cap):
    return __lsl_qbe_call2(__lsl_symbol("cairo_set_line_cap"), ptr(cr), ptr(cap))
end

function set_line_join(cr, join):
    return __lsl_qbe_call2(__lsl_symbol("cairo_set_line_join"), ptr(cr), ptr(join))
end

function set_operator(cr, operator):
    return __lsl_qbe_call2(__lsl_symbol("cairo_set_operator"), ptr(cr), ptr(operator))
end

function set_antialias(cr, antialias):
    return __lsl_qbe_call2(__lsl_symbol("cairo_set_antialias"), ptr(cr), ptr(antialias))
end

# Čárkování: délky úseků [kresli, mezera, …] a posun; prázdný seznam ruší.
function set_dash(cr, lengths, offset):
    count = len(lengths)
    bytes = __lsl_byte_zeros(8 * count + 8)
    data = __lsl_qbe_load64(__lsl_address(bytes) + 24)
    index = 0
    while index < count:
        __lsl_qbe_store64(data + 8 * index, __lsl_float_bits(Float(lengths[index])))
        index += 1
    end
    return __lsl_qbe_call4(__lsl_symbol("cairo_set_dash"), ptr(cr), data, count, Float(offset))
end

# --- cesty ---

function new_path(cr):
    return __lsl_qbe_call1(__lsl_symbol("cairo_new_path"), ptr(cr))
end

function close_path(cr):
    return __lsl_qbe_call1(__lsl_symbol("cairo_close_path"), ptr(cr))
end

function move_to(cr, x, y):
    return __lsl_qbe_call3(__lsl_symbol("cairo_move_to"), ptr(cr), Float(x), Float(y))
end

function line_to(cr, x, y):
    return __lsl_qbe_call3(__lsl_symbol("cairo_line_to"), ptr(cr), Float(x), Float(y))
end

function rel_move_to(cr, dx, dy):
    return __lsl_qbe_call3(__lsl_symbol("cairo_rel_move_to"), ptr(cr), Float(dx), Float(dy))
end

function rel_line_to(cr, dx, dy):
    return __lsl_qbe_call3(__lsl_symbol("cairo_rel_line_to"), ptr(cr), Float(dx), Float(dy))
end

function curve_to(cr, x1, y1, x2, y2, x3, y3):
    return __lsl_qbe_call7(__lsl_symbol("cairo_curve_to"), ptr(cr), Float(x1), Float(y1), Float(x2), Float(y2), Float(x3), Float(y3))
end

function rectangle(cr, x, y, width, height):
    return __lsl_qbe_call5(__lsl_symbol("cairo_rectangle"), ptr(cr), Float(x), Float(y), Float(width), Float(height))
end

# Oblouk se středem [xc, yc] a poloměrem od úhlu angle1 do angle2 (radiány).
function arc(cr, xc, yc, radius, angle1, angle2):
    return __lsl_qbe_call6(__lsl_symbol("cairo_arc"), ptr(cr), Float(xc), Float(yc), Float(radius), Float(angle1), Float(angle2))
end

function arc_negative(cr, xc, yc, radius, angle1, angle2):
    return __lsl_qbe_call6(__lsl_symbol("cairo_arc_negative"), ptr(cr), Float(xc), Float(yc), Float(radius), Float(angle1), Float(angle2))
end

# Obdélník se zaoblenými rohy (dlaždice, zvýraznění dne).
function rounded_rectangle(cr, x, y, width, height, radius):
    r = Float(radius)
    call new_path(cr)
    call arc(cr, Float(x) + Float(width) - r, Float(y) + r, r, -PI / 2.0, 0.0)
    call arc(cr, Float(x) + Float(width) - r, Float(y) + Float(height) - r, r, 0.0, PI / 2.0)
    call arc(cr, Float(x) + r, Float(y) + Float(height) - r, r, PI / 2.0, PI)
    call arc(cr, Float(x) + r, Float(y) + r, r, PI, 3.0 * PI / 2.0)
    return close_path(cr)
end

function fill(cr):
    return __lsl_qbe_call1(__lsl_symbol("cairo_fill"), ptr(cr))
end

function fill_preserve(cr):
    return __lsl_qbe_call1(__lsl_symbol("cairo_fill_preserve"), ptr(cr))
end

function stroke(cr):
    return __lsl_qbe_call1(__lsl_symbol("cairo_stroke"), ptr(cr))
end

function stroke_preserve(cr):
    return __lsl_qbe_call1(__lsl_symbol("cairo_stroke_preserve"), ptr(cr))
end

function paint(cr):
    return __lsl_qbe_call1(__lsl_symbol("cairo_paint"), ptr(cr))
end

function paint_with_alpha(cr, alpha):
    return __lsl_qbe_call2(__lsl_symbol("cairo_paint_with_alpha"), ptr(cr), Float(alpha))
end

function clip(cr):
    return __lsl_qbe_call1(__lsl_symbol("cairo_clip"), ptr(cr))
end

function reset_clip(cr):
    return __lsl_qbe_call1(__lsl_symbol("cairo_reset_clip"), ptr(cr))
end

function save(cr):
    return __lsl_qbe_call1(__lsl_symbol("cairo_save"), ptr(cr))
end

function restore(cr):
    return __lsl_qbe_call1(__lsl_symbol("cairo_restore"), ptr(cr))
end

# --- transformace ---

function translate(cr, tx, ty):
    return __lsl_qbe_call3(__lsl_symbol("cairo_translate"), ptr(cr), Float(tx), Float(ty))
end

function scale(cr, sx, sy):
    return __lsl_qbe_call3(__lsl_symbol("cairo_scale"), ptr(cr), Float(sx), Float(sy))
end

function rotate(cr, angle):
    return __lsl_qbe_call2(__lsl_symbol("cairo_rotate"), ptr(cr), Float(angle))
end

# --- jednoduchý text (bez Pango: ASCII, bez zalamování) ---

function select_font_face(cr, family, slant, weight):
    return __lsl_qbe_call4(__lsl_symbol("cairo_select_font_face"), ptr(cr), cstr(family), ptr(slant), ptr(weight))
end

function set_font_size(cr, size):
    return __lsl_qbe_call2(__lsl_symbol("cairo_set_font_size"), ptr(cr), Float(size))
end

function show_text(cr, text):
    return __lsl_qbe_call2(__lsl_symbol("cairo_show_text"), ptr(cr), cstr(text))
end

# Rozměry textu [x_bearing, y_bearing, width, height, x_advance, y_advance].
function text_extents(cr, text):
    bytes = __lsl_byte_zeros(48)
    data = __lsl_qbe_load64(__lsl_address(bytes) + 24)
    call __lsl_qbe_call3(__lsl_symbol("cairo_text_extents"), ptr(cr), cstr(text), data)
    result = []
    index = 0
    while index < 6:
        result.append(__lsl_float_from_bits(__lsl_qbe_load64(data + 8 * index)))
        index += 1
    end
    return result
end

# --- přechody ---

function pattern_create_linear(x0, y0, x1, y1):
    return __lsl_qbe_call4(__lsl_symbol("cairo_pattern_create_linear"), Float(x0), Float(y0), Float(x1), Float(y1))
end

function pattern_create_radial(cx0, cy0, radius0, cx1, cy1, radius1):
    return __lsl_qbe_call6(__lsl_symbol("cairo_pattern_create_radial"), Float(cx0), Float(cy0), Float(radius0), Float(cx1), Float(cy1), Float(radius1))
end

function pattern_add_color_stop_rgba(pattern, offset, red, green, blue, alpha):
    return __lsl_qbe_call6(__lsl_symbol("cairo_pattern_add_color_stop_rgba"), ptr(pattern), Float(offset), Float(red), Float(green), Float(blue), Float(alpha))
end

function set_source(cr, pattern):
    return __lsl_qbe_call2(__lsl_symbol("cairo_set_source"), ptr(cr), ptr(pattern))
end

function pattern_destroy(pattern):
    return __lsl_qbe_call1(__lsl_symbol("cairo_pattern_destroy"), ptr(pattern))
end

# --- obrázky mimo okno ---

function image_surface_create(format, width, height):
    return __lsl_qbe_call3(__lsl_symbol("cairo_image_surface_create"), ptr(format), ptr(width), ptr(height))
end

function image_surface_create_from_png(path):
    return __lsl_qbe_call1(__lsl_symbol("cairo_image_surface_create_from_png"), cstr(path))
end

function image_surface_get_width(surface):
    return __lsl_qbe_call1(__lsl_symbol("cairo_image_surface_get_width"), ptr(surface))
end

function image_surface_get_height(surface):
    return __lsl_qbe_call1(__lsl_symbol("cairo_image_surface_get_height"), ptr(surface))
end

# cairo_status_t: 0 = CAIRO_STATUS_SUCCESS.
function surface_status(surface):
    return __lsl_qbe_call1(__lsl_symbol("cairo_surface_status"), ptr(surface))
end

function surface_write_to_png(surface, path):
    return __lsl_qbe_call2(__lsl_symbol("cairo_surface_write_to_png"), ptr(surface), cstr(path))
end

function surface_destroy(surface):
    return __lsl_qbe_call1(__lsl_symbol("cairo_surface_destroy"), ptr(surface))
end

function set_source_surface(cr, surface, x, y):
    return __lsl_qbe_call4(__lsl_symbol("cairo_set_source_surface"), ptr(cr), ptr(surface), Float(x), Float(y))
end

function create(surface):
    return __lsl_qbe_call1(__lsl_symbol("cairo_create"), ptr(surface))
end

function destroy(cr):
    return __lsl_qbe_call1(__lsl_symbol("cairo_destroy"), ptr(cr))
end

function status(cr):
    return __lsl_qbe_call1(__lsl_symbol("cairo_status"), ptr(cr))
end

# Pixel obrázku ARGB32 jako číslo 0xAARRGGBB (testy, odečet barvy).
function image_surface_pixel(surface, x, y):
    call __lsl_qbe_call1(__lsl_symbol("cairo_surface_flush"), ptr(surface))
    data = __lsl_qbe_call1(__lsl_symbol("cairo_image_surface_get_data"), ptr(surface))
    stride = __lsl_qbe_call1(__lsl_symbol("cairo_image_surface_get_stride"), ptr(surface))
    return __lsl_qbe_u32(__lsl_qbe_load32(data + ptr(y) * stride + ptr(x) * 4))
end
