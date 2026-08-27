# Minimal X11 client in pure LSL over a unix socket: handshake with
# MIT-MAGIC-COOKIE-1 auth, one InputOutput window, ZPixmap PutImage
# presentation and key/button/motion/expose/close events. No libX11.
#
# The stateful parts are free functions (not methods) so the unified
# display.Display class can drive them: LSL method dispatch needs a
# statically known receiver type, which a polymorphic backend lacks.

load env
load fd

MAX_XAUTHORITY = 1048576
MAX_X11_REPLY = 1048576
MAX_X11_PENDING = 1048576
MAX_X11_DIMENSION = 16384

function pad4(count):
    return (4 - count % 4) % 4
end

# Readers cast to a typed local first: appending or indexing a computed
# position straight on an Any-typed parameter miscompiles today.
function put16(buffer, value):
    typed = ByteArray(buffer)
    number = Int(value)
    typed.append(number % 256)
    typed.append(number // 256 % 256)
    return None
end

function put32(buffer, value):
    typed = ByteArray(buffer)
    number = Int(value)
    typed.append(number % 256)
    typed.append(number // 256 % 256)
    typed.append(number // 65536 % 256)
    typed.append(number // 16777216 % 256)
    return None
end

function get16(data, offset):
    typed = ByteArray(data)
    start = Int(offset)
    if start < 0 or start > len(typed) - 2:
        Error(X11Error: "truncated 16-bit protocol field")
    end
    return typed[start] + typed[start + 1] * 256
end

function get32(data, offset):
    typed = ByteArray(data)
    start = Int(offset)
    if start < 0 or start > len(typed) - 4:
        Error(X11Error: "truncated 32-bit protocol field")
    end
    return typed[start] + typed[start + 1] * 256 + typed[start + 2] * 65536 + typed[start + 3] * 16777216
end

# Big-endian u16 used by the .Xauthority file format.
function get16be(data, offset):
    typed = ByteArray(data)
    start = Int(offset)
    if start < 0 or start > len(typed) - 2:
        Error(X11Error: "truncated big-endian protocol field")
    end
    return typed[start] * 256 + typed[start + 1]
end

function send_bytes(handle, buffer):
    call fd.write(handle, buffer, len(buffer))
    return None
end

# Blocking read of exactly count bytes from a nonblocking socket.
function read_exact(handle, count):
    if type(count) != "Int" or count < 0 or count > MAX_X11_REPLY:
        Error(X11Error: "X11 reply exceeds the secure limit")
    end
    chunk = ByteArray()
    index = 0
    while index < count:
        chunk.append(0)
        index += 1
    end
    collected = ByteArray()
    deadline = clock() + 10.0
    while len(collected) < count:
        got = fd.read(handle, chunk, count - len(collected))
        if got == fd.again:
            if clock() >= deadline:
                Error(X11Error: "timed out waiting for the X server")
            end
            call __lsl_sleep(0.001)
            continue
        end
        if got == 0:
            Error(X11Error: "X server closed the connection")
        end
        index = 0
        while index < got:
            collected.append(chunk[index])
            index += 1
        end
    end
    return collected
end

# Find the MIT-MAGIC-COOKIE-1 for this display in ~/.Xauthority.
function find_cookie(display):
    path = env.get("XAUTHORITY", "")
    if path == "":
        home = env.get("HOME", "")
        if home == "":
            return ByteArray()
        end
        path = home + "/.Xauthority"
    end
    if not exists(path):
        return ByteArray()
    end
    data = ByteArray(fd.read_all_limit(path, MAX_XAUTHORITY))
    total = len(data)
    offset = 0
    wanted = "MIT-MAGIC-COOKIE-1"
    number_text = String(display)
    while offset + 4 <= total:
        offset += 2
        address_length = get16be(data, offset)
        offset += 2
        if address_length > total - offset:
            return ByteArray()
        end
        offset += address_length
        if offset > total - 2:
            return ByteArray()
        end
        number_length = get16be(data, offset)
        offset += 2
        if number_length > total - offset:
            return ByteArray()
        end
        number = __lsl_text_from_bytes(data, offset, number_length)
        offset += number_length
        if offset > total - 2:
            return ByteArray()
        end
        name_length = get16be(data, offset)
        offset += 2
        if name_length > total - offset:
            return ByteArray()
        end
        name = __lsl_text_from_bytes(data, offset, name_length)
        offset += name_length
        if offset > total - 2:
            return ByteArray()
        end
        data_length = get16be(data, offset)
        offset += 2
        if data_length > total - offset:
            return ByteArray()
        end
        if name == wanted and (number == number_text or number == ""):
            if data_length > 256:
                return ByteArray()
            end
            cookie = ByteArray()
            index = 0
            while index < data_length:
                cookie.append(data[offset + index])
                index += 1
            end
            return cookie
        end
        offset += data_length
    end
    return ByteArray()
end

function display_number():
    display = env.get("DISPLAY", ":0")
    start = display.find(":")
    if start < 0:
        return 0
    end
    rest = display[start + 1:len(display)]
    dot = rest.find(".")
    if dot >= 0:
        rest = rest[0:dot]
    end
    if rest == "":
        return 0
    end
    if len(rest) > 5:
        Error(X11Error: "DISPLAY number is too long")
    end
    for character in rest:
        code = ord(character)
        if code < 48 or code > 57:
            Error(X11Error: "DISPLAY must contain a numeric local display")
        end
    end
    number = Int(rest)
    if number < 0 or number > 65535:
        Error(X11Error: "DISPLAY number is out of range")
    end
    return number
end

# One InternAtom round trip; events arriving meanwhile are ignored,
# which is safe because the window is not mapped yet.
function intern_atom(handle, name):
    if type(name) != "String" or len(name) == 0 or len(name) > 255:
        Error(X11Error: "X11 atom name has an invalid length")
    end
    request = ByteArray()
    request.append(16)
    request.append(0)
    call put16(request, 2 + (len(name) + pad4(len(name))) // 4)
    call put16(request, len(name))
    call put16(request, 0)
    for character in name:
        request.append(ord(character))
    end
    padding = pad4(len(name))
    index = 0
    while index < padding:
        request.append(0)
        index += 1
    end
    call send_bytes(handle, request)
    deadline = clock() + 10.0
    loop:
        if clock() >= deadline:
            Error(X11Error: "timed out waiting for InternAtom")
        end
        message = ByteArray(read_exact(handle, 32))
        kind = message[0]
        if kind == 1:
            return get32(message, 8)
        elif kind == 0:
            Error(X11Error: "X request failed with error code " + String(message[1]))
        end
    end
end

# Encode a String to its UTF-8 bytes. LSL strings iterate by code point,
# and a ByteArray only holds 0..255, so multi-byte characters (e.g. Czech
# diacritics in a window title) must be expanded here.
function utf8_bytes(value):
    out = ByteArray()
    for character in value:
        code = ord(character)
        if code < 128:
            out.append(code)
        elif code < 2048:
            out.append(192 + code // 64)
            out.append(128 + code % 64)
        elif code < 65536:
            out.append(224 + code // 4096)
            out.append(128 + code // 64 % 64)
            out.append(128 + code % 64)
        else:
            out.append(240 + code // 262144)
            out.append(128 + code // 4096 % 64)
            out.append(128 + code // 64 % 64)
            out.append(128 + code % 64)
        end
    end
    return out
end

# ChangeProperty with 8-bit UTF-8 payload (for WM_NAME / _NET_WM_NAME).
function set_property_utf8(handle, window_id, property, kind, value):
    payload = ByteArray(utf8_bytes(value))
    count = len(payload)
    if count > 262116:
        Error(X11Error: "X11 property exceeds one protocol request")
    end
    request = ByteArray()
    request.append(18)
    request.append(0)
    call put16(request, 6 + (count + pad4(count)) // 4)
    call put32(request, window_id)
    call put32(request, property)
    call put32(request, kind)
    request.append(8)
    request.append(0)
    call put16(request, 0)
    call put32(request, count)
    index = 0
    while index < count:
        request.append(payload[index])
        index += 1
    end
    padding = pad4(count)
    index = 0
    while index < padding:
        request.append(0)
        index += 1
    end
    call send_bytes(handle, request)
    return None
end

function set_property_atom(handle, window_id, property, value):
    request = ByteArray()
    request.append(18)
    request.append(0)
    call put16(request, 7)
    call put32(request, window_id)
    call put32(request, property)
    call put32(request, 4)
    request.append(32)
    request.append(0)
    call put16(request, 0)
    call put32(request, 1)
    call put32(request, value)
    call send_bytes(handle, request)
    return None
end

# ChangeProperty with a List of 32-bit words (format 32). Used for
# WM_HINTS so the window manager gives the window keyboard focus.
function set_property_words(handle, window_id, property, kind, words):
    count = len(words)
    if count > 65529:
        Error(X11Error: "X11 word property exceeds one protocol request")
    end
    request = ByteArray()
    request.append(18)
    request.append(0)
    call put16(request, 6 + count)
    call put32(request, window_id)
    call put32(request, property)
    call put32(request, kind)
    request.append(32)
    request.append(0)
    call put16(request, 0)
    call put32(request, count)
    for word in words:
        call put32(request, word)
    end
    call send_bytes(handle, request)
    return None
end

# Connect, authenticate and map one InputOutput window. Returns a
# Dictionary of the raw connection state the caller must keep.
function create_window(width, height, title):
    window_width = Int(width)
    window_height = Int(height)
    if window_width <= 0 or window_width > MAX_X11_DIMENSION or window_height <= 0 or window_height > MAX_X11_DIMENSION:
        Error(X11Error: "X11 window dimensions must be between 1 and 16384")
    end
    if type(title) != "String":
        Error(X11Error: "X11 title must be a String")
    end
    if __lsl_text_byte_length(String(title)) > 262116 or chr(0) in title:
        Error(X11Error: "X11 title is invalid or too long")
    end
    number = display_number()
    handle = fd.connect_unix("/tmp/.X11-unix/X" + String(number))

    cookie = ByteArray(find_cookie(number))
    setup = ByteArray()
    setup.append(108)
    setup.append(0)
    call put16(setup, 11)
    call put16(setup, 0)
    auth_name = ""
    if len(cookie) > 0:
        auth_name = "MIT-MAGIC-COOKIE-1"
    end
    call put16(setup, len(auth_name))
    call put16(setup, len(cookie))
    call put16(setup, 0)
    for character in auth_name:
        setup.append(ord(character))
    end
    padding = pad4(len(auth_name))
    index = 0
    while index < padding:
        setup.append(0)
        index += 1
    end
    index = 0
    while index < len(cookie):
        setup.append(cookie[index])
        index += 1
    end
    padding = pad4(len(cookie))
    index = 0
    while index < padding:
        setup.append(0)
        index += 1
    end
    call send_bytes(handle, setup)

    head = ByteArray(read_exact(handle, 8))
    status = head[0]
    reply_size = get16(head, 6) * 4
    if reply_size > MAX_X11_REPLY:
        Error(X11Error: "X11 setup reply exceeds the secure limit")
    end
    payload = ByteArray(read_exact(handle, reply_size))
    if status != 1:
        reason = ""
        index = 0
        while index < head[1] and index < len(payload):
            reason += chr(payload[index])
            index += 1
        end
        Error(X11Error: "X server refused the connection: " + reason)
    end
    if len(payload) < 40 or payload[20] < 1:
        Error(X11Error: "X server returned a truncated setup reply")
    end

    id_base = get32(payload, 4)
    vendor_length = get16(payload, 16)
    format_count = payload[21]
    screen = 32 + vendor_length + pad4(vendor_length) + format_count * 8
    if screen < 32 or screen > len(payload) - 40:
        Error(X11Error: "X server returned an invalid screen table")
    end
    root = get32(payload, screen)
    root_visual = get32(payload, screen + 32)
    depth = payload[screen + 38]
    window_id = id_base
    gc_id = id_base + 1

    wm_protocols = intern_atom(handle, "WM_PROTOCOLS")
    wm_delete = intern_atom(handle, "WM_DELETE_WINDOW")
    net_wm_name = intern_atom(handle, "_NET_WM_NAME")
    utf8_string = intern_atom(handle, "UTF8_STRING")

    request = ByteArray()
    request.append(1)
    request.append(depth)
    call put16(request, 10)
    call put32(request, window_id)
    call put32(request, root)
    call put16(request, 0)
    call put16(request, 0)
    call put16(request, window_width)
    call put16(request, window_height)
    call put16(request, 0)
    call put16(request, 1)
    call put32(request, root_visual)
    call put32(request, 2 + 2048)
    call put32(request, 0)
    call put32(request, 163919)
    call send_bytes(handle, request)

    # WM_NAME (STRING, best-effort) plus _NET_WM_NAME (UTF8_STRING) so
    # both legacy and modern window managers show the title correctly.
    call set_property_utf8(handle, window_id, 39, 31, title)
    call set_property_utf8(handle, window_id, net_wm_name, utf8_string, title)
    call set_property_atom(handle, window_id, wm_protocols, wm_delete)

    request = ByteArray()
    request.append(55)
    request.append(0)
    call put16(request, 4)
    call put32(request, gc_id)
    call put32(request, window_id)
    call put32(request, 0)
    call send_bytes(handle, request)

    request = ByteArray()
    request.append(8)
    request.append(0)
    call put16(request, 2)
    call put32(request, window_id)
    call send_bytes(handle, request)

    info = {}
    info["handle"] = handle
    info["window_id"] = window_id
    info["gc_id"] = gc_id
    info["depth"] = depth
    info["wm_delete"] = wm_delete
    info["width"] = window_width
    info["height"] = window_height
    return info
end

# Send an already-packed BGRX buffer as ZPixmap PutImage strips. The
# 24-byte header and strip payload are written into the caller's reusable
# `request` buffer by index assignment (no per-strip allocation), so a
# redraw loop produces no garbage for the conservative GC to retain. Each
# strip stays small so one fd.write drains without a write/read deadlock.
function put_image(handle, window_id, gc_id, depth, width, rows, packed, request):
    window_width = Int(width)
    row_count = Int(rows)
    buffer = ByteArray(packed)
    out = ByteArray(request)
    wid = Int(window_id)
    gid = Int(gc_id)
    depth_value = Int(depth)
    if window_width <= 0 or window_width > MAX_X11_DIMENSION or row_count < 0 or row_count > MAX_X11_DIMENSION:
        Error(X11Error: "X11 image dimensions are out of range")
    elif row_count > 0 and window_width > 1073741823 // row_count:
        Error(X11Error: "X11 image dimensions overflow")
    elif len(buffer) < window_width * row_count * 4 or len(out) < 24 + min(row_count, max(1, 16384 // window_width)) * window_width * 4:
        Error(X11Error: "X11 image buffer is truncated")
    end
    strip = 16384 // window_width
    if strip < 1:
        strip = 1
    end
    row = 0
    while row < row_count:
        count = min(strip, row_count - row)
        words = 6 + count * window_width
        out[0] = 72
        out[1] = 2
        out[2] = words % 256
        out[3] = words // 256 % 256
        out[4] = wid % 256
        out[5] = wid // 256 % 256
        out[6] = wid // 65536 % 256
        out[7] = wid // 16777216 % 256
        out[8] = gid % 256
        out[9] = gid // 256 % 256
        out[10] = gid // 65536 % 256
        out[11] = gid // 16777216 % 256
        out[12] = window_width % 256
        out[13] = window_width // 256 % 256
        out[14] = count % 256
        out[15] = count // 256 % 256
        out[16] = 0
        out[17] = 0
        out[18] = row % 256
        out[19] = row // 256 % 256
        out[20] = 0
        out[21] = depth_value
        out[22] = 0
        out[23] = 0
        start = row * window_width * 4
        length = count * window_width * 4
        i = 0
        while i < length:
            out[24 + i] = buffer[start + i]
            i += 1
        end
        call fd.write(handle, out, 24 + length)
        row += count
    end
    return None
end

# Drain pending X events. carry_bytes holds any partial 32-byte event
# left from last time. Returns {events, carry, closed} where events is a
# List of (kind, a, b) tuples with Linux-compatible key codes.
# scratch is a reusable 4096-byte ByteArray owned by the caller, so an
# idle poll allocates almost nothing — important because per-frame garbage
# can be falsely retained by the conservative GC and slowly grow memory.
function read_events(handle, carry_bytes, wm_delete, scratch):
    events = []
    chunk = ByteArray(scratch)
    pending = ByteArray(carry_bytes)
    closed = False
    reads = 0
    loop:
        if reads >= 256:
            break
        end
        got = fd.read(handle, chunk, 4096)
        if got == fd.again or got == 0:
            break
        end
        index = 0
        while index < got:
            if len(pending) >= MAX_X11_PENDING:
                Error(X11Error: "X11 pending event data exceeds 1 MiB")
            end
            pending.append(chunk[index])
            index += 1
        end
        reads += 1
    end
    offset = 0
    total = len(pending)
    while offset + 32 <= total:
        kind = pending[offset] % 128
        if kind == 2 or kind == 3:
            pressed = 1
            if kind == 3:
                pressed = 0
            end
            events.append(("key", pending[offset + 1] - 8, pressed))
        elif kind == 4 or kind == 5:
            pressed = 1
            if kind == 5:
                pressed = 0
            end
            events.append(("button", pending[offset + 1], pressed))
        elif kind == 6:
            x = pending[offset + 24] + pending[offset + 25] * 256
            y = pending[offset + 26] + pending[offset + 27] * 256
            events.append(("motion", x, y))
        elif kind == 12:
            events.append(("expose", 0, 0))
        elif kind == 33:
            atom = pending[offset + 12] + pending[offset + 13] * 256 + pending[offset + 14] * 65536 + pending[offset + 15] * 16777216
            if atom == wm_delete:
                closed = True
                events.append(("close", 0, 0))
            end
        end
        offset += 32
    end
    remainder = ByteArray()
    while offset < total:
        remainder.append(pending[offset])
        offset += 1
    end
    result = {}
    result["events"] = events
    result["carry"] = remainder
    result["closed"] = closed
    return result
end

# Read whatever the server has already sent and append it to carry, so a
# large PutImage write cannot deadlock against a full server->client
# buffer. Returns the extended carry; poll() parses it next time.
function drain(handle, carry_bytes):
    carry = ByteArray(carry_bytes)
    if len(carry) > MAX_X11_PENDING:
        Error(X11Error: "X11 pending data exceeds 1 MiB")
    end
    chunk = ByteArray()
    index = 0
    while index < 4096:
        chunk.append(0)
        index += 1
    end
    reads = 0
    loop:
        if reads >= 256:
            break
        end
        got = fd.read(handle, chunk, 4096)
        if got == fd.again or got == 0:
            break
        end
        cursor = 0
        while cursor < got:
            if len(carry) >= MAX_X11_PENDING:
                Error(X11Error: "X11 pending data exceeds 1 MiB")
            end
            carry.append(chunk[cursor])
            cursor += 1
        end
        reads += 1
    end
    return carry
end

function close(handle):
    call fd.close(handle)
    return None
end
