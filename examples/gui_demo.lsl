# GUI kreslení v čistém LSL: okno s textem se uloží do PPM souboru,
# takže příklad běží i bez framebufferu. Na konzoli s /dev/fb0 ukáže
# examples/gui_fb_demo.lsl stejnou scénu naživo.

load gfx

screen = gfx.surface(640, 360, gfx.rgb(24, 26, 34))

call screen.fill_rect(40, 40, 360, 180, gfx.rgb(52, 120, 246))
call screen.rect(40, 40, 360, 180, gfx.rgb(255, 255, 255))
call screen.text(64, 64, "Ahoj z LSL!", gfx.rgb(255, 255, 255))
call screen.text(64, 88, "Příliš žluťoučký kůň úpěl ďábelské ódy", gfx.rgb(220, 230, 255))
call screen.line(40, 260, 600, 300, gfx.rgb(246, 190, 60))

icon = gfx.surface(24, 24, gfx.rgb(230, 60, 60))
call icon.rect(0, 0, 24, 24, gfx.rgb(255, 255, 255))
call screen.blit(icon.pixels, icon.width, icon.height, 560, 48)

call screen.save_ppm("gui_demo.ppm")
print "uloženo: gui_demo.ppm (640x360)"
