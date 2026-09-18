# Volitelná rozšíření LSL

Tyto zdroje nejsou kopírovány základním instalátorem. Vývojový compiler
je načítá z checkoutu; instalované LSL vyžaduje `lsl install NAME`.
Publikované kopie a metadata jsou v repozitáři LSL-Packages.

- `gfx`: rasterizace, pixelové plochy a bitmapové fonty.
- `x11`: X11 klient; `wayland`: Wayland protokol/compositor.
- `input`: Linux evdev; `display`: X11/framebuffer/DRM, závisí na x11/input.
- `ui`: widgety, závisí na gfx/input; `css`: styly, závisí na gfx.

První řádek `# lsl: requires NAME ...` je součástí hashovaného zdroje.
Klient jej zpracuje až po ověření SHA-256, kontroluje jména a cykly, následně
ověří a nainstaluje závislosti před překladem rodiče. Žádné instalační
skripty se nespouštějí. Při chybě mohou již nainstalované závislosti zůstat;
jednotlivé zdroje se publikují atomicky. Opakovaná instalace aktualizuje
i deklarované závislosti. Nízkoúrovňové operace jsou explicitně `unsafe`.
