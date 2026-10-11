# Pure-LSL 2D pixel graphics: RGB surface over IntArray, rasterization,
# 8x16 bitmap text (ASCII plus Czech diacritics) and PPM output.
# One pixel is one Int 0xRRGGBB element; the layout matches 32bpp
# framebuffer rows so a display backend can copy rows directly.

function rgb(r, g, b):
    return Int(r) % 256 * 65536 + Int(g) % 256 * 256 + Int(b) % 256
end

function red(color):
    return color // 65536 % 256
end

function green(color):
    return color // 256 % 256
end

function blue(color):
    return color % 256
end

# --- Compositing: alpha, gradients, anti-aliased rounded shapes ---------
# These give the "liquid glass" look: translucent frosted panels, gradient
# buttons, soft shadows and smooth edges. Alpha is 0..255. Blending is
# straight-alpha over the existing pixel: out = dst + (src - dst) * a / 255.

# All compositing uses fixed-point Int math (1/256 px). Float arithmetic
# in LSL boxes every intermediate on the heap, which made per-pixel shapes
# ~1000x slower and allocation-heavy; integers stay on the raw fast path.
function isqrt(value):
    if value <= 0:
        return 0
    end
    guess = value
    next_guess = (guess + 1) // 2
    while next_guess < guess:
        guess = next_guess
        next_guess = (guess + value // guess) // 2
    end
    return guess
end

function mix_color(bottom, top, alpha):
    a = Int(alpha)
    if a <= 0:
        return bottom
    end
    if a >= 255:
        return top
    end
    br = bottom // 65536 % 256
    bg = bottom // 256 % 256
    bb = bottom % 256
    tr = top // 65536 % 256
    tg = top // 256 % 256
    tb = top % 256
    nr = br + (tr - br) * a // 255
    ng = bg + (tg - bg) * a // 255
    nb = bb + (tb - bb) * a // 255
    return nr * 65536 + ng * 256 + nb
end

# Diagonal two-color gradient over the whole buffer (opaque, no blending).
function raster_gradient(pixels, width, height, top_color, bottom_color):
    data = IntArray(pixels)
    w = Int(width)
    h = Int(height)
    span = w + h - 2
    if span < 1:
        span = 1
    end
    top_value = Int(top_color)
    bottom_value = Int(bottom_color)
    tr = top_value // 65536 % 256
    tg = top_value // 256 % 256
    tb = top_value % 256
    br = bottom_value // 65536 % 256
    bg = bottom_value // 256 % 256
    bb = bottom_value % 256
    y = 0
    while y < h:
        base = y * w
        x = 0
        while x < w:
            numerator = (x + y) * 256 // span
            nr = tr + (br - tr) * numerator // 256
            ng = tg + (bg - tg) * numerator // 256
            nb = tb + (bb - tb) * numerator // 256
            data[base + x] = Int(nr * 65536 + ng * 256 + nb)
            x += 1
        end
        y += 1
    end
    return None
end

# Filled rounded rectangle, anti-aliased and alpha-blended. feather is the
# edge softness in pixels: 1 for a crisp shape, larger for a soft shadow.
function raster_round_rect(pixels, width, height, x, y, rect_w, rect_h, radius, color, alpha, feather):
    call raster_round_rect_grad(pixels, width, height, x, y, rect_w, rect_h, radius, color, color, alpha, feather)
    return None
end

# Same, but the fill is a vertical gradient from top_color to bottom_color.
# Coordinates are held in 1/256 px fixed point so the whole inner loop is
# integer-only: the rounded-corner distance uses an integer square root.
function raster_round_rect_grad(pixels, width, height, x, y, rect_w, rect_h, radius, top_color, bottom_color, alpha, feather):
    data = IntArray(pixels)
    w = Int(width)
    h = Int(height)
    left = Int(x)
    top = Int(y)
    rw = Int(rect_w)
    rh = Int(rect_h)
    base_alpha = Int(alpha)
    soft = Int(feather)
    if soft < 1:
        soft = 1
    end
    cx = left * 256 + rw * 128
    cy = top * 256 + rh * 128
    half_x = rw * 128
    half_y = rh * 128
    r_fix = Int(radius) * 256
    inset_x = half_x - r_fix
    inset_y = half_y - r_fix
    margin = soft + 1
    top_value = Int(top_color)
    bottom_value = Int(bottom_color)
    tr = top_value // 65536 % 256
    tg = top_value // 256 % 256
    tb = top_value % 256
    dr = bottom_value // 65536 % 256
    dg = bottom_value // 256 % 256
    db = bottom_value % 256
    denom = rh - 1
    if denom < 1:
        denom = 1
    end
    py = top - margin
    stop_y = top + rh + margin
    while py < stop_y:
        if py >= 0 and py < h:
            t256 = (py - top) * 256 // denom
            if t256 < 0:
                t256 = 0
            end
            if t256 > 256:
                t256 = 256
            end
            sr = tr + (dr - tr) * t256 // 256
            sg = tg + (dg - tg) * t256 // 256
            sb = tb + (db - tb) * t256 // 256
            row_base = py * w
            dy = py * 256 + 128 - cy
            if dy < 0:
                dy = 0 - dy
            end
            qy = dy - inset_y
            mqy = qy
            if mqy < 0:
                mqy = 0
            end
            square_y = mqy * mqy
            px = left - margin
            stop_x = left + rw + margin
            while px < stop_x:
                if px >= 0 and px < w:
                    dx = px * 256 + 128 - cx
                    if dx < 0:
                        dx = 0 - dx
                    end
                    qx = dx - inset_x
                    mqx = qx
                    if mqx < 0:
                        mqx = 0
                    end
                    # Inlined integer sqrt of the corner distance; interior
                    # pixels short-circuit at zero. Everything here stays a
                    # typed Int so the loop never boxes or allocates.
                    radicand = mqx * mqx + square_y
                    outside = 0
                    if radicand > 0:
                        outside = radicand
                        next_guess = (outside + 1) // 2
                        while next_guess < outside:
                            outside = next_guess
                            next_guess = (outside + radicand // outside) // 2
                        end
                    end
                    inner = qx
                    if qy > inner:
                        inner = qy
                    end
                    if inner > 0:
                        inner = 0
                    end
                    coverage = 128 - (outside + inner - r_fix) // soft
                    if coverage > 0:
                        if coverage > 256:
                            coverage = 256
                        end
                        pixel_alpha = base_alpha * coverage // 256
                        if pixel_alpha > 0:
                            index = row_base + px
                            back = data[index]
                            br = back // 65536 % 256
                            bg = back // 256 % 256
                            bb = back % 256
                            nr = br + (sr - br) * pixel_alpha // 255
                            ng = bg + (sg - bg) * pixel_alpha // 255
                            nb = bb + (sb - bb) * pixel_alpha // 255
                            data[index] = nr * 65536 + ng * 256 + nb
                        end
                    end
                end
                px += 1
            end
        end
        py += 1
    end
    return None
end

# Soft drop shadow: a feathered dark rounded rect, usually offset down.
function raster_shadow(pixels, width, height, x, y, rect_w, rect_h, radius, color, alpha, blur):
    call raster_round_rect(pixels, width, height, x, y, rect_w, rect_h, radius + blur // 2, color, alpha, blur)
    return None
end

# Free rasterizers operate on a raw pixel IntArray plus width/height, so
# both Surface methods and the ui toolkit (which only receives the raw
# buffer, never a typed Surface) share one implementation. Each casts the
# buffer to a typed local, which aliases the same object and keeps the
# inner loops on native indexed stores.
function raster_clear(pixels, width, height, color):
    unsafe:
        data = IntArray(pixels)
        call __lsl_raster_fill(data, 0, Int(width) * Int(height), Int(color))
        return None
    end
end

function raster_set(pixels, width, height, x, y, color):
    px = Int(x)
    py = Int(y)
    w = Int(width)
    if px < 0 or py < 0 or px >= w or py >= Int(height):
        return None
    end
    data = IntArray(pixels)
    data[py * w + px] = Int(color)
    return None
end

function raster_hline(pixels, width, height, x, y, length, color):
    unsafe:
        py = Int(y)
        w = Int(width)
        if py < 0 or py >= Int(height):
            return None
        end
        stop = min(Int(x) + Int(length), w)
        cursor = max(Int(x), 0)
        data = IntArray(pixels)
        call __lsl_raster_fill(data, py * w + cursor, stop - cursor, Int(color))
        return None
    end
end

function raster_vline(pixels, width, height, x, y, length, color):
    px = Int(x)
    w = Int(width)
    if px < 0 or px >= w:
        return None
    end
    stop = min(Int(y) + Int(length), Int(height))
    cursor = max(Int(y), 0)
    data = IntArray(pixels)
    value = Int(color)
    while cursor < stop:
        data[cursor * w + px] = value
        cursor += 1
    end
    return None
end

function raster_fill_rect(pixels, width, height, x, y, w, h, color):
    unsafe:
        stride = Int(width)
        value = Int(color)
        x0 = max(Int(x), 0)
        y0 = max(Int(y), 0)
        x1 = min(Int(x) + Int(w), stride)
        y1 = min(Int(y) + Int(h), Int(height))
        data = IntArray(pixels)
        span = x1 - x0
        row = y0
        while row < y1:
            call __lsl_raster_fill(data, row * stride + x0, span, value)
            row += 1
        end
        return None
    end
end

function raster_rect(pixels, width, height, x, y, w, h, color):
    call raster_hline(pixels, width, height, x, y, w, color)
    call raster_hline(pixels, width, height, x, y + h - 1, w, color)
    call raster_vline(pixels, width, height, x, y, h, color)
    call raster_vline(pixels, width, height, x + w - 1, y, h, color)
    return None
end

function raster_line(pixels, width, height, x0, y0, x1, y1, color):
    dx = abs(x1 - x0)
    dy = abs(y1 - y0)
    step_x = 1
    if x0 > x1:
        step_x = -1
    end
    step_y = 1
    if y0 > y1:
        step_y = -1
    end
    error_term = dx - dy
    x = x0
    y = y0
    loop:
        call raster_set(pixels, width, height, x, y, color)
        if x == x1 and y == y1:
            break
        end
        doubled = error_term * 2
        if doubled > 0 - dy:
            error_term -= dy
            x += step_x
        end
        if doubled < dx:
            error_term += dx
            y += step_y
        end
    end
    return None
end

function raster_blit(dst_pixels, dst_width, dst_height, src_pixels, src_width, src_height, dx, dy):
    unsafe:
        src = IntArray(src_pixels)
        swidth = Int(src_width)
        shift_x = Int(dx)
        shift_y = Int(dy)
        x0 = max(0 - shift_x, 0)
        y0 = max(0 - shift_y, 0)
        x1 = min(swidth, Int(dst_width) - shift_x)
        y1 = min(Int(src_height), Int(dst_height) - shift_y)
        dst = IntArray(dst_pixels)
        dwidth = Int(dst_width)
        span = x1 - x0
        row = y0
        while row < y1:
            call __lsl_raster_copy(dst, src, (row + shift_y) * dwidth + shift_x + x0, row * swidth + x0, span)
            row += 1
        end
        return None
    end
end

# Copy an axis-aligned sub-rectangle between two surfaces at the same
# coordinates (e.g. restoring a cursor-sized patch of a cached backdrop).
# Rows go through the native copy kernel, so the cost is proportional to
# the rectangle, not the surface.
function raster_copy_rect(dst_pixels, dst_width, dst_height, src_pixels, src_width, src_height, x, y, w, h):
    unsafe:
        src = IntArray(src_pixels)
        dst = IntArray(dst_pixels)
        dwidth = Int(dst_width)
        swidth = Int(src_width)
        x0 = max(Int(x), 0)
        y0 = max(Int(y), 0)
        x1 = min(Int(x) + Int(w), min(dwidth, swidth))
        y1 = min(Int(y) + Int(h), min(Int(dst_height), Int(src_height)))
        span = x1 - x0
        row = y0
        while row < y1:
            call __lsl_raster_copy(dst, src, row * dwidth + x0, row * swidth + x0, span)
            row += 1
        end
        return None
    end
end

# Filled circle by horizontal spans; one integer square-root scan per row
# keeps it allocation-free. Used for round buttons.
function raster_fill_circle(pixels, width, height, cx, cy, radius, color):
    unsafe:
        center_x = Int(cx)
        center_y = Int(cy)
        r = Int(radius)
        w = Int(width)
        h = Int(height)
        data = IntArray(pixels)
        value = Int(color)
        dy = 0 - r
        while dy <= r:
            py = center_y + dy
            if py >= 0 and py < h:
                limit = r * r - dy * dy
                dx = 0
                while (dx + 1) * (dx + 1) <= limit:
                    dx += 1
                end
                start = max(center_x - dx, 0)
                stop = min(center_x + dx + 1, w)
                call __lsl_raster_fill(data, py * w + start, stop - start, value)
            end
            dy += 1
        end
        return None
    end
end

# A pill (rounded rectangle) as a middle rectangle plus two end circles.
function raster_fill_pill(pixels, width, height, x, y, w, h, color):
    left = Int(x)
    top = Int(y)
    box_w = Int(w)
    box_h = Int(h)
    radius = box_h // 2
    call raster_fill_rect(pixels, width, height, left + radius, top, box_w - box_h, box_h, color)
    call raster_fill_circle(pixels, width, height, left + radius, top + radius, radius, color)
    call raster_fill_circle(pixels, width, height, left + box_w - radius - 1, top + radius, radius, color)
    return None
end

# Bitmap glyph scaled by an integer factor: each set bit becomes a
# scale x scale block. Lets one embedded font drive large display text.
function raster_glyph_scaled(pixels, width, height, x, y, offset, color, scale):
    left = Int(x)
    top = Int(y)
    w = Int(width)
    h = Int(height)
    factor = Int(scale)
    data = IntArray(pixels)
    value = Int(color)
    rows = IntArray(font_data)
    start = Int(offset)
    row = 0
    while row < 16:
        glyph_bits = rows[start + row]
        if glyph_bits != 0:
            column = 0
            divisor = 128
            while column < 8:
                if glyph_bits // divisor % 2 == 1:
                    block_x = left + column * factor
                    block_y = top + row * factor
                    fy = 0
                    while fy < factor:
                        screen_y = block_y + fy
                        if screen_y >= 0 and screen_y < h:
                            base = screen_y * w
                            fx = 0
                            while fx < factor:
                                screen_x = block_x + fx
                                if screen_x >= 0 and screen_x < w:
                                    data[base + screen_x] = value
                                end
                                fx += 1
                            end
                        end
                        fy += 1
                    end
                end
                column += 1
                divisor = divisor // 2
            end
        end
        row += 1
    end
    return None
end

function raster_text_scaled(pixels, width, height, x, y, value, color, scale):
    factor = Int(scale)
    cursor = Int(x)
    origin = cursor
    for character in value:
        offset = font_index.get(ord(character), 0 - 1)
        if offset >= 0:
            call raster_glyph_scaled(pixels, width, height, cursor, y, offset, color, factor)
        end
        cursor += 8 * factor
    end
    return cursor - origin
end

# Anti-aliased scaled glyph: each output pixel samples the 1-bit source at
# four sub-positions, so on/off edges soften to quarter-coverage steps and
# blend with the background instead of showing a hard staircase.
function raster_glyph_aa(pixels, width, height, x, y, offset, color, alpha, scale):
    left = Int(x)
    top = Int(y)
    w = Int(width)
    h = Int(height)
    factor = Int(scale)
    data = IntArray(pixels)
    rows = IntArray(font_data)
    weights = IntArray(bit_weights)
    start = Int(offset)
    base_alpha = Int(alpha)
    color_value = Int(color)
    cr = color_value // 65536 % 256
    cg = color_value // 256 % 256
    cb = color_value % 256
    quarter = 4 * factor
    out_h = 16 * factor
    out_w = 8 * factor
    oy = 0
    while oy < out_h:
        screen_y = top + oy
        if screen_y >= 0 and screen_y < h:
            row_base = screen_y * w
            row_top = rows[start + (oy * 4 + 1) // quarter]
            row_bottom = rows[start + (oy * 4 + 3) // quarter]
            ox = 0
            while ox < out_w:
                screen_x = left + ox
                if screen_x >= 0 and screen_x < w:
                    col_left = weights[(ox * 4 + 1) // quarter]
                    col_right = weights[(ox * 4 + 3) // quarter]
                    hits = 0
                    if row_top // col_left % 2 == 1:
                        hits += 1
                    end
                    if row_top // col_right % 2 == 1:
                        hits += 1
                    end
                    if row_bottom // col_left % 2 == 1:
                        hits += 1
                    end
                    if row_bottom // col_right % 2 == 1:
                        hits += 1
                    end
                    if hits > 0:
                        pixel_alpha = base_alpha * hits // 4
                        index = row_base + screen_x
                        back = data[index]
                        br = back // 65536 % 256
                        bg = back // 256 % 256
                        bb = back % 256
                        nr = br + (cr - br) * pixel_alpha // 255
                        ng = bg + (cg - bg) * pixel_alpha // 255
                        nb = bb + (cb - bb) * pixel_alpha // 255
                        data[index] = nr * 65536 + ng * 256 + nb
                    end
                end
                ox += 1
            end
        end
        oy += 1
    end
    return None
end

function raster_text_aa(pixels, width, height, x, y, value, color, alpha, scale):
    factor = Int(scale)
    cursor = Int(x)
    origin = cursor
    for character in value:
        offset = font_index.get(ord(character), 0 - 1)
        if offset >= 0:
            call raster_glyph_aa(pixels, width, height, cursor, y, offset, color, alpha, factor)
        end
        cursor += 8 * factor
    end
    return cursor - origin
end

# The glyph row is an 8-bit mask, most significant bit on the left.
function raster_glyph(pixels, width, height, x, y, offset, color):
    left = Int(x)
    top = Int(y)
    w = Int(width)
    h = Int(height)
    if left + 8 <= 0 or left >= w or top + 16 <= 0 or top >= h:
        return None
    end
    data = IntArray(pixels)
    value = Int(color)
    rows = IntArray(font_data)
    start = Int(offset)
    row = 0
    while row < 16:
        screen_y = top + row
        if screen_y >= 0 and screen_y < h:
            glyph_bits = rows[start + row]
            if glyph_bits != 0:
                base = screen_y * w
                column = 0
                divisor = 128
                while column < 8:
                    if glyph_bits // divisor % 2 == 1:
                        screen_x = left + column
                        if screen_x >= 0 and screen_x < w:
                            data[base + screen_x] = value
                        end
                    end
                    column += 1
                    divisor = divisor // 2
                end
            end
        end
        row += 1
    end
    return None
end

function raster_text(pixels, width, height, x, y, value, color):
    cursor = Int(x)
    origin = cursor
    for character in value:
        offset = font_index.get(ord(character), 0 - 1)
        if offset >= 0:
            call raster_glyph(pixels, width, height, cursor, y, offset, color)
        end
        cursor += 8
    end
    return cursor - origin
end

class Surface(True):
    ctype Public

    function init(self, width, height):
        unsafe:
            w = Int(width)
            h = Int(height)
            if w <= 0 or h <= 0:
                Error(GfxError: "surface dimensions must be positive")
            elif w > 16384 or h > 16384 or w > 16777216 // h:
                Error(GfxError: "surface exceeds the secure 16-million-pixel limit")
            end
            self.width = w
            self.height = h
            # Bulk-allocate the pixel buffer in one shot. Building it with a
            # per-element append registers one object per element, which blows
            # the object table up to millions of slots (tens of MB) for a large
            # surface; __lsl_int_zeros allocates the whole buffer at once.
            self.pixels = __lsl_int_zeros(w * h)
        end
    end

    function clear(self, color):
        call raster_clear(self.pixels, self.width, self.height, color)
        return None
    end

    function get(self, x, y):
        if x < 0 or y < 0 or x >= self.width or y >= self.height:
            Error(GfxError: "pixel coordinates out of range")
        end
        return self.pixels[y * self.width + x]
    end

    function set(self, x, y, color):
        call raster_set(self.pixels, self.width, self.height, x, y, color)
        return None
    end

    function hline(self, x, y, length, color):
        call raster_hline(self.pixels, self.width, self.height, x, y, length, color)
        return None
    end

    function vline(self, x, y, length, color):
        call raster_vline(self.pixels, self.width, self.height, x, y, length, color)
        return None
    end

    function fill_rect(self, x, y, w, h, color):
        call raster_fill_rect(self.pixels, self.width, self.height, x, y, w, h, color)
        return None
    end

    function rect(self, x, y, w, h, color):
        call raster_rect(self.pixels, self.width, self.height, x, y, w, h, color)
        return None
    end

    function line(self, x0, y0, x1, y1, color):
        call raster_line(self.pixels, self.width, self.height, x0, y0, x1, y1, color)
        return None
    end

    # Cross-surface member access is not available inside methods, so the
    # caller passes the source fields: screen.blit(s.pixels, s.width,
    # s.height, dx, dy).
    function blit(self, source_pixels, source_width, source_height, dx, dy):
        call raster_blit(self.pixels, self.width, self.height, source_pixels, source_width, source_height, dx, dy)
        return None
    end

    function text(self, x, y, value, color):
        return raster_text(self.pixels, self.width, self.height, x, y, value, color)
    end

    function glyph(self, x, y, offset, color):
        call raster_glyph(self.pixels, self.width, self.height, x, y, offset, color)
        return None
    end

    function save_ppm(self, path):
        header = "P6\n" + String(self.width) + " " + String(self.height) + "\n255\n"
        output = ByteArray()
        for character in header:
            output.append(ord(character))
        end
        pixels = IntArray(self.pixels)
        total = Int(self.width) * Int(self.height)
        index = 0
        while index < total:
            color = pixels[index]
            output.append(color // 65536 % 256)
            output.append(color // 256 % 256)
            output.append(color % 256)
            index += 1
        end
        call writebytes(path, output)
        return None
    end
end

function surface(width, height, color):
    result = Surface(width, height)
    if color != 0:
        call result.clear(color)
    end
    return result
end

function text_width(value):
    return len(value) * 8
end

function text_height():
    return 16
end

font_codes = [
    32, 33, 34, 35, 36, 37, 38, 39, 40, 41, 42, 43, 44, 45, 46, 47,
    48, 49, 50, 51, 52, 53, 54, 55, 56, 57, 58, 59, 60, 61, 62, 63,
    64, 65, 66, 67, 68, 69, 70, 71, 72, 73, 74, 75, 76, 77, 78, 79,
    80, 81, 82, 83, 84, 85, 86, 87, 88, 89, 90, 91, 92, 93, 94, 95,
    96, 97, 98, 99, 100, 101, 102, 103, 104, 105, 106, 107, 108, 109, 110, 111,
    112, 113, 114, 115, 116, 117, 118, 119, 120, 121, 122, 123, 124, 125, 126, 193,
    201, 205, 211, 218, 221, 225, 233, 237, 243, 250, 253, 268, 269, 270, 271, 282,
    283, 327, 328, 344, 345, 352, 353, 356, 357, 366, 367, 381, 382
]
# The glyph table is split into parts: one literal must stay under the
# compiler's 1024-token expression limit (E1118).
font_bits_part1 = [
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 8, 8, 8, 8, 8, 8, 8, 0, 8, 8, 0, 0,
    0, 0, 34, 34, 34, 34, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 18, 18, 18, 126, 36, 36, 126, 72, 72, 72, 0, 0,
    0, 0, 0, 0, 8, 62, 73, 72, 56, 14, 9, 73, 62, 8, 0, 0,
    0, 0, 0, 0, 49, 74, 74, 52, 8, 8, 22, 41, 41, 70, 0, 0,
    0, 0, 0, 0, 28, 34, 34, 20, 24, 41, 69, 66, 70, 57, 0, 0,
    0, 0, 8, 8, 8, 8, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 4, 8, 8, 16, 16, 16, 16, 16, 16, 8, 8, 4, 0,
    0, 0, 0, 32, 16, 16, 8, 8, 8, 8, 8, 8, 16, 16, 32, 0,
    0, 0, 0, 0, 0, 0, 8, 73, 42, 28, 42, 73, 8, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 8, 8, 8, 127, 8, 8, 8, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 24, 8, 8, 16,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 60, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 24, 24, 0, 0,
    0, 0, 0, 0, 2, 2, 4, 8, 8, 16, 16, 32, 64, 64, 0, 0,
    0, 0, 0, 0, 24, 36, 66, 70, 74, 82, 98, 66, 36, 24, 0, 0,
    0, 0, 0, 0, 8, 24, 40, 8, 8, 8, 8, 8, 8, 62, 0, 0,
    0, 0, 0, 0, 60, 66, 66, 2, 12, 16, 32, 64, 64, 126, 0, 0,
    0, 0, 0, 0, 60, 66, 66, 2, 28, 2, 2, 66, 66, 60, 0, 0,
    0, 0, 0, 0, 4, 12, 20, 36, 68, 68, 126, 4, 4, 4, 0, 0,
    0, 0, 0, 0, 126, 64, 64, 64, 124, 2, 2, 2, 66, 60, 0, 0,
    0, 0, 0, 0, 28, 32, 64, 64, 124, 66, 66, 66, 66, 60, 0, 0,
    0, 0, 0, 0, 126, 2, 2, 4, 4, 4, 8, 8, 8, 8, 0, 0,
    0, 0, 0, 0, 60, 66, 66, 66, 60, 66, 66, 66, 66, 60, 0, 0
]
font_bits_part2 = [
    0, 0, 0, 0, 60, 66, 66, 66, 62, 2, 2, 2, 4, 56, 0, 0,
    0, 0, 0, 0, 0, 0, 24, 24, 0, 0, 0, 24, 24, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 24, 24, 0, 0, 0, 24, 8, 8, 16, 0,
    0, 0, 0, 0, 0, 2, 4, 8, 16, 32, 16, 8, 4, 2, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 126, 0, 0, 0, 126, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 64, 32, 16, 8, 4, 8, 16, 32, 64, 0, 0,
    0, 0, 0, 0, 60, 66, 66, 2, 4, 8, 8, 0, 8, 8, 0, 0,
    0, 0, 0, 0, 28, 34, 74, 86, 82, 82, 82, 78, 32, 30, 0, 0,
    0, 0, 0, 0, 24, 36, 36, 66, 66, 126, 66, 66, 66, 66, 0, 0,
    0, 0, 0, 0, 124, 66, 66, 66, 124, 66, 66, 66, 66, 124, 0, 0,
    0, 0, 0, 0, 60, 66, 66, 64, 64, 64, 64, 66, 66, 60, 0, 0,
    0, 0, 0, 0, 120, 68, 66, 66, 66, 66, 66, 66, 68, 120, 0, 0,
    0, 0, 0, 0, 126, 64, 64, 64, 124, 64, 64, 64, 64, 126, 0, 0,
    0, 0, 0, 0, 126, 64, 64, 64, 124, 64, 64, 64, 64, 64, 0, 0,
    0, 0, 0, 0, 60, 66, 66, 64, 64, 78, 66, 66, 70, 58, 0, 0,
    0, 0, 0, 0, 66, 66, 66, 66, 126, 66, 66, 66, 66, 66, 0, 0,
    0, 0, 0, 0, 62, 8, 8, 8, 8, 8, 8, 8, 8, 62, 0, 0,
    0, 0, 0, 0, 31, 4, 4, 4, 4, 4, 4, 68, 68, 56, 0, 0,
    0, 0, 0, 0, 66, 68, 72, 80, 96, 96, 80, 72, 68, 66, 0, 0,
    0, 0, 0, 0, 64, 64, 64, 64, 64, 64, 64, 64, 64, 126, 0, 0,
    0, 0, 0, 0, 66, 66, 102, 102, 90, 90, 66, 66, 66, 66, 0, 0,
    0, 0, 0, 0, 66, 98, 98, 82, 82, 74, 74, 70, 70, 66, 0, 0,
    0, 0, 0, 0, 60, 66, 66, 66, 66, 66, 66, 66, 66, 60, 0, 0,
    0, 0, 0, 0, 124, 66, 66, 66, 124, 64, 64, 64, 64, 64, 0, 0,
    0, 0, 0, 0, 60, 66, 66, 66, 66, 66, 66, 90, 102, 60, 3, 0
]
font_bits_part3 = [
    0, 0, 0, 0, 124, 66, 66, 66, 124, 72, 68, 68, 66, 66, 0, 0,
    0, 0, 0, 0, 60, 66, 66, 64, 48, 12, 2, 66, 66, 60, 0, 0,
    0, 0, 0, 0, 127, 8, 8, 8, 8, 8, 8, 8, 8, 8, 0, 0,
    0, 0, 0, 0, 66, 66, 66, 66, 66, 66, 66, 66, 66, 60, 0, 0,
    0, 0, 0, 0, 65, 65, 65, 34, 34, 34, 20, 20, 8, 8, 0, 0,
    0, 0, 0, 0, 66, 66, 66, 66, 90, 90, 102, 102, 66, 66, 0, 0,
    0, 0, 0, 0, 66, 66, 36, 36, 24, 24, 36, 36, 66, 66, 0, 0,
    0, 0, 0, 0, 65, 65, 34, 34, 20, 8, 8, 8, 8, 8, 0, 0,
    0, 0, 0, 0, 126, 2, 2, 4, 8, 16, 32, 64, 64, 126, 0, 0,
    0, 0, 0, 14, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 14, 0,
    0, 0, 0, 0, 64, 64, 32, 16, 16, 8, 8, 4, 2, 2, 0, 0,
    0, 0, 0, 112, 16, 16, 16, 16, 16, 16, 16, 16, 16, 16, 112, 0,
    0, 0, 24, 36, 66, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 127, 0,
    0, 32, 16, 8, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 60, 66, 2, 62, 66, 66, 70, 58, 0, 0,
    0, 0, 0, 64, 64, 64, 92, 98, 66, 66, 66, 66, 98, 92, 0, 0,
    0, 0, 0, 0, 0, 0, 60, 66, 64, 64, 64, 64, 66, 60, 0, 0,
    0, 0, 0, 2, 2, 2, 58, 70, 66, 66, 66, 66, 70, 58, 0, 0,
    0, 0, 0, 0, 0, 0, 60, 66, 66, 126, 64, 64, 66, 60, 0, 0,
    0, 0, 0, 12, 16, 16, 16, 124, 16, 16, 16, 16, 16, 16, 0, 0,
    0, 0, 0, 0, 0, 2, 58, 68, 68, 68, 56, 32, 60, 66, 66, 60,
    0, 0, 0, 64, 64, 64, 92, 98, 66, 66, 66, 66, 66, 66, 0, 0,
    0, 0, 0, 8, 8, 0, 24, 8, 8, 8, 8, 8, 8, 62, 0, 0,
    0, 0, 0, 4, 4, 0, 12, 4, 4, 4, 4, 4, 4, 4, 72, 48
]
font_bits_part4 = [
    0, 0, 0, 64, 64, 64, 68, 72, 80, 96, 80, 72, 68, 66, 0, 0,
    0, 0, 0, 24, 8, 8, 8, 8, 8, 8, 8, 8, 8, 62, 0, 0,
    0, 0, 0, 0, 0, 0, 118, 73, 73, 73, 73, 73, 73, 73, 0, 0,
    0, 0, 0, 0, 0, 0, 92, 98, 66, 66, 66, 66, 66, 66, 0, 0,
    0, 0, 0, 0, 0, 0, 60, 66, 66, 66, 66, 66, 66, 60, 0, 0,
    0, 0, 0, 0, 0, 0, 92, 98, 66, 66, 66, 66, 98, 92, 64, 64,
    0, 0, 0, 0, 0, 0, 58, 70, 66, 66, 66, 66, 70, 58, 2, 2,
    0, 0, 0, 0, 0, 0, 92, 98, 66, 64, 64, 64, 64, 64, 0, 0,
    0, 0, 0, 0, 0, 0, 60, 66, 64, 48, 12, 2, 66, 60, 0, 0,
    0, 0, 0, 0, 16, 16, 16, 124, 16, 16, 16, 16, 16, 12, 0, 0,
    0, 0, 0, 0, 0, 0, 66, 66, 66, 66, 66, 66, 70, 58, 0, 0,
    0, 0, 0, 0, 0, 0, 66, 66, 66, 36, 36, 36, 24, 24, 0, 0,
    0, 0, 0, 0, 0, 0, 65, 73, 73, 73, 73, 73, 73, 54, 0, 0,
    0, 0, 0, 0, 0, 0, 66, 66, 36, 24, 24, 36, 66, 66, 0, 0,
    0, 0, 0, 0, 0, 0, 66, 66, 66, 66, 66, 38, 26, 2, 2, 60,
    0, 0, 0, 0, 0, 0, 126, 2, 4, 8, 16, 32, 64, 126, 0, 0,
    0, 0, 0, 12, 16, 16, 8, 8, 16, 32, 16, 8, 8, 16, 16, 12,
    0, 0, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8,
    0, 0, 0, 48, 8, 8, 16, 16, 8, 4, 8, 16, 16, 8, 8, 48,
    0, 0, 0, 49, 73, 70, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    12, 48, 0, 0, 24, 36, 36, 66, 66, 126, 66, 66, 66, 66, 0, 0,
    12, 48, 0, 0, 126, 64, 64, 64, 124, 64, 64, 64, 64, 126, 0, 0,
    12, 48, 0, 0, 62, 8, 8, 8, 8, 8, 8, 8, 8, 62, 0, 0,
    12, 48, 0, 0, 60, 66, 66, 66, 66, 66, 66, 66, 66, 60, 0, 0,
    12, 48, 0, 0, 66, 66, 66, 66, 66, 66, 66, 66, 66, 60, 0, 0
]
font_bits_part5 = [
    12, 48, 0, 0, 65, 65, 34, 34, 20, 8, 8, 8, 8, 8, 0, 0,
    0, 0, 12, 48, 0, 0, 60, 66, 2, 62, 66, 66, 70, 58, 0, 0,
    0, 0, 12, 48, 0, 0, 60, 66, 66, 126, 64, 64, 66, 60, 0, 0,
    0, 0, 12, 48, 0, 0, 24, 8, 8, 8, 8, 8, 8, 62, 0, 0,
    0, 0, 12, 48, 0, 0, 60, 66, 66, 66, 66, 66, 66, 60, 0, 0,
    0, 0, 12, 48, 0, 0, 66, 66, 66, 66, 66, 66, 70, 58, 0, 0,
    0, 0, 12, 48, 0, 0, 66, 66, 66, 66, 66, 38, 26, 2, 2, 60,
    36, 24, 0, 0, 60, 66, 66, 64, 64, 64, 64, 66, 66, 60, 0, 0,
    0, 0, 36, 24, 0, 0, 60, 66, 64, 64, 64, 64, 66, 60, 0, 0,
    72, 48, 0, 0, 120, 68, 66, 66, 66, 66, 66, 66, 68, 120, 0, 0,
    0, 0, 0, 22, 18, 18, 84, 176, 144, 144, 144, 144, 176, 80, 0, 0,
    36, 24, 0, 0, 126, 64, 64, 64, 124, 64, 64, 64, 64, 126, 0, 0,
    0, 0, 36, 24, 0, 0, 60, 66, 66, 126, 64, 64, 66, 60, 0, 0,
    36, 24, 0, 0, 66, 98, 98, 82, 82, 74, 74, 70, 70, 66, 0, 0,
    0, 0, 36, 24, 0, 0, 92, 98, 66, 66, 66, 66, 66, 66, 0, 0,
    36, 24, 0, 0, 124, 66, 66, 66, 124, 72, 68, 68, 66, 66, 0, 0,
    0, 0, 36, 24, 0, 0, 92, 98, 66, 64, 64, 64, 64, 64, 0, 0,
    36, 24, 0, 0, 60, 66, 66, 64, 48, 12, 2, 66, 66, 60, 0, 0,
    0, 0, 36, 24, 0, 0, 60, 66, 64, 48, 12, 2, 66, 60, 0, 0,
    36, 24, 0, 0, 127, 8, 8, 8, 8, 8, 8, 8, 8, 8, 0, 0,
    0, 0, 6, 2, 34, 36, 32, 248, 32, 32, 32, 32, 32, 24, 0, 0,
    24, 36, 24, 0, 66, 66, 66, 66, 66, 66, 66, 66, 66, 60, 0, 0,
    0, 0, 24, 36, 24, 0, 66, 66, 66, 66, 66, 66, 70, 58, 0, 0,
    36, 24, 0, 0, 126, 2, 2, 4, 8, 16, 32, 64, 64, 126, 0, 0,
    0, 0, 36, 24, 0, 0, 126, 2, 4, 8, 16, 32, 64, 126, 0, 0
]
font_bits = []
font_bits.extend(font_bits_part1)
font_bits.extend(font_bits_part2)
font_bits.extend(font_bits_part3)
font_bits.extend(font_bits_part4)
font_bits.extend(font_bits_part5)

# Build the fast lookup structures once at module load: packed glyph rows
# in an IntArray and a code-point index into it.
font_data = IntArray()
for bits in font_bits:
    font_data.append(Int(bits))
end
font_index = {}
glyph = 0
while glyph < len(font_codes):
    font_index[font_codes[glyph]] = glyph * 16
    glyph += 1
end

# Column bit weights (MSB first) for glyph sampling without a shift op.
bit_weights = IntArray()
bit_weights.append(128)
bit_weights.append(64)
bit_weights.append(32)
bit_weights.append(16)
bit_weights.append(8)
bit_weights.append(4)
bit_weights.append(2)
bit_weights.append(1)
