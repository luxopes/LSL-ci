# lsl: internal-abi
# lsl: link libgtk-3.so.0 libgdk-3.so.0 libgdk_pixbuf-2.0.so.0 libgio-2.0.so.0 libgobject-2.0.so.0 libglib-2.0.so.0
# GTK 3 přímo z LSL (cíl linux-x86_64-gnu): program je dynamicky linkovaný
# proti knihovnám systému a volá je bez mezivrstvy. Hodnoty widgetů jsou
# surové ukazatele (Int). Obsluhy signálů jsou běžné funkce LSL (most
# zpětných volání: modul glib). Pravidla psaní viz glib.lsl.
load glib

# Orientace a zarovnání (GtkOrientation, GtkAlign).
HORIZONTAL = 0
VERTICAL = 1
ALIGN_FILL = 0
ALIGN_START = 1
ALIGN_END = 2
ALIGN_CENTER = 3

# Počet argumentů signálu před instancí (obsluha dostane je a nakonec widget).
SIGNAL_ARGS = {"draw":1, "key-press-event":1, "key-release-event":1, "button-press-event":1, "button-release-event":1, "delete-event":1, "size-allocate":1, "scroll-event":1, "motion-notify-event":1, "enter-notify-event":1, "leave-notify-event":1, "focus-in-event":1, "focus-out-event":1, "configure-event":1, "window-state-event":1, "map-event":1, "unmap-event":1, "row-selected":1, "row-activated":1, "state-set":1, "notify":1, "icon-press":2, "query-tooltip":4}

function cstr(text):
    return __lsl_address(text) + 16
end

function ptr(value):
    return __lsl_unbox_int(value)
end

function from_c(address):
    return glib.from_c(address)
end

function init():
    return __lsl_qbe_call2(__lsl_symbol("gtk_init"), 0, 0)
end

function main():
    # Výstup programu (roura, journal) musí jít ven hned, ne až při ukončení.
    call glib.unbuffered()
    return __lsl_qbe_call0(__lsl_symbol("gtk_main"))
end

function main_quit():
    return __lsl_qbe_call0(__lsl_symbol("gtk_main_quit"))
end

function version():
    return [__lsl_qbe_call0(__lsl_symbol("gtk_get_major_version")), __lsl_qbe_call0(__lsl_symbol("gtk_get_minor_version")), __lsl_qbe_call0(__lsl_symbol("gtk_get_micro_version"))]
end

# --- okna a kontejnery ---

function window_new(title):
    window = __lsl_qbe_call1(__lsl_symbol("gtk_window_new"), 0)
    call __lsl_qbe_call2(__lsl_symbol("gtk_window_set_title"), window, cstr(title))
    return window
end

function window_set_default_size(window, width, height):
    return __lsl_qbe_call3(__lsl_symbol("gtk_window_set_default_size"), ptr(window), ptr(width), ptr(height))
end

function window_set_title(window, title):
    return __lsl_qbe_call2(__lsl_symbol("gtk_window_set_title"), ptr(window), cstr(title))
end

function box_new(orientation, spacing):
    return __lsl_qbe_call2(__lsl_symbol("gtk_box_new"), ptr(orientation), ptr(spacing))
end

function box_pack_start(box, child, expand, fill, padding):
    return __lsl_qbe_call5(__lsl_symbol("gtk_box_pack_start"), ptr(box), ptr(child), ptr(expand), ptr(fill), ptr(padding))
end

function box_pack_end(box, child, expand, fill, padding):
    return __lsl_qbe_call5(__lsl_symbol("gtk_box_pack_end"), ptr(box), ptr(child), ptr(expand), ptr(fill), ptr(padding))
end

function container_add(container, child):
    return __lsl_qbe_call2(__lsl_symbol("gtk_container_add"), ptr(container), ptr(child))
end

function container_set_border_width(container, width):
    return __lsl_qbe_call2(__lsl_symbol("gtk_container_set_border_width"), ptr(container), ptr(width))
end

# --- widgety ---

function label_new(text):
    return __lsl_qbe_call1(__lsl_symbol("gtk_label_new"), cstr(text))
end

function label_set_text(label, text):
    return __lsl_qbe_call2(__lsl_symbol("gtk_label_set_text"), ptr(label), cstr(text))
end

function label_set_markup(label, markup):
    return __lsl_qbe_call2(__lsl_symbol("gtk_label_set_markup"), ptr(label), cstr(markup))
end

function label_get_text(label):
    return from_c(__lsl_qbe_call1(__lsl_symbol("gtk_label_get_text"), ptr(label)))
end

function button_new(text):
    return __lsl_qbe_call1(__lsl_symbol("gtk_button_new_with_label"), cstr(text))
end

function button_set_label(button, text):
    return __lsl_qbe_call2(__lsl_symbol("gtk_button_set_label"), ptr(button), cstr(text))
end

function button_clicked(button):
    return __lsl_qbe_call1(__lsl_symbol("gtk_button_clicked"), ptr(button))
end

function image_new_from_icon_name(name, size):
    return __lsl_qbe_call2(__lsl_symbol("gtk_image_new_from_icon_name"), cstr(name), ptr(size))
end

function entry_new():
    return __lsl_qbe_call0(__lsl_symbol("gtk_entry_new"))
end

function entry_get_text(entry):
    return from_c(__lsl_qbe_call1(__lsl_symbol("gtk_entry_get_text"), ptr(entry)))
end

function entry_set_text(entry, text):
    return __lsl_qbe_call2(__lsl_symbol("gtk_entry_set_text"), ptr(entry), cstr(text))
end

function switch_new():
    return __lsl_qbe_call0(__lsl_symbol("gtk_switch_new"))
end

function switch_get_active(switch):
    return __lsl_qbe_call1(__lsl_symbol("gtk_switch_get_active"), ptr(switch)) != 0
end

function switch_set_active(switch, active):
    return __lsl_qbe_call2(__lsl_symbol("gtk_switch_set_active"), ptr(switch), ptr(active))
end

function widget_show_all(widget):
    return __lsl_qbe_call1(__lsl_symbol("gtk_widget_show_all"), ptr(widget))
end

function widget_show(widget):
    return __lsl_qbe_call1(__lsl_symbol("gtk_widget_show"), ptr(widget))
end

function widget_hide(widget):
    return __lsl_qbe_call1(__lsl_symbol("gtk_widget_hide"), ptr(widget))
end

function widget_destroy(widget):
    return __lsl_qbe_call1(__lsl_symbol("gtk_widget_destroy"), ptr(widget))
end

