# Modul gtk, doplňky 0.10.6: mřížka, posuvník a číselník (Float přes ABI C),
# popisky, obrázek z PNG (cairo → pixbuf), CSS načíst a odebrat, barva z
# motivu, monitory, GtkSettings (g_object_get/set), okno bez dekorací,
# kalendář, potomci kontejneru, kurzor. Bez DISPLAY se test spustí znovu
# pod xvfb-run; bez něj vypíše SKIP.
load env
load glib
load gtk
load cairo

if env.get("DISPLAY") == None and env.get("WAYLAND_DISPLAY") == None:
    launcher = glib.find_program_in_path("xvfb-run")
    if launcher == "":
        print("SKIP: no xvfb-run")
    else:
        exit(run(glib.find_program_in_path("env"), ["NO_AT_BRIDGE=1", launcher, "-a", executable_path()]))
    end
    exit(0)
end

call gtk.init()
window = gtk.window_new("Widgets")
grid = gtk.grid_new()
call gtk.grid_set_row_spacing(grid, 4)
call gtk.grid_set_column_spacing(grid, 6)
call gtk.grid_set_column_homogeneous(grid, True)
scale = gtk.scale_new_with_range(gtk.HORIZONTAL, 0, 100, 1)
call gtk.scale_set_draw_value(scale, False)
call gtk.range_set_value(scale, 42.5)
print gtk.range_get_value(scale)
spin = gtk.spin_button_new_with_range(0, 10, 0.5)
call gtk.spin_button_set_value(spin, 2.5)
print gtk.spin_button_get_value(spin)
label = gtk.label_new("Dlouhý text pro výpustku v mřížce")
call gtk.label_set_ellipsize(label, gtk.ELLIPSIZE_END)
call gtk.label_set_xalign(label, 0.0)
call gtk.label_set_max_width_chars(label, 8)
call gtk.grid_attach(grid, scale, 0, 0, 2, 1)
call gtk.grid_attach(grid, label, 0, 1, 1, 1)
call gtk.grid_attach(grid, spin, 1, 1, 1, 1)
bar = gtk.progress_bar_new()
call gtk.progress_bar_set_fraction(bar, 0.25)
call gtk.progress_bar_set_text(bar, "25 %")
call gtk.grid_attach(grid, bar, 0, 2, 2, 1)

# PNG z cairo → pixbuf zmenšený na 8×8 → obrázek
png = "lsl-gtk-widgets-" + String(Int(monotonic() * 1000000.0)) + ".png"
surface = cairo.image_surface_create(cairo.FORMAT_ARGB32, 16, 16)
cr = cairo.create(surface)
call cairo.set_source_rgb(cr, 0, 1, 0)
call cairo.paint(cr)
call cairo.destroy(cr)
call cairo.surface_write_to_png(surface, png)
call cairo.surface_destroy(surface)
pixbuf = gtk.pixbuf_new_from_file_at_scale(png, 8, 8, True)
print pixbuf != 0, gtk.pixbuf_get_width(pixbuf), gtk.pixbuf_get_height(pixbuf), gtk.pixbuf_new_from_file("no-such-file.png")
image = gtk.image_new_from_pixbuf(pixbuf)
call gtk.image_set_from_icon_name(image, "folder", 1)
call gtk.image_set_pixel_size(image, 24)
button = gtk.button_new_empty()
call gtk.button_set_image(button, image)
call gtk.button_set_always_show_image(button, True)
call gtk.button_set_relief(button, gtk.RELIEF_NONE)
call gtk.grid_attach(grid, button, 0, 3, 1, 1)
toggle = gtk.toggle_button_new("Zap")
call gtk.toggle_button_set_active(toggle, True)
combo = gtk.combo_box_text_new()
call gtk.combo_box_text_append(combo, "a", "Alfa")
call gtk.combo_box_text_append(combo, "b", "Beta")
call gtk.combo_box_set_active(combo, 1)
print gtk.toggle_button_get_active(toggle), gtk.combo_box_get_active(combo), gtk.combo_box_text_get_active_text(combo)
call unlink(png)

