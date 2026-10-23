# lsl: internal-abi
# lsl: link libgtk-3.so.0 libgdk-3.so.0 libgio-2.0.so.0 libgobject-2.0.so.0 libglib-2.0.so.0
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
SIGNAL_ARGS = {"draw":1, "key-press-event":1, "key-release-event":1, "button-press-event":1, "button-release-event":1, "delete-event":1, "size-allocate":1, "scroll-event":1, "motion-notify-event":1, "row-selected":1, "row-activated":1, "state-set":1}

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

# CSS pro celou obrazovku (GTK_STYLE_PROVIDER_PRIORITY_APPLICATION = 600).
function css_load(css):
    provider = __lsl_qbe_call0(__lsl_symbol("gtk_css_provider_new"))
    call __lsl_qbe_call4(__lsl_symbol("gtk_css_provider_load_from_data"), provider, cstr(css), -1, 0)
    screen = __lsl_qbe_call0(__lsl_symbol("gdk_screen_get_default"))
    return __lsl_qbe_call3(__lsl_symbol("gtk_style_context_add_provider_for_screen"), screen, provider, 600)
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