function widget_set_size_request(widget, width, height):
    return __lsl_qbe_call3(__lsl_symbol("gtk_widget_set_size_request"), ptr(widget), ptr(width), ptr(height))
end

function widget_set_halign(widget, align):
    return __lsl_qbe_call2(__lsl_symbol("gtk_widget_set_halign"), ptr(widget), ptr(align))
end

function widget_set_valign(widget, align):
    return __lsl_qbe_call2(__lsl_symbol("gtk_widget_set_valign"), ptr(widget), ptr(align))
end

function widget_set_margin(widget, margin):
    w = ptr(widget)
    m = ptr(margin)
    call __lsl_qbe_call2(__lsl_symbol("gtk_widget_set_margin_start"), w, m)
    call __lsl_qbe_call2(__lsl_symbol("gtk_widget_set_margin_end"), w, m)
    call __lsl_qbe_call2(__lsl_symbol("gtk_widget_set_margin_top"), w, m)
    call __lsl_qbe_call2(__lsl_symbol("gtk_widget_set_margin_bottom"), w, m)
    return 0
end

function widget_set_sensitive(widget, sensitive):
    return __lsl_qbe_call2(__lsl_symbol("gtk_widget_set_sensitive"), ptr(widget), ptr(sensitive))
end

function widget_set_tooltip(widget, text):
    return __lsl_qbe_call2(__lsl_symbol("gtk_widget_set_tooltip_text"), ptr(widget), cstr(text))
end

function widget_set_name(widget, name):
    return __lsl_qbe_call2(__lsl_symbol("gtk_widget_set_name"), ptr(widget), cstr(name))
end

function widget_add_class(widget, name):
    context = __lsl_qbe_call1(__lsl_symbol("gtk_widget_get_style_context"), ptr(widget))
    return __lsl_qbe_call2(__lsl_symbol("gtk_style_context_add_class"), context, cstr(name))
end

function widget_remove_class(widget, name):
    context = __lsl_qbe_call1(__lsl_symbol("gtk_widget_get_style_context"), ptr(widget))
    return __lsl_qbe_call2(__lsl_symbol("gtk_style_context_remove_class"), context, cstr(name))
end

# CSS pro celou obrazovku (GTK_STYLE_PROVIDER_PRIORITY_APPLICATION = 600);
# vrací provider pro css_remove (přepnutí motivu za běhu).
function css_load(css):
    provider = __lsl_qbe_call0(__lsl_symbol("gtk_css_provider_new"))
    call __lsl_qbe_call4(__lsl_symbol("gtk_css_provider_load_from_data"), provider, cstr(css), -1, 0)
    screen = __lsl_qbe_call0(__lsl_symbol("gdk_screen_get_default"))
    call __lsl_qbe_call3(__lsl_symbol("gtk_style_context_add_provider_for_screen"), screen, provider, 600)
    return provider
end

# --- signály a zdroje hlavní smyčky ---

# Připojí obsluhu signálu; obsluha dostane argumenty signálu a nakonec
# widget, např. on_click(button) nebo on_draw(cr, area).
function connect(widget, signal, handler):
    return glib.signal_connect(widget, signal, handler, SIGNAL_ARGS.get(signal, 0))
end

function timeout_add(interval, handler):
    return glib.timeout_add(interval, handler)
end

function idle_add(handler):
    return glib.idle_add(handler)
end

function source_remove(id):
    return glib.source_remove(id)
end

# Jeden průchod čekajícími událostmi (testy bez gtk.main).
function pump():
    while __lsl_qbe_call0(__lsl_symbol("gtk_events_pending")) != 0:
        call __lsl_qbe_call1(__lsl_symbol("gtk_main_iteration_do"), 0)
    end
    return 0
end

# --- mřížka, posuvníky, obrázky, tlačítka ---

function grid_new():
    return __lsl_qbe_call0(__lsl_symbol("gtk_grid_new"))
end

function grid_attach(grid, child, left, top, width, height):
    return __lsl_qbe_call6(__lsl_symbol("gtk_grid_attach"), ptr(grid), ptr(child), ptr(left), ptr(top), ptr(width), ptr(height))
end

function grid_set_row_spacing(grid, spacing):
    return __lsl_qbe_call2(__lsl_symbol("gtk_grid_set_row_spacing"), ptr(grid), ptr(spacing))
end

function grid_set_column_spacing(grid, spacing):
    return __lsl_qbe_call2(__lsl_symbol("gtk_grid_set_column_spacing"), ptr(grid), ptr(spacing))
end

function grid_set_column_homogeneous(grid, homogeneous):
    return __lsl_qbe_call2(__lsl_symbol("gtk_grid_set_column_homogeneous"), ptr(grid), ptr(homogeneous))
end

function grid_set_row_homogeneous(grid, homogeneous):
    return __lsl_qbe_call2(__lsl_symbol("gtk_grid_set_row_homogeneous"), ptr(grid), ptr(homogeneous))
end

# Posuvník s rozsahem (jas, hlasitost); hodnoty jsou Float.
function scale_new_with_range(orientation, minimum, maximum, step):
    return __lsl_qbe_call4(__lsl_symbol("gtk_scale_new_with_range"), ptr(orientation), Float(minimum), Float(maximum), Float(step))
end

function scale_set_draw_value(scale, draw):
    return __lsl_qbe_call2(__lsl_symbol("gtk_scale_set_draw_value"), ptr(scale), ptr(draw))
end

function range_get_value(range):
    return __lsl_qbe_fcall1(__lsl_symbol("gtk_range_get_value"), ptr(range))
end

function range_set_value(range, value):
    return __lsl_qbe_call2(__lsl_symbol("gtk_range_set_value"), ptr(range), Float(value))
end

function range_set_increments(range, step, page):
    return __lsl_qbe_call3(__lsl_symbol("gtk_range_set_increments"), ptr(range), Float(step), Float(page))
end

function spin_button_new_with_range(minimum, maximum, step):
    return __lsl_qbe_call3(__lsl_symbol("gtk_spin_button_new_with_range"), Float(minimum), Float(maximum), Float(step))
end

function spin_button_get_value(spin):
    return __lsl_qbe_fcall1(__lsl_symbol("gtk_spin_button_get_value"), ptr(spin))
end

function spin_button_set_value(spin, value):
    return __lsl_qbe_call2(__lsl_symbol("gtk_spin_button_set_value"), ptr(spin), Float(value))
end

function progress_bar_new():
    return __lsl_qbe_call0(__lsl_symbol("gtk_progress_bar_new"))
end

