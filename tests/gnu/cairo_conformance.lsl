# Moduly cairo a pango na cíli linux-x86_64-gnu bez displeje: kreslení do
# obrázku v paměti (double argumenty volání C, návrat double), pixely,
# text přes Pango (rozměry, výpustka), PNG na disk.
load cairo
load pango

surface = cairo.image_surface_create(cairo.FORMAT_ARGB32, 40, 30)
print cairo.surface_status(surface), cairo.image_surface_get_width(surface), cairo.image_surface_get_height(surface)
cr = cairo.create(surface)
call cairo.set_source_rgb(cr, 1, 1, 1)
call cairo.paint(cr)
call cairo.set_source_rgba(cr, 1.0, 0.0, 0.0, 1.0)
call cairo.rectangle(cr, 10, 5, 20, 10)
call cairo.fill(cr)
print cairo.image_surface_pixel(surface, 15, 8) == 4294901760, cairo.image_surface_pixel(surface, 2, 2) == 4294967295
call cairo.set_line_width(cr, 2.5)
print cairo.get_line_width(cr)
call cairo.set_source_color(cr, [0.0, 0.0, 1.0, 1.0])
call cairo.arc(cr, 20, 20, 6, 0, 2 * cairo.PI)
call cairo.fill(cr)
print cairo.image_surface_pixel(surface, 20, 20) == 4278190335
call cairo.save(cr)
call cairo.translate(cr, 30, 0)
call cairo.set_source_rgb(cr, 0, 0, 0)
call cairo.rounded_rectangle(cr, 1, 20, 8, 8, 2)
call cairo.set_dash(cr, [2, 1], 0)
call cairo.stroke(cr)
call cairo.restore(cr)
print cairo.status(cr)

# Pango: text má kladné rozměry, širší text je širší, výpustka omezí šířku.
size = pango.text_size(cr, "Ahoj", "Sans 10")
wide = pango.text_size(cr, "Ahoj světe, dlouhý text", "Sans 10")
print size[0] > 0, size[1] > 0, wide[0] > size[0], wide[1] == size[1]
layout = pango.cairo_create_layout(cr)
call pango.layout_set_font(layout, "Sans 10")
call pango.layout_set_text(layout, "Ahoj světe, dlouhý text")
call pango.layout_set_width(layout, 60)
call pango.layout_set_ellipsize(layout, pango.ELLIPSIZE_END)
print pango.layout_get_pixel_size(layout)[0] <= 60, pango.layout_is_ellipsized(layout), pango.layout_get_line_count(layout)
call pango.layout_set_markup(layout, "<b>tučně</b> a <i>kurzíva</i>")
call cairo.move_to(cr, 0, 0)
call pango.cairo_show_layout(cr, layout)
baseline = pango.layout_get_baseline(layout)
call pango.layout_unref(layout)
drawn = pango.draw_text(cr, 2, 12, "x", "Sans 8")
print drawn[0] > 0, drawn[1] > 0, baseline > 0

path = "lsl-cairo-test-" + String(Int(monotonic() * 1000000.0)) + ".png"
print cairo.surface_write_to_png(surface, path), len(readbytes(path)) > 100
call unlink(path)
call cairo.destroy(cr)
call cairo.surface_destroy(surface)
print "done"
