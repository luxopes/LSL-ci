# Modul gtk na cíli linux-x86_64-gnu: widgety, CSS, signály (clicked, draw
# s argumentem před instancí, delete-event), text zpět z GTK, časovač.
# Bez DISPLAY se test spustí znovu pod xvfb-run; bez něj vypíše SKIP.
load env
load glib
load gtk

if env.get("DISPLAY") == None and env.get("WAYLAND_DISPLAY") == None:
    launcher = glib.find_program_in_path("xvfb-run")
    if launcher == "":
        print("SKIP: no xvfb-run")
    else:
        exit(run(launcher, ["-a", executable_path()]))
    end
    exit(0)
end

clicks = 0
draws = 0
toggles = []

function on_click(button):
    global clicks
    clicks += 1
    call gtk.label_set_text(label, "clicked " + String(clicks))
    call gtk.button_set_label(button, "again")
    return 0
end

function on_draw(cr, widget):
    global draws
    draws += 1
    if cr == 0 or widget != area:
        print("draw arguments wrong")
    end
    return False
end

function on_toggle(state, switch):
    toggles.append(state)
    return False
end

function on_delete(event, window):
    return True
end

function on_tick():
    if clicks == 0:
        call gtk.button_clicked(button)
        return True
    end
    if draws > 0:
        call gtk.main_quit()
        return False
    end
    return True
end

function give_up():
    print("timeout, draws", draws)
    call gtk.main_quit()
    return False
end

call gtk.init()
print("GTK major:", gtk.version()[0])
call gtk.css_load("#test label { font-weight: bold; }")
window = gtk.window_new("LSL test")
call gtk.widget_set_name(window, "test")
call gtk.window_set_default_size(window, 200, 120)
box = gtk.box_new(gtk.VERTICAL, 4)
label = gtk.label_new("ready")
button = gtk.button_new("click")
entry = gtk.entry_new()
switch = gtk.switch_new()
area = gtk.box_new(gtk.HORIZONTAL, 0)
call gtk.widget_set_size_request(area, 40, 40)
call gtk.box_pack_start(box, label, False, False, 0)
call gtk.box_pack_start(box, button, False, False, 0)
call gtk.box_pack_start(box, entry, False, False, 0)
call gtk.box_pack_start(box, switch, False, False, 0)
call gtk.box_pack_start(box, area, True, True, 0)
call gtk.container_add(window, box)
call gtk.entry_set_text(entry, "žluťoučký kůň")
call gtk.connect(button, "clicked", on_click)
call gtk.connect(area, "draw", on_draw)
call gtk.connect(switch, "state-set", on_toggle)
call gtk.connect(window, "delete-event", on_delete)
call gtk.switch_set_active(switch, True)
call gtk.timeout_add(10, on_tick)
call gtk.timeout_add(5000, give_up)
call gtk.widget_show_all(window)
call gtk.main()
print("label:", gtk.label_get_text(label))
print("entry:", gtk.entry_get_text(entry), len(gtk.entry_get_text(entry)))
print("switch:", gtk.switch_get_active(switch), toggles)
print("clicks:", clicks, "drawn:", draws > 0)
call gtk.widget_destroy(window)
print("done")