function progress_bar_set_fraction(bar, fraction):
    return __lsl_qbe_call2(__lsl_symbol("gtk_progress_bar_set_fraction"), ptr(bar), Float(fraction))
end

function progress_bar_set_text(bar, text):
    call __lsl_qbe_call2(__lsl_symbol("gtk_progress_bar_set_show_text"), ptr(bar), 1)
    return __lsl_qbe_call2(__lsl_symbol("gtk_progress_bar_set_text"), ptr(bar), cstr(text))
end

function level_bar_new():
    return __lsl_qbe_call0(__lsl_symbol("gtk_level_bar_new"))
end

function level_bar_set_value(bar, value):
    return __lsl_qbe_call2(__lsl_symbol("gtk_level_bar_set_value"), ptr(bar), Float(value))
end

# Obrázek ze souboru zmenšený na šířku × výšku (-1 = podle poměru); 0 při
# chybě (soubor chybí nebo není obrázek). Uvolnění: glib.object_unref.
function pixbuf_new_from_file_at_scale(path, width, height, keep_aspect):
    return __lsl_qbe_call5(__lsl_symbol("gdk_pixbuf_new_from_file_at_scale"), cstr(path), ptr(width), ptr(height), ptr(keep_aspect), 0)
end

function pixbuf_new_from_file(path):
    return __lsl_qbe_call2(__lsl_symbol("gdk_pixbuf_new_from_file"), cstr(path), 0)
end

function pixbuf_get_width(pixbuf):
    return __lsl_qbe_call1(__lsl_symbol("gdk_pixbuf_get_width"), ptr(pixbuf))
end

function pixbuf_get_height(pixbuf):
    return __lsl_qbe_call1(__lsl_symbol("gdk_pixbuf_get_height"), ptr(pixbuf))
end

function image_new_from_pixbuf(pixbuf):
    return __lsl_qbe_call1(__lsl_symbol("gtk_image_new_from_pixbuf"), ptr(pixbuf))
end

function image_new_from_file(path):
    return __lsl_qbe_call1(__lsl_symbol("gtk_image_new_from_file"), cstr(path))
end

function image_set_from_pixbuf(image, pixbuf):
    return __lsl_qbe_call2(__lsl_symbol("gtk_image_set_from_pixbuf"), ptr(image), ptr(pixbuf))
end

function image_set_from_icon_name(image, name, size):
    return __lsl_qbe_call3(__lsl_symbol("gtk_image_set_from_icon_name"), ptr(image), cstr(name), ptr(size))
end

function image_set_pixel_size(image, size):
    return __lsl_qbe_call2(__lsl_symbol("gtk_image_set_pixel_size"), ptr(image), ptr(size))
end

function image_clear(image):
    return __lsl_qbe_call1(__lsl_symbol("gtk_image_clear"), ptr(image))
end

function icon_theme_has_icon(name):
    theme = __lsl_qbe_call0(__lsl_symbol("gtk_icon_theme_get_default"))
    return __lsl_qbe_call2(__lsl_symbol("gtk_icon_theme_has_icon"), theme, cstr(name)) != 0
end

# Kreslení pixbufu do cairo kontextu (obsluha draw).
function cairo_set_source_pixbuf(cr, pixbuf, x, y):
    return __lsl_qbe_call4(__lsl_symbol("gdk_cairo_set_source_pixbuf"), ptr(cr), ptr(pixbuf), Float(x), Float(y))
end

RELIEF_NORMAL = 0
RELIEF_NONE = 2

function button_new_empty():
    return __lsl_qbe_call0(__lsl_symbol("gtk_button_new"))
end

function button_new_from_icon_name(name, size):
    return __lsl_qbe_call2(__lsl_symbol("gtk_button_new_from_icon_name"), cstr(name), ptr(size))
end

function button_set_relief(button, relief):
    return __lsl_qbe_call2(__lsl_symbol("gtk_button_set_relief"), ptr(button), ptr(relief))
end

function button_set_image(button, image):
    return __lsl_qbe_call2(__lsl_symbol("gtk_button_set_image"), ptr(button), ptr(image))
end

function button_set_always_show_image(button, show):
    return __lsl_qbe_call2(__lsl_symbol("gtk_button_set_always_show_image"), ptr(button), ptr(show))
end

# Pozice obrázku v tlačítku: POS_LEFT = 0, POS_RIGHT = 1, POS_TOP = 2, POS_BOTTOM = 3.
function button_set_image_position(button, position):
    return __lsl_qbe_call2(__lsl_symbol("gtk_button_set_image_position"), ptr(button), ptr(position))
end

function toggle_button_new(text):
    return __lsl_qbe_call1(__lsl_symbol("gtk_toggle_button_new_with_label"), cstr(text))
end

function check_button_new(text):
    return __lsl_qbe_call1(__lsl_symbol("gtk_check_button_new_with_label"), cstr(text))
end

function toggle_button_get_active(button):
    return __lsl_qbe_call1(__lsl_symbol("gtk_toggle_button_get_active"), ptr(button)) != 0
end

function toggle_button_set_active(button, active):
    return __lsl_qbe_call2(__lsl_symbol("gtk_toggle_button_set_active"), ptr(button), ptr(active))
end

function combo_box_text_new():
    return __lsl_qbe_call0(__lsl_symbol("gtk_combo_box_text_new"))
end

function combo_box_text_append(combo, id, text):
    return __lsl_qbe_call3(__lsl_symbol("gtk_combo_box_text_append"), ptr(combo), cstr(id), cstr(text))
end

function combo_box_text_get_active_text(combo):
    return glib.take_c(__lsl_qbe_call1(__lsl_symbol("gtk_combo_box_text_get_active_text"), ptr(combo)))
end

function combo_box_get_active(combo):
    return __lsl_qbe_s32(__lsl_qbe_call1(__lsl_symbol("gtk_combo_box_get_active"), ptr(combo)))
end

function combo_box_set_active(combo, index):
    return __lsl_qbe_call2(__lsl_symbol("gtk_combo_box_set_active"), ptr(combo), ptr(index))
end

# --- okna: typ, poloha, vrstvy ---

# GdkWindowTypeHint
TYPE_HINT_NORMAL = 0
TYPE_HINT_DIALOG = 1
TYPE_HINT_MENU = 2
TYPE_HINT_TOOLBAR = 3
TYPE_HINT_SPLASHSCREEN = 4
TYPE_HINT_UTILITY = 5
TYPE_HINT_DOCK = 6
TYPE_HINT_DESKTOP = 7
TYPE_HINT_DROPDOWN_MENU = 8
TYPE_HINT_POPUP_MENU = 9
TYPE_HINT_TOOLTIP = 10
TYPE_HINT_NOTIFICATION = 11
# GtkWindowPosition
WIN_POS_NONE = 0
WIN_POS_CENTER = 1
WIN_POS_MOUSE = 2
WIN_POS_CENTER_ALWAYS = 3
WIN_POS_CENTER_ON_PARENT = 4
CURRENT_TIME = 0

