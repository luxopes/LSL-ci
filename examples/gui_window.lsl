# GUI aplikace s vlastním oknem. Na desktopu (DISPLAY) se otevře X11
# okno, na textové konzoli LuxOS stejný kód kreslí na framebuffer.
# Šipky posouvají panel, Esc nebo zavření okna aplikaci ukončí.

load gfx
load display
load input
load time

d = display.open(640, 400, "LSL aplikace")
screen = gfx.surface(d.width, d.height, 0)

background = gfx.rgb(16, 18, 26)
panel = gfx.rgb(52, 120, 246)
x = d.width // 2 - 110
y = d.height // 2 - 80
running = True

while running and not d.should_close():
    for event in d.poll():
        name = event[0]
        code = event[1]
        value = event[2]
        if name == "key" and (value == input.press or value == input.repeat):
            if code == input.key_left:
                x -= 16
            elif code == input.key_right:
                x += 16
            elif code == input.key_up:
                y -= 16
            elif code == input.key_down:
                y += 16
            elif code == input.key_esc or code == input.key_q:
                running = False
            end
        end
    end
    call screen.clear(background)
    call screen.fill_rect(x, y, 220, 160, panel)
    call screen.rect(x, y, 220, 160, gfx.rgb(255, 255, 255))
    call screen.text(x + 16, y + 16, "LSL aplikace", gfx.rgb(255, 255, 255))
    call screen.text(x + 16, y + 40, "šipky = pohyb", gfx.rgb(200, 210, 235))
    call screen.text(x + 16, y + 60, "Esc = konec", gfx.rgb(200, 210, 235))
    call d.present(screen.pixels, screen.width, screen.height)
    call time.sleep(0.016)
end

call d.close()
print "hotovo"
