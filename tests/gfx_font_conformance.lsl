load gfx

check(len(gfx.font_data) == len(gfx.font_codes) * 16, "font table length")
check(len(gfx.font_codes) == len(gfx.font_index), "font code uniqueness")
check(gfx.font_index[ord("ž")] >= 0, "Czech glyph")
surface = gfx.Surface(64, 32)
call surface.clear(gfx.rgb(1, 2, 3))
check(surface.get(0, 0) == 66051, "surface clear")
call surface.text(0, 0, "Až", gfx.rgb(255, 255, 255))
changed = 0
for pixel in surface.pixels:
    if pixel != 66051:
        changed += 1
    end
end
check(changed > 10, "glyph rasterization")
print "gfx split font table and Czech glyph rendering passed"