# Okno bez správce oken (GTK_WINDOW_POPUP = 1): vyskakovací panely u lišty.
function window_new_popup():
    return __lsl_qbe_call1(__lsl_symbol("gtk_window_new"), 1)
end

function window_set_type_hint(window, hint):
    return __lsl_qbe_call2(__lsl_symbol("gtk_window_set_type_hint"), ptr(window), ptr(hint))
end

function window_set_decorated(window, decorated):
    return __lsl_qbe_call2(__lsl_symbol("gtk_window_set_decorated"), ptr(window), ptr(decorated))
end

function window_set_keep_above(window, above):
    return __lsl_qbe_call2(__lsl_symbol("gtk_window_set_keep_above"), ptr(window), ptr(above))
end

function window_set_keep_below(window, below):
    return __lsl_qbe_call2(__lsl_symbol("gtk_window_set_keep_below"), ptr(window), ptr(below))
end

function window_set_skip_taskbar_hint(window, skip):
    return __lsl_qbe_call2(__lsl_symbol("gtk_window_set_skip_taskbar_hint"), ptr(window), ptr(skip))
end

function window_set_skip_pager_hint(window, skip):
    return __lsl_qbe_call2(__lsl_symbol("gtk_window_set_skip_pager_hint"), ptr(window), ptr(skip))
end

function window_set_accept_focus(window, accept):
    return __lsl_qbe_call2(__lsl_symbol("gtk_window_set_accept_focus"), ptr(window), ptr(accept))
end

function window_set_resizable(window, resizable):
    return __lsl_qbe_call2(__lsl_symbol("gtk_window_set_resizable"), ptr(window), ptr(resizable))
end

function window_set_modal(window, modal):
    return __lsl_qbe_call2(__lsl_symbol("gtk_window_set_modal"), ptr(window), ptr(modal))
end

function window_set_transient_for(window, parent):
    return __lsl_qbe_call2(__lsl_symbol("gtk_window_set_transient_for"), ptr(window), ptr(parent))
end

function window_set_position(window, position):
    return __lsl_qbe_call2(__lsl_symbol("gtk_window_set_position"), ptr(window), ptr(position))
end

function window_set_icon_name(window, name):
    return __lsl_qbe_call2(__lsl_symbol("gtk_window_set_icon_name"), ptr(window), cstr(name))
end

function window_move(window, x, y):
    return __lsl_qbe_call3(__lsl_symbol("gtk_window_move"), ptr(window), ptr(x), ptr(y))
end

function window_resize(window, width, height):
    return __lsl_qbe_call3(__lsl_symbol("gtk_window_resize"), ptr(window), ptr(width), ptr(height))
end

# [šířka, výška] a [x, y] okna.
function window_get_size(window):
    cells = __lsl_byte_zeros(16)
    data = glib.array_data(cells)
    call __lsl_qbe_call3(__lsl_symbol("gtk_window_get_size"), ptr(window), data, data + 8)
    return [__lsl_qbe_s32(__lsl_qbe_load32(data)), __lsl_qbe_s32(__lsl_qbe_load32(data + 8))]
end

function window_get_position(window):
    cells = __lsl_byte_zeros(16)
    data = glib.array_data(cells)
    call __lsl_qbe_call3(__lsl_symbol("gtk_window_get_position"), ptr(window), data, data + 8)
    return [__lsl_qbe_s32(__lsl_qbe_load32(data)), __lsl_qbe_s32(__lsl_qbe_load32(data + 8))]
end

function window_present(window):
    return __lsl_qbe_call1(__lsl_symbol("gtk_window_present"), ptr(window))
end

function window_present_with_time(window, timestamp):
    return __lsl_qbe_call2(__lsl_symbol("gtk_window_present_with_time"), ptr(window), ptr(timestamp))
end

function window_stick(window):
    return __lsl_qbe_call1(__lsl_symbol("gtk_window_stick"), ptr(window))
end

function window_close(window):
    return __lsl_qbe_call1(__lsl_symbol("gtk_window_close"), ptr(window))
end

function window_fullscreen(window):
    return __lsl_qbe_call1(__lsl_symbol("gtk_window_fullscreen"), ptr(window))
end

function window_unfullscreen(window):
    return __lsl_qbe_call1(__lsl_symbol("gtk_window_unfullscreen"), ptr(window))
end

function window_maximize(window):
    return __lsl_qbe_call1(__lsl_symbol("gtk_window_maximize"), ptr(window))
end

function window_iconify(window):
    return __lsl_qbe_call1(__lsl_symbol("gtk_window_iconify"), ptr(window))
end

function window_is_active(window):
    return __lsl_qbe_call1(__lsl_symbol("gtk_window_is_active"), ptr(window)) != 0
end

function window_set_default(window, widget):
    return __lsl_qbe_call2(__lsl_symbol("gtk_window_set_default"), ptr(window), ptr(widget))
end

# Čas aktuální události pro present_with_time (0 = CURRENT_TIME mimo obsluhu).
function get_current_event_time():
    return __lsl_qbe_call0(__lsl_symbol("gtk_get_current_event_time"))
end

# Průhledné pozadí: RGBA visual obrazovky (True, když ho kompozitor nabízí)
# a kreslení vlastního pozadí (app_paintable) – zbytek dělá CSS nebo draw.
function widget_set_rgba_visual(widget):
    screen = __lsl_qbe_call1(__lsl_symbol("gtk_widget_get_screen"), ptr(widget))
    visual = __lsl_qbe_call1(__lsl_symbol("gdk_screen_get_rgba_visual"), screen)
    if visual == 0:
        return False
    end
    call __lsl_qbe_call2(__lsl_symbol("gtk_widget_set_visual"), ptr(widget), visual)
    return True
end

function widget_set_app_paintable(widget, paintable):
    return __lsl_qbe_call2(__lsl_symbol("gtk_widget_set_app_paintable"), ptr(widget), ptr(paintable))
end

function screen_is_composited():
    screen = __lsl_qbe_call0(__lsl_symbol("gdk_screen_get_default"))
    return __lsl_qbe_call1(__lsl_symbol("gdk_screen_is_composited"), screen) != 0
end

# --- monitory (umístění oken u lišty) ---

