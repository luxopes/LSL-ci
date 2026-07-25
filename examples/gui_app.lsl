# Kompletní GUI aplikace v LSL: okno s tlačítky a checkboxem, reakce na
# myš i klávesnici. Stejný kód běží jako okno na desktopu (X11) i na
# framebufferu LuxOS. Aplikace vlastní display, plochu a smyčku; modul
# ui dodává widgety, zpracování událostí a kreslení.

load gfx
load display
load ui
load time

function on_increment(widget, state):
    state["count"] = state["count"] + 1
    return None
end

function on_reset(widget, state):
    state["count"] = 0
    return None
end

function on_quit(widget, state):
    state["running"] = False
    return None
end

d = display.open(560, 380, "LSL GUI aplikace")
screen = gfx.surface(d.width, d.height, 0)

state = ui.new_state()
state["count"] = 0

widgets = []
widgets.append(ui.label(30, 30, "Počítadlo kliknutí:"))
widgets.append(ui.button(30, 70, 150, 40, "Přidej +1", on_increment))
widgets.append(ui.button(200, 70, 150, 40, "Vynuluj", on_reset))
widgets.append(ui.checkbox(30, 140, "Zobrazit nápovědu", True))
widgets.append(ui.button(30, 320, 150, 40, "Konec", on_quit))
help_index = 3

while state["running"] and not d.should_close():
    call ui.process(widgets, state, d.poll())
    call ui.paint(screen.pixels, screen.width, screen.height, widgets, ui.color_background)
    call screen.text(230, 40, "= " + String(state["count"]), ui.color_accent_text)
    if widgets[help_index]["checked"]:
        call screen.text(30, 180, "Klikni na tlačítka nebo stiskni Esc.", ui.color_muted)
        call screen.text(30, 200, "Poslední klávesa: " + String(state["key"]), ui.color_muted)
    end
    call d.present(screen.pixels, screen.width, screen.height)
    call time.sleep(0.016)
end

call d.close()
print "hotovo, počet:", state["count"]