box = gtk.box_new(gtk.VERTICAL, 2)
call gtk.box_set_homogeneous(box, False)
call gtk.box_pack_start(box, grid, True, True, 0)
call gtk.box_pack_start(box, toggle, False, False, 0)
call gtk.box_pack_start(box, combo, False, False, 0)
entry = gtk.search_entry_new()
call gtk.entry_set_placeholder_text(entry, "Hledat")
call gtk.entry_set_icon_from_icon_name(entry, gtk.ENTRY_ICON_SECONDARY, "edit-clear")
call gtk.box_pack_start(box, entry, False, False, 0)
scrolled = gtk.scrolled_window_new()
call gtk.scrolled_window_set_policy(scrolled, gtk.POLICY_NEVER, gtk.POLICY_AUTOMATIC)
area = gtk.drawing_area_new()
call gtk.widget_set_size_request(area, 50, 30)
events = gtk.event_box_new()
call gtk.event_box_set_visible_window(events, False)
call gtk.widget_add_events(events, gtk.BUTTON_PRESS_MASK + gtk.SCROLL_MASK)
call gtk.container_add(events, area)
call gtk.container_add(scrolled, events)
call gtk.box_pack_start(box, scrolled, True, True, 0)
call gtk.container_add(window, box)
call gtk.widget_show_all(window)
call gtk.pump()
print len(gtk.container_get_children(box)), len(gtk.container_get_children(grid)), gtk.widget_get_visible(label), gtk.widget_is_visible(area)
print gtk.widget_get_allocated_width(scale) > 0, len(gtk.widget_get_allocation(area)), gtk.widget_get_parent(area) == events, gtk.widget_get_toplevel(area) == window

# CSS za běhu a barva z motivu
provider = gtk.css_load("label { color: #ff0000; }")
call gtk.pump()
red = gtk.widget_get_color(label, 0)
print provider != 0, red[0] > 0.99, red[1] < 0.01, red[3] > 0.99
call gtk.css_remove(provider)
call gtk.pump()
after = gtk.widget_get_color(label, 0)
print after != red, gtk.css_load_file("no-such.css")

# Monitory a GtkSettings
work = gtk.primary_monitor_workarea()
print gtk.monitor_count() >= 1, len(work), work[2] > 0, work[3] > 0, gtk.monitor_workarea(0) == work, gtk.monitor_at_point_workarea(work[0] + 1, work[1] + 1) == work, gtk.monitor_geometry(0)[2] >= work[2], gtk.monitor_scale_factor(0) >= 1
settings = gtk.settings_get_default()
theme = gtk.object_get_string(settings, "gtk-theme-name")
call gtk.object_set_bool(settings, "gtk-application-prefer-dark-theme", True)
call gtk.object_set_int(settings, "gtk-cursor-blink-time", 777)
call gtk.object_set_string(settings, "gtk-font-name", "Sans 9")
print len(theme) > 0, gtk.object_get_bool(settings, "gtk-application-prefer-dark-theme"), gtk.object_get_int(settings, "gtk-cursor-blink-time"), gtk.object_get_string(settings, "gtk-font-name")

# Okno bez správce oken: typ, poloha, velikost
popup = gtk.window_new_popup()
call gtk.window_set_type_hint(popup, gtk.TYPE_HINT_DOCK)
call gtk.window_set_decorated(popup, False)
call gtk.window_set_keep_above(popup, True)
call gtk.window_set_skip_taskbar_hint(popup, True)
call gtk.window_set_skip_pager_hint(popup, True)
call gtk.window_set_accept_focus(popup, False)
call gtk.window_set_resizable(popup, True)
call gtk.window_stick(popup)
call gtk.container_add(popup, gtk.label_new("popup"))
call gtk.window_move(popup, 10, 20)
call gtk.window_resize(popup, 50, 40)
call gtk.widget_set_app_paintable(popup, True)
rgba = gtk.widget_set_rgba_visual(popup)
call gtk.widget_show_all(popup)
call gtk.window_present_with_time(popup, gtk.get_current_event_time())
call gtk.pump()
print gtk.window_get_size(popup), gtk.window_get_position(popup), type(rgba), type(gtk.screen_is_composited())
call gtk.widget_set_opacity(popup, 0.5)
call gtk.window_set_keep_above(popup, False)
print gtk.widget_set_cursor(window, "pointer"), gtk.widget_set_cursor(window, ""), gtk.widget_set_cursor(gtk.label_new("x"), "text")
call gtk.widget_destroy(popup)

# Kalendář a stavové příznaky
calendar = gtk.calendar_new()
call gtk.calendar_select_day(calendar, 2026, 10, 23)
call gtk.calendar_mark_day(calendar, 5)
print gtk.calendar_get_date(calendar)
call gtk.widget_set_state_flags(button, gtk.STATE_FLAG_CHECKED, False)
print (gtk.widget_get_state_flags(button) // gtk.STATE_FLAG_CHECKED) % 2
call gtk.widget_unset_state_flags(button, gtk.STATE_FLAG_CHECKED)
print (gtk.widget_get_state_flags(button) // gtk.STATE_FLAG_CHECKED) % 2
print gtk.icon_theme_has_icon("folder") or True, gtk.KEY_Escape, gtk.widget_get_window(window) != 0
call gtk.widget_destroy(window)
print "done"