function monitor_count():
    display = __lsl_qbe_call0(__lsl_symbol("gdk_display_get_default"))
    return __lsl_qbe_call1(__lsl_symbol("gdk_display_get_n_monitors"), display)
end

# GdkRectangle monitoru: workarea (bez panelů) nebo celá geometrie.
function rectangle_of(monitor, workarea):
    if monitor == 0:
        return [0, 0, 0, 0]
    end
    cells = __lsl_byte_zeros(16)
    data = glib.array_data(cells)
    if workarea:
        call __lsl_qbe_call2(__lsl_symbol("gdk_monitor_get_workarea"), ptr(monitor), data)
    else:
        call __lsl_qbe_call2(__lsl_symbol("gdk_monitor_get_geometry"), ptr(monitor), data)
    end
    return [__lsl_qbe_s32(__lsl_qbe_load32(data)), __lsl_qbe_s32(__lsl_qbe_load32(data + 4)), __lsl_qbe_s32(__lsl_qbe_load32(data + 8)), __lsl_qbe_s32(__lsl_qbe_load32(data + 12))]
end

# Pracovní plocha monitoru [x, y, šířka, výška] bez panelů; index monitoru,
# primary_monitor_workarea() pro hlavní a monitor_at_point_workarea(x, y)
# pro monitor pod bodem (např. pod ikonou v liště).
function monitor_workarea(index):
    display = __lsl_qbe_call0(__lsl_symbol("gdk_display_get_default"))
    return rectangle_of(__lsl_qbe_call2(__lsl_symbol("gdk_display_get_monitor"), display, ptr(index)), True)
end

function monitor_geometry(index):
    display = __lsl_qbe_call0(__lsl_symbol("gdk_display_get_default"))
    return rectangle_of(__lsl_qbe_call2(__lsl_symbol("gdk_display_get_monitor"), display, ptr(index)), False)
end

function primary_monitor_workarea():
    display = __lsl_qbe_call0(__lsl_symbol("gdk_display_get_default"))
    monitor = __lsl_qbe_call1(__lsl_symbol("gdk_display_get_primary_monitor"), display)
    if monitor == 0:
        monitor = __lsl_qbe_call2(__lsl_symbol("gdk_display_get_monitor"), display, 0)
    end
    return rectangle_of(monitor, True)
end

function monitor_at_point_workarea(x, y):
    display = __lsl_qbe_call0(__lsl_symbol("gdk_display_get_default"))
    return rectangle_of(__lsl_qbe_call3(__lsl_symbol("gdk_display_get_monitor_at_point"), display, ptr(x), ptr(y)), True)
end

function monitor_scale_factor(index):
    display = __lsl_qbe_call0(__lsl_symbol("gdk_display_get_default"))
    monitor = __lsl_qbe_call2(__lsl_symbol("gdk_display_get_monitor"), display, ptr(index))
    if monitor == 0:
        return 1
    end
    return __lsl_qbe_call1(__lsl_symbol("gdk_monitor_get_scale_factor"), monitor)
end

# --- vlastnosti GObject (GtkSettings: motiv, tmavý režim) ---

function settings_get_default():
    return __lsl_qbe_call0(__lsl_symbol("gtk_settings_get_default"))
end

# g_object_get/set pro String, Int a Bool (jiné typy přes g_object_set_property).
function object_get_string(object, property):
    cell = __lsl_byte_zeros(8)
    call __lsl_qbe_call4(__lsl_symbol("g_object_get"), ptr(object), cstr(property), glib.array_data(cell), 0)
    return glib.take_c(__lsl_qbe_load64(glib.array_data(cell)))
end

function object_get_int(object, property):
    cell = __lsl_byte_zeros(8)
    call __lsl_qbe_call4(__lsl_symbol("g_object_get"), ptr(object), cstr(property), glib.array_data(cell), 0)
    return __lsl_qbe_s32(__lsl_qbe_load32(glib.array_data(cell)))
end

function object_get_bool(object, property):
    return object_get_int(object, property) != 0
end

function object_set_string(object, property, value):
    return __lsl_qbe_call4(__lsl_symbol("g_object_set"), ptr(object), cstr(property), cstr(value), 0)
end

function object_set_int(object, property, value):
    return __lsl_qbe_call4(__lsl_symbol("g_object_set"), ptr(object), cstr(property), ptr(value), 0)
end

function object_set_bool(object, property, value):
    return __lsl_qbe_call4(__lsl_symbol("g_object_set"), ptr(object), cstr(property), ptr(value), 0)
end

# --- události (key-press-event, button-press-event, scroll-event, motion) ---

KEY_Escape = 65307
KEY_Return = 65293
KEY_KP_Enter = 65421
KEY_Tab = 65289
KEY_BackSpace = 65288
KEY_Delete = 65535
KEY_Up = 65362
KEY_Down = 65364
KEY_Left = 65361
KEY_Right = 65363
KEY_Home = 65360
KEY_End = 65367
KEY_Page_Up = 65365
KEY_Page_Down = 65366
KEY_space = 32
KEY_F1 = 65470
# GdkModifierType
SHIFT_MASK = 1
CONTROL_MASK = 4
MOD1_MASK = 8
SUPER_MASK = 67108864
# GdkEventMask pro widget_add_events
POINTER_MOTION_MASK = 4
BUTTON_PRESS_MASK = 256
BUTTON_RELEASE_MASK = 512
KEY_PRESS_MASK = 1024
KEY_RELEASE_MASK = 2048
ENTER_NOTIFY_MASK = 4096
LEAVE_NOTIFY_MASK = 8192
SCROLL_MASK = 2097152
SMOOTH_SCROLL_MASK = 8388608
# GdkScrollDirection
SCROLL_UP = 0
SCROLL_DOWN = 1
SCROLL_LEFT = 2
SCROLL_RIGHT = 3
SCROLL_SMOOTH = 4

function widget_add_events(widget, mask):
    return __lsl_qbe_call2(__lsl_symbol("gtk_widget_add_events"), ptr(widget), ptr(mask))
end

# GdkEventKey: keyval (gdk.KEY_*), stav modifikátorů a jméno klávesy.
function event_key_keyval(event):
    return __lsl_qbe_load32(ptr(event) + 28)
end

function event_key_state(event):
    return __lsl_qbe_load32(ptr(event) + 24)
end

function event_key_name(event):
    return from_c(__lsl_qbe_call1(__lsl_symbol("gdk_keyval_name"), event_key_keyval(event)))
end

# Znak klávesy ("" pro klávesy bez znaku).
function event_key_text(event):
    code = __lsl_qbe_call1(__lsl_symbol("gdk_keyval_to_unicode"), event_key_keyval(event))
    if code == 0:
        return ""
    end
    return chr(code)
end

# GdkEventButton/Motion/Scroll: čas, souřadnice (Float) a tlačítko.
function event_time(event):
    return __lsl_qbe_load32(ptr(event) + 20)
end

function event_x(event):
    return __lsl_float_from_bits(__lsl_qbe_load64(ptr(event) + 24))
end

function event_y(event):
    return __lsl_float_from_bits(__lsl_qbe_load64(ptr(event) + 32))
end

function event_button(event):
    return __lsl_qbe_load32(ptr(event) + 52)
end

function event_button_state(event):
    return __lsl_qbe_load32(ptr(event) + 48)
end

# Dvojklik: GDK_2BUTTON_PRESS = 5 (typ události na začátku záznamu).
function event_is_double_click(event):
    return __lsl_qbe_load32(ptr(event)) == 5
end

function event_scroll_direction(event):
    return __lsl_qbe_load32(ptr(event) + 44)
end

# [dx, dy] plynulého posunu (SCROLL_SMOOTH).
function event_scroll_deltas(event):
    return [__lsl_float_from_bits(__lsl_qbe_load64(ptr(event) + 72)), __lsl_float_from_bits(__lsl_qbe_load64(ptr(event) + 80))]
end

# --- widgety: rozměry, viditelnost, stav, kurzor ---

# GtkStateFlags
STATE_FLAG_ACTIVE = 1
STATE_FLAG_PRELIGHT = 2
STATE_FLAG_SELECTED = 4
STATE_FLAG_INSENSITIVE = 8
STATE_FLAG_CHECKED = 2048

function widget_get_allocated_width(widget):
    return __lsl_qbe_call1(__lsl_symbol("gtk_widget_get_allocated_width"), ptr(widget))
end

function widget_get_allocated_height(widget):
    return __lsl_qbe_call1(__lsl_symbol("gtk_widget_get_allocated_height"), ptr(widget))
end

# [x, y, šířka, výška] přidělené widgetu v okně.
function widget_get_allocation(widget):
    cells = __lsl_byte_zeros(16)
    data = glib.array_data(cells)
    call __lsl_qbe_call2(__lsl_symbol("gtk_widget_get_allocation"), ptr(widget), data)
    return [__lsl_qbe_s32(__lsl_qbe_load32(data)), __lsl_qbe_s32(__lsl_qbe_load32(data + 4)), __lsl_qbe_s32(__lsl_qbe_load32(data + 8)), __lsl_qbe_s32(__lsl_qbe_load32(data + 12))]
end

function widget_queue_draw(widget):
    return __lsl_qbe_call1(__lsl_symbol("gtk_widget_queue_draw"), ptr(widget))
end

function widget_set_opacity(widget, opacity):
    return __lsl_qbe_call2(__lsl_symbol("gtk_widget_set_opacity"), ptr(widget), Float(opacity))
end

function widget_get_visible(widget):
    return __lsl_qbe_call1(__lsl_symbol("gtk_widget_get_visible"), ptr(widget)) != 0
end

function widget_set_visible(widget, visible):
    return __lsl_qbe_call2(__lsl_symbol("gtk_widget_set_visible"), ptr(widget), ptr(visible))
end

function widget_is_visible(widget):
    return __lsl_qbe_call1(__lsl_symbol("gtk_widget_is_visible"), ptr(widget)) != 0
end

function widget_grab_focus(widget):
    return __lsl_qbe_call1(__lsl_symbol("gtk_widget_grab_focus"), ptr(widget))
end

function widget_set_can_focus(widget, can):
    return __lsl_qbe_call2(__lsl_symbol("gtk_widget_set_can_focus"), ptr(widget), ptr(can))
end

function widget_set_can_default(widget, can):
    return __lsl_qbe_call2(__lsl_symbol("gtk_widget_set_can_default"), ptr(widget), ptr(can))
end

function widget_set_hexpand(widget, expand):
    return __lsl_qbe_call2(__lsl_symbol("gtk_widget_set_hexpand"), ptr(widget), ptr(expand))
end

function widget_set_vexpand(widget, expand):
    return __lsl_qbe_call2(__lsl_symbol("gtk_widget_set_vexpand"), ptr(widget), ptr(expand))
end

function widget_set_margins(widget, start, end_margin, top, bottom):
    w = ptr(widget)
    call __lsl_qbe_call2(__lsl_symbol("gtk_widget_set_margin_start"), w, ptr(start))
    call __lsl_qbe_call2(__lsl_symbol("gtk_widget_set_margin_end"), w, ptr(end_margin))
    call __lsl_qbe_call2(__lsl_symbol("gtk_widget_set_margin_top"), w, ptr(top))
    call __lsl_qbe_call2(__lsl_symbol("gtk_widget_set_margin_bottom"), w, ptr(bottom))
    return 0
end

function widget_set_tooltip_markup(widget, markup):
    return __lsl_qbe_call2(__lsl_symbol("gtk_widget_set_tooltip_markup"), ptr(widget), cstr(markup))
end

function widget_get_parent(widget):
    return __lsl_qbe_call1(__lsl_symbol("gtk_widget_get_parent"), ptr(widget))
end

function widget_get_toplevel(widget):
    return __lsl_qbe_call1(__lsl_symbol("gtk_widget_get_toplevel"), ptr(widget))
end

function widget_get_window(widget):
    return __lsl_qbe_call1(__lsl_symbol("gtk_widget_get_window"), ptr(widget))
end

function widget_realize(widget):
    return __lsl_qbe_call1(__lsl_symbol("gtk_widget_realize"), ptr(widget))
end

function widget_set_state_flags(widget, flags, clear):
    return __lsl_qbe_call3(__lsl_symbol("gtk_widget_set_state_flags"), ptr(widget), ptr(flags), ptr(clear))
end

function widget_unset_state_flags(widget, flags):
    return __lsl_qbe_call2(__lsl_symbol("gtk_widget_unset_state_flags"), ptr(widget), ptr(flags))
end

function widget_get_state_flags(widget):
    return __lsl_qbe_call1(__lsl_symbol("gtk_widget_get_state_flags"), ptr(widget))
end

# Barva popředí z motivu pro daný stav (STATE_FLAG_*; 0 = normální):
# [r, g, b, a] jako Float 0–1, pro kreslení cairo.
function widget_get_color(widget, state):
    context = __lsl_qbe_call1(__lsl_symbol("gtk_widget_get_style_context"), ptr(widget))
    cells = __lsl_byte_zeros(32)
    data = glib.array_data(cells)
    call __lsl_qbe_call3(__lsl_symbol("gtk_style_context_get_color"), context, ptr(state), data)
    return [__lsl_float_from_bits(__lsl_qbe_load64(data)), __lsl_float_from_bits(__lsl_qbe_load64(data + 8)), __lsl_float_from_bits(__lsl_qbe_load64(data + 16)), __lsl_float_from_bits(__lsl_qbe_load64(data + 24))]
end

# Kurzor podle jména CSS ("pointer", "text", "default", "grab") na
# realizovaném widgetu (po show); 0 vrátí kurzor zpět výchozímu.
function widget_set_cursor(widget, name):
    window = __lsl_qbe_call1(__lsl_symbol("gtk_widget_get_window"), ptr(widget))
    if window == 0:
        return False
    end
    cursor = 0
    if len(name) > 0:
        display = __lsl_qbe_call0(__lsl_symbol("gdk_display_get_default"))
        cursor = __lsl_qbe_call2(__lsl_symbol("gdk_cursor_new_from_name"), display, cstr(name))
    end
    call __lsl_qbe_call2(__lsl_symbol("gdk_window_set_cursor"), window, cursor)
    if cursor != 0:
        call glib.object_unref(cursor)
    end
    return True
end

# --- popisky, vstupní pole ---

# PangoEllipsizeMode
ELLIPSIZE_NONE = 0
ELLIPSIZE_START = 1
ELLIPSIZE_MIDDLE = 2
ELLIPSIZE_END = 3
# GtkJustification
JUSTIFY_LEFT = 0
JUSTIFY_RIGHT = 1
JUSTIFY_CENTER = 2

function label_set_ellipsize(label, mode):
    return __lsl_qbe_call2(__lsl_symbol("gtk_label_set_ellipsize"), ptr(label), ptr(mode))
end

function label_set_xalign(label, xalign):
    return __lsl_qbe_call2(__lsl_symbol("gtk_label_set_xalign"), ptr(label), __lsl_qbe_f32(Float(xalign)))
end

function label_set_yalign(label, yalign):
    return __lsl_qbe_call2(__lsl_symbol("gtk_label_set_yalign"), ptr(label), __lsl_qbe_f32(Float(yalign)))
end

function label_set_max_width_chars(label, chars):
    return __lsl_qbe_call2(__lsl_symbol("gtk_label_set_max_width_chars"), ptr(label), ptr(chars))
end

function label_set_width_chars(label, chars):
    return __lsl_qbe_call2(__lsl_symbol("gtk_label_set_width_chars"), ptr(label), ptr(chars))
end

function label_set_line_wrap(label, wrap):
    return __lsl_qbe_call2(__lsl_symbol("gtk_label_set_line_wrap"), ptr(label), ptr(wrap))
end

function label_set_justify(label, justify):
    return __lsl_qbe_call2(__lsl_symbol("gtk_label_set_justify"), ptr(label), ptr(justify))
end

function label_set_selectable(label, selectable):
    return __lsl_qbe_call2(__lsl_symbol("gtk_label_set_selectable"), ptr(label), ptr(selectable))
end

function label_set_use_markup(label, use):
    return __lsl_qbe_call2(__lsl_symbol("gtk_label_set_use_markup"), ptr(label), ptr(use))
end

# GtkEntryIconPosition
ENTRY_ICON_PRIMARY = 0
ENTRY_ICON_SECONDARY = 1

function search_entry_new():
    return __lsl_qbe_call0(__lsl_symbol("gtk_search_entry_new"))
end

function entry_set_placeholder_text(entry, text):
    return __lsl_qbe_call2(__lsl_symbol("gtk_entry_set_placeholder_text"), ptr(entry), cstr(text))
end

function entry_set_icon_from_icon_name(entry, position, name):
    return __lsl_qbe_call3(__lsl_symbol("gtk_entry_set_icon_from_icon_name"), ptr(entry), ptr(position), cstr(name))
end

function entry_set_max_length(entry, length):
    return __lsl_qbe_call2(__lsl_symbol("gtk_entry_set_max_length"), ptr(entry), ptr(length))
end

function entry_set_visibility(entry, visible):
    return __lsl_qbe_call2(__lsl_symbol("gtk_entry_set_visibility"), ptr(entry), ptr(visible))
end

function entry_set_activates_default(entry, activates):
    return __lsl_qbe_call2(__lsl_symbol("gtk_entry_set_activates_default"), ptr(entry), ptr(activates))
end

function entry_grab_focus_without_selecting(entry):
    return __lsl_qbe_call1(__lsl_symbol("gtk_entry_grab_focus_without_selecting"), ptr(entry))
end

# --- další kontejnery a widgety ---

# GtkPolicyType
POLICY_ALWAYS = 0
POLICY_AUTOMATIC = 1
POLICY_NEVER = 2
POLICY_EXTERNAL = 3
# GtkRevealerTransitionType
REVEALER_NONE = 0
REVEALER_CROSSFADE = 1
REVEALER_SLIDE_RIGHT = 2
REVEALER_SLIDE_LEFT = 3
REVEALER_SLIDE_UP = 4
REVEALER_SLIDE_DOWN = 5

function drawing_area_new():
    return __lsl_qbe_call0(__lsl_symbol("gtk_drawing_area_new"))
end

function event_box_new():
    return __lsl_qbe_call0(__lsl_symbol("gtk_event_box_new"))
end

function event_box_set_visible_window(box, visible):
    return __lsl_qbe_call2(__lsl_symbol("gtk_event_box_set_visible_window"), ptr(box), ptr(visible))
end

function event_box_set_above_child(box, above):
    return __lsl_qbe_call2(__lsl_symbol("gtk_event_box_set_above_child"), ptr(box), ptr(above))
end

function scrolled_window_new():
    return __lsl_qbe_call2(__lsl_symbol("gtk_scrolled_window_new"), 0, 0)
end

function scrolled_window_set_policy(window, horizontal, vertical):
    return __lsl_qbe_call3(__lsl_symbol("gtk_scrolled_window_set_policy"), ptr(window), ptr(horizontal), ptr(vertical))
end

function scrolled_window_set_min_content_height(window, height):
    return __lsl_qbe_call2(__lsl_symbol("gtk_scrolled_window_set_min_content_height"), ptr(window), ptr(height))
end

function scrolled_window_set_max_content_height(window, height):
    call __lsl_qbe_call2(__lsl_symbol("gtk_scrolled_window_set_propagate_natural_height"), ptr(window), 1)
    return __lsl_qbe_call2(__lsl_symbol("gtk_scrolled_window_set_max_content_height"), ptr(window), ptr(height))
end

function separator_new(orientation):
    return __lsl_qbe_call1(__lsl_symbol("gtk_separator_new"), ptr(orientation))
end

function frame_new(label):
    if len(label) == 0:
        return __lsl_qbe_call1(__lsl_symbol("gtk_frame_new"), 0)
    end
    return __lsl_qbe_call1(__lsl_symbol("gtk_frame_new"), cstr(label))
end

function fixed_new():
    return __lsl_qbe_call0(__lsl_symbol("gtk_fixed_new"))
end

function fixed_put(fixed, child, x, y):
    return __lsl_qbe_call4(__lsl_symbol("gtk_fixed_put"), ptr(fixed), ptr(child), ptr(x), ptr(y))
end

function fixed_move(fixed, child, x, y):
    return __lsl_qbe_call4(__lsl_symbol("gtk_fixed_move"), ptr(fixed), ptr(child), ptr(x), ptr(y))
end

function overlay_new():
    return __lsl_qbe_call0(__lsl_symbol("gtk_overlay_new"))
end

function overlay_add_overlay(overlay, child):
    return __lsl_qbe_call2(__lsl_symbol("gtk_overlay_add_overlay"), ptr(overlay), ptr(child))
end

function revealer_new():
    return __lsl_qbe_call0(__lsl_symbol("gtk_revealer_new"))
end

function revealer_set_reveal_child(revealer, reveal):
    return __lsl_qbe_call2(__lsl_symbol("gtk_revealer_set_reveal_child"), ptr(revealer), ptr(reveal))
end

function revealer_set_transition_type(revealer, kind):
    return __lsl_qbe_call2(__lsl_symbol("gtk_revealer_set_transition_type"), ptr(revealer), ptr(kind))
end

function revealer_set_transition_duration(revealer, milliseconds):
    return __lsl_qbe_call2(__lsl_symbol("gtk_revealer_set_transition_duration"), ptr(revealer), ptr(milliseconds))
end

function list_box_new():
    return __lsl_qbe_call0(__lsl_symbol("gtk_list_box_new"))
end

function list_box_insert(box, child, position):
    return __lsl_qbe_call3(__lsl_symbol("gtk_list_box_insert"), ptr(box), ptr(child), ptr(position))
end

# GtkSelectionMode: SELECTION_NONE = 0, SINGLE = 1, BROWSE = 2, MULTIPLE = 3.
function list_box_set_selection_mode(box, mode):
    return __lsl_qbe_call2(__lsl_symbol("gtk_list_box_set_selection_mode"), ptr(box), ptr(mode))
end

function list_box_row_get_index(row):
    return __lsl_qbe_s32(__lsl_qbe_call1(__lsl_symbol("gtk_list_box_row_get_index"), ptr(row)))
end

function box_set_homogeneous(box, homogeneous):
    return __lsl_qbe_call2(__lsl_symbol("gtk_box_set_homogeneous"), ptr(box), ptr(homogeneous))
end

function box_set_spacing(box, spacing):
    return __lsl_qbe_call2(__lsl_symbol("gtk_box_set_spacing"), ptr(box), ptr(spacing))
end

function box_reorder_child(box, child, position):
    return __lsl_qbe_call3(__lsl_symbol("gtk_box_reorder_child"), ptr(box), ptr(child), ptr(position))
end

function container_remove(container, child):
    return __lsl_qbe_call2(__lsl_symbol("gtk_container_remove"), ptr(container), ptr(child))
end

# Seznam přímých potomků kontejneru (ukazatele).
function container_get_children(container):
    children = []
    list = __lsl_qbe_call1(__lsl_symbol("gtk_container_get_children"), ptr(container))
    node = list
    while node != 0:
        children.append(__lsl_qbe_load64(node))
        node = __lsl_qbe_load64(node + 8)
    end
    if list != 0:
        call __lsl_qbe_call1(__lsl_symbol("g_list_free"), list)
    end
    return children
end

# Kalendář GTK: datum [rok, měsíc 1–12, den].
function calendar_new():
    return __lsl_qbe_call0(__lsl_symbol("gtk_calendar_new"))
end

function calendar_get_date(calendar):
    cells = __lsl_byte_zeros(24)
    data = glib.array_data(cells)
    call __lsl_qbe_call4(__lsl_symbol("gtk_calendar_get_date"), ptr(calendar), data, data + 8, data + 16)
    return [__lsl_qbe_load32(data), __lsl_qbe_load32(data + 8) + 1, __lsl_qbe_load32(data + 16)]
end

function calendar_select_day(calendar, year, month, day):
    call __lsl_qbe_call3(__lsl_symbol("gtk_calendar_select_month"), ptr(calendar), ptr(month) - 1, ptr(year))
    return __lsl_qbe_call2(__lsl_symbol("gtk_calendar_select_day"), ptr(calendar), ptr(day))
end

function calendar_mark_day(calendar, day):
    return __lsl_qbe_call2(__lsl_symbol("gtk_calendar_mark_day"), ptr(calendar), ptr(day))
end

function calendar_clear_marks(calendar):
    return __lsl_qbe_call1(__lsl_symbol("gtk_calendar_clear_marks"), ptr(calendar))
end

# --- CSS za běhu ---

# Odebere dřív načtené CSS (css_load vrací provider): přepnutí světlý/tmavý.
function css_remove(provider):
    screen = __lsl_qbe_call0(__lsl_symbol("gdk_screen_get_default"))
    call __lsl_qbe_call2(__lsl_symbol("gtk_style_context_remove_provider_for_screen"), screen, ptr(provider))
    return glib.object_unref(provider)
end

# CSS ze souboru (provider pro css_remove; 0 při chybě souboru).
function css_load_file(path):
    provider = __lsl_qbe_call0(__lsl_symbol("gtk_css_provider_new"))
    cell = __lsl_byte_zeros(8)
    call __lsl_qbe_call3(__lsl_symbol("gtk_css_provider_load_from_path"), provider, cstr(path), glib.array_data(cell))
    error = __lsl_qbe_load64(glib.array_data(cell))
    if error != 0:
        call __lsl_qbe_call1(__lsl_symbol("g_error_free"), error)
        call glib.object_unref(provider)
        return 0
    end
    screen = __lsl_qbe_call0(__lsl_symbol("gdk_screen_get_default"))
    call __lsl_qbe_call3(__lsl_symbol("gtk_style_context_add_provider_for_screen"), screen, provider, 600)
    return provider
end
