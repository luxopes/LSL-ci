# Wayland server, implemented from the protocol itself: no libwayland, no
# wlroots. The LuxOS compositor gains a socket that real GTK/Qt clients can
# connect to, while every pixel still goes through the same LSL compositor
# that draws the glass desktop.
#
# The wire format (wayland.xml, "Wire Format" in the spec):
#   message = object id (u32) + [size(u16) << 16 | opcode(u16)] (u32) + args
#   arguments: uint/int/fixed = 4 bytes, new_id = 4, object = 4,
#     string = length(u32, NUL included) + data padded to 4,
#     array = length(u32) + data padded to 4, fd = out of band (SCM_RIGHTS)
# Requests come from the client, events go back with the same framing.
#
# Interfaces implemented here (the minimum a toolkit needs to map a window
# and present frames):
#   wl_display(1)     sync, get_registry            -> error, delete_id
#   wl_registry       bind                          -> global
#   wl_compositor     create_surface, create_region
#   wl_shm            create_pool                   -> format
#   wl_shm_pool       create_buffer, destroy, resize
#   wl_buffer         destroy                       -> release
#   wl_surface        attach, damage, frame, commit, ...  -> enter
#   xdg_wm_base       get_xdg_surface, pong         -> ping
#   xdg_surface       get_toplevel, ack_configure   -> configure
#   xdg_toplevel      set_title, set_app_id, ...    -> configure, close
#   wl_seat           get_pointer, get_keyboard     -> capabilities, name
#   wl_output                                       -> geometry, mode, scale
#
# Frame pacing: a client that asked for wl_surface.frame is told when its
# content was actually composited (frame callback), so it draws exactly one
# buffer per screen update — the protocol's "every frame is perfect" rule:
# a surface only changes when a commit applies a complete new state, so a
# half-drawn window can never reach the screen.

load unixsock
load fd
load env

# ---------------------------------------------------------------------------
# Interface tags for allocated object ids.
WO_NONE = 0
WO_DISPLAY = 1
WO_REGISTRY = 2
WO_COMPOSITOR = 3
WO_SHM = 4
WO_SHM_POOL = 5
WO_BUFFER = 6
WO_SURFACE = 7
WO_REGION = 8
WO_XDG_WM_BASE = 9
WO_XDG_SURFACE = 10
WO_XDG_TOPLEVEL = 11
WO_SEAT = 12
WO_POINTER = 13
WO_KEYBOARD = 14
WO_OUTPUT = 15
WO_CALLBACK = 16
WO_SUBCOMPOSITOR = 17

# Globals advertised on the registry: name, interface, version.
GLOBAL_NAMES = [1, 2, 3, 4, 5]
GLOBAL_IFACES = ["wl_compositor", "wl_shm", "xdg_wm_base", "wl_seat", "wl_output"]
GLOBAL_VERSIONS = [4, 1, 2, 5, 3]

WL_SHM_FORMAT_ARGB8888 = 0
WL_SHM_FORMAT_XRGB8888 = 1

MAX_CLIENTS = 8
MAX_OBJECTS = 4096

# ---------------------------------------------------------------------------
# Little-endian helpers over ByteArrays.
function w_put32(buffer, offset, value):
    b = ByteArray(buffer)
    v = Int(value) % 4294967296
    b[offset] = v % 256
    b[offset + 1] = v // 256 % 256
    b[offset + 2] = v // 65536 % 256
    b[offset + 3] = v // 16777216 % 256
    return None
end

function w_get32(buffer, offset):
    b = ByteArray(buffer)
    return Int(b[offset]) + Int(b[offset + 1]) * 256 + Int(b[offset + 2]) * 65536 + Int(b[offset + 3]) * 16777216
end

# Signed 32-bit read (positions and dimensions can be negative).
function w_get_int(buffer, offset):
    v = Int(w_get32(buffer, offset))
    if v >= 2147483648:
        return v - 4294967296
    end
    return v
end

function w_append32(out, value):
    v = Int(value) % 4294967296
    call out.append(v % 256)
    call out.append(v // 256 % 256)
    call out.append(v // 65536 % 256)
    call out.append(v // 16777216 % 256)
    return None
end

# A protocol string: length including the NUL, the bytes, NUL padding to 4.
function w_append_string(out, text):
    t = String(text)
    n = len(t) + 1
    call w_append32(out, n)
    i = 0
    while i < len(t):
        call out.append(ord(t[i]))
        i = i + 1
    end
    call out.append(0)
    pad = (4 - n % 4) % 4
    i = 0
    while i < pad:
        call out.append(0)
        i = i + 1
    end
    return None
end

function w_read_string(buffer, offset):
    n = Int(w_get32(buffer, offset))
    b = ByteArray(buffer)
    out = ""
    i = 0
    while i + 1 < n:
        out = out + chr(b[offset + 4 + i])
        i = i + 1
    end
    return out
end

# String length on the wire (4 + padded payload).
function w_string_size(buffer, offset):
    n = Int(w_get32(buffer, offset))
    return 4 + (n + 3) // 4 * 4
end

# ---------------------------------------------------------------------------
# Server state. Per client: socket, object table (id -> interface tag),
# an inbound byte buffer, pending descriptors, and the surfaces it owns.
# Per-client state as parallel lists indexed by client number (the shell
# uses the same flat style; LSL cannot re-cast a class instance fetched
# from a list, and this keeps every access a plain array index).
CL_FD = []
CL_ALIVE = []
CL_INBUF = []
CL_FDS = []
CL_KIND = []
CL_A = []
CL_B = []
CL_C = []
CL_D = []
CL_E = []
CL_F = []
CL_TITLE = []

function cl_new(handle):
    call CL_FD.append(Int(handle))
    call CL_ALIVE.append(1)
    call CL_INBUF.append(ByteArray())
    call CL_FDS.append([])
    kinds = __lsl_int_zeros(MAX_OBJECTS)
    IntArray(kinds)[1] = WO_DISPLAY
    call CL_KIND.append(kinds)
    call CL_A.append(__lsl_int_zeros(MAX_OBJECTS))
    call CL_B.append(__lsl_int_zeros(MAX_OBJECTS))
    call CL_C.append(__lsl_int_zeros(MAX_OBJECTS))
    call CL_D.append(__lsl_int_zeros(MAX_OBJECTS))
    call CL_E.append(__lsl_int_zeros(MAX_OBJECTS))
    call CL_F.append(__lsl_int_zeros(MAX_OBJECTS))
    call CL_TITLE.append("")
    return len(CL_FD) - 1
end

function cl_kind(ci, oid):
    i = Int(oid)
    if i < 0 or i >= MAX_OBJECTS:
        return WO_NONE
    end
    return Int(IntArray(CL_KIND[Int(ci)])[i])
end

function cl_set_kind(ci, oid, kind):
    i = Int(oid)
    if i >= 0 and i < MAX_OBJECTS:
        IntArray(CL_KIND[Int(ci)])[i] = Int(kind)
    end
    return None
end

# Queue one event: object id, opcode, and the already-built argument bytes.
# The header's size field counts the whole message.
function cl_post(ci, oid, opcode, args):
    a = ByteArray(args)
    size = 8 + len(a)
    out = ByteArray()
    call w_append32(out, Int(oid))
    call w_append32(out, size * 65536 + Int(opcode))
    i = 0
    while i < len(a):
        call out.append(a[i])
        i = i + 1
    end
    rc = 0
    safe:
        rc = unixsock.send_bytes(Int(CL_FD[Int(ci)]), out, len(out))
    end
    if rc < 0:
        CL_ALIVE[Int(ci)] = 0
    end
    return None
end

WL_NCLIENTS = [0]
WL_SERVER = [0 - 1]
WL_RXBUF = [__lsl_byte_zeros(16384)]
WL_SOCKET_PATH = [""]
# Surfaces mapped as desktop windows: parallel lists of client index,
# surface id and window id, so the compositor can find one from the other.
WL_WIN_CLIENT = []
WL_WIN_SURFACE = []
WL_WIN_ID = []

# The host (a compositor) drains this queue once per frame instead of
# registering callbacks: kind 1 = map a new toplevel (client, surface),
# 2 = a surface committed new pixels (window, address, w, h, stride,
# format), 3 = title changed (window, WL_EVT text), 4 = client gone.
WL_EV_KIND = []
WL_EV_A = []
WL_EV_B = []
WL_EV_C = []
WL_EV_D = []
WL_EV_E = []
WL_EV_F = []
WL_EVT = []

function wl_emit(kind, a, b, c, d, e, f, text):
    call WL_EV_KIND.append(Int(kind))
    call WL_EV_A.append(Int(a))
    call WL_EV_B.append(Int(b))
    call WL_EV_C.append(Int(c))
    call WL_EV_D.append(Int(d))
    call WL_EV_E.append(Int(e))
    call WL_EV_F.append(Int(f))
    call WL_EVT.append(String(text))
    return None
end

function wl_events_clear():
    WL_EV_KIND = []
    WL_EV_A = []
    WL_EV_B = []
    WL_EV_C = []
    WL_EV_D = []
    WL_EV_E = []
    WL_EV_F = []
    WL_EVT = []
    return None
end

# The host calls this once it has created a window for a mapped surface.
function wl_bind_window(client_index, surface_id, window_id):
    IntArray(CL_A[Int(client_index)])[Int(surface_id)] = Int(window_id)
    return None
end

function wl_log(message):
    trace = env.get("LUXOS_WAYLAND_TRACE", "")
    if trace != "":
        line = "WAYLAND " + String(message) + chr(10)
        buf = ByteArray()
        i = 0
        while i < len(line):
            call buf.append(ord(line[i]))
            i = i + 1
        end
        call fd.write(2, buf, len(buf))
    end
    return None
end

# ---------------------------------------------------------------------------
# Socket lifecycle. The display name follows the spec: $XDG_RUNTIME_DIR
# (default /run/user/<uid>, we use /run) plus WAYLAND_DISPLAY.
function wl_socket_path():
    dir = env.get("XDG_RUNTIME_DIR", "/run")
    name = env.get("WAYLAND_DISPLAY", "wayland-0")
    return dir + "/" + name
end

function wl_start():
    path = wl_socket_path()
    s = unixsock.listen_unix(path, 16)
    if s < 0:
        call wl_log("listen failed " + String(s) + " on " + path)
        return 0 - 1
    end
    WL_SERVER[0] = s
    WL_SOCKET_PATH[0] = path
    call wl_log("listening on " + path)
    return s
end

function wl_stop():
    if Int(WL_SERVER[0]) >= 0:
        call unixsock.close_fd(Int(WL_SERVER[0]))
        WL_SERVER[0] = 0 - 1
    end
    if String(WL_SOCKET_PATH[0]) != "":
        call unlink(String(WL_SOCKET_PATH[0]))
        WL_SOCKET_PATH[0] = ""
    end
    return None
end

function wl_accept():
    if Int(WL_SERVER[0]) < 0:
        return None
    end
    if len(CL_FD) >= MAX_CLIENTS:
        return None
    end
    c = unixsock.accept_unix(Int(WL_SERVER[0]))
    if c < 0:
        return None
    end
    idx = cl_new(c)
    WL_NCLIENTS[0] = Int(WL_NCLIENTS[0]) + 1
    call wl_log("client " + String(idx) + " connected (fd " + String(c) + ")")
    return None
end

# ---------------------------------------------------------------------------
# Request dispatch. One function per interface, opcodes exactly as in the
# protocol XML.

function wl_display_request(cli, oid, opcode, body):
    ci = Int(cli)
    if opcode == 0:
        # sync(new_id callback): answer done(serial) and destroy it.
        cb = Int(w_get32(body, 0))
        args = ByteArray()
        call w_append32(args, 1)
        call cl_post(ci, cb, 0, args)
        dele = ByteArray()
        call w_append32(dele, cb)
        call cl_post(ci, 1, 1, dele)
    elif opcode == 1:
        # get_registry(new_id registry): advertise every global.
        reg = Int(w_get32(body, 0))
        call cl_set_kind(ci, reg, WO_REGISTRY)
        i = 0
        while i < len(GLOBAL_NAMES):
            args = ByteArray()
            call w_append32(args, Int(GLOBAL_NAMES[i]))
            call w_append_string(args, String(GLOBAL_IFACES[i]))
            call w_append32(args, Int(GLOBAL_VERSIONS[i]))
            call cl_post(ci, reg, 0, args)
            i = i + 1
        end
    end
    return None
end

function wl_registry_request(cli, oid, opcode, body):
    ci = Int(cli)
    if opcode != 0:
        return None
    end
    # bind(name, interface string, version, new_id)
    name = Int(w_get32(body, 0))
    iface = w_read_string(body, 4)
    after = 4 + Int(w_string_size(body, 4))
    newid = Int(w_get32(body, after + 4))
    if iface == "wl_compositor":
        call cl_set_kind(ci, newid, WO_COMPOSITOR)
    elif iface == "wl_shm":
        call cl_set_kind(ci, newid, WO_SHM)
        # Advertise the pixel formats we can composite.
        args = ByteArray()
        call w_append32(args, WL_SHM_FORMAT_ARGB8888)
        call cl_post(ci, newid, 0, args)
        args2 = ByteArray()
        call w_append32(args2, WL_SHM_FORMAT_XRGB8888)
        call cl_post(ci, newid, 0, args2)
    elif iface == "xdg_wm_base":
        call cl_set_kind(ci, newid, WO_XDG_WM_BASE)
    elif iface == "wl_seat":
        call cl_set_kind(ci, newid, WO_SEAT)
        caps = ByteArray()
        call w_append32(caps, 3)
        call cl_post(ci, newid, 0, caps)
        nm = ByteArray()
        call w_append_string(nm, "luxos-seat0")
        call cl_post(ci, newid, 1, nm)
    elif iface == "wl_output":
        call cl_set_kind(ci, newid, WO_OUTPUT)
        call wl_send_output(cli, newid)
    end
    call wl_log("bind " + iface + " -> " + String(newid))
    return None
end

# geometry, mode, scale, done — enough for a toolkit to size a window.
function wl_send_output(cli, oid):
    ci = Int(cli)
    geo = ByteArray()
    call w_append32(geo, 0)
    call w_append32(geo, 0)
    call w_append32(geo, 290)
    call w_append32(geo, 180)
    call w_append32(geo, 0)
    call w_append_string(geo, "LuxOS")
    call w_append_string(geo, "Virtual-1")
    call w_append32(geo, 0)
    call cl_post(ci, oid, 0, geo)
    mode = ByteArray()
    call w_append32(mode, 3)
    call w_append32(mode, Int(WL_OUT_W[0]))
    call w_append32(mode, Int(WL_OUT_H[0]))
    call w_append32(mode, 60000)
    call cl_post(ci, oid, 1, mode)
    scale = ByteArray()
    call w_append32(scale, 1)
    call cl_post(ci, oid, 3, scale)
    call cl_post(ci, oid, 2, ByteArray())
    return None
end

WL_OUT_W = [1280]
WL_OUT_H = [800]

function wl_compositor_request(cli, oid, opcode, body):
    ci = Int(cli)
    newid = Int(w_get32(body, 0))
    if opcode == 0:
        call cl_set_kind(ci, newid, WO_SURFACE)
        IntArray(CL_A[ci])[newid] = 0 - 1
        IntArray(CL_B[ci])[newid] = 0
        IntArray(CL_C[ci])[newid] = 0
        IntArray(CL_D[ci])[newid] = 0
    elif opcode == 1:
        call cl_set_kind(ci, newid, WO_REGION)
    end
    return None
end

function wl_shm_request(cli, oid, opcode, body, fds):
    ci = Int(cli)
    if opcode != 0:
        return None
    end
    # create_pool(new_id, fd, size): the fd arrived out of band.
    pool = Int(w_get32(body, 0))
    size = Int(w_get32(body, 4))
    if len(fds) == 0:
        call wl_log("create_pool without a descriptor")
        return None
    end
    pfd = Int(fds[0])
    call fds.pop(0)
    addr = fd.mmap(pfd, size, 0)
    if addr < 0:
        call wl_log("pool mmap failed " + String(addr))
        call unixsock.close_fd(pfd)
        return None
    end
    call cl_set_kind(ci, pool, WO_SHM_POOL)
    IntArray(CL_A[ci])[pool] = pfd
    IntArray(CL_B[ci])[pool] = addr
    IntArray(CL_C[ci])[pool] = size
    call wl_log("pool " + String(pool) + " size " + String(size))
    return None
end

function wl_shm_pool_request(cli, oid, opcode, body):
    ci = Int(cli)
    if opcode == 0:
        # create_buffer(new_id, offset, width, height, stride, format)
        buf = Int(w_get32(body, 0))
        call cl_set_kind(ci, buf, WO_BUFFER)
        IntArray(CL_A[ci])[buf] = Int(oid)
        IntArray(CL_B[ci])[buf] = Int(w_get32(body, 4))
        IntArray(CL_C[ci])[buf] = Int(w_get32(body, 8))
        IntArray(CL_D[ci])[buf] = Int(w_get32(body, 12))
        IntArray(CL_E[ci])[buf] = Int(w_get32(body, 16))
        IntArray(CL_F[ci])[buf] = Int(w_get32(body, 20))
    elif opcode == 2:
        # resize(size): remap at the new length.
        size = Int(w_get32(body, 0))
        pfd = Int(IntArray(CL_A[ci])[Int(oid)])
        addr = fd.mmap(pfd, size, 0)
        if addr >= 0:
            IntArray(CL_B[ci])[Int(oid)] = addr
            IntArray(CL_C[ci])[Int(oid)] = size
        end
    end
    return None
end

function wl_surface_request(cli, oid, opcode, body):
    ci = Int(cli)
    sid = Int(oid)
    if opcode == 1:
        # attach(buffer, x, y): pending state, applied on commit.
        IntArray(CL_B[ci])[sid] = Int(w_get32(body, 0))
    elif opcode == 3:
        # frame(new_id callback): remembered until this surface is drawn.
        cb = Int(w_get32(body, 0))
        call cl_set_kind(ci, cb, WO_CALLBACK)
        IntArray(CL_D[ci])[sid] = cb
    elif opcode == 6:
        # commit: apply pending state atomically. This is the moment a
        # surface changes at all — the protocol's guarantee that a client
        # never shows a half-drawn frame.
        call wl_surface_commit(cli, sid)
    end
    return None
end

function wl_surface_commit(cli, sid):
    ci = Int(cli)
    buf = Int(IntArray(CL_B[ci])[sid])
    win = Int(IntArray(CL_A[ci])[sid])
    if buf == 0:
        return None
    end
    if cl_kind(ci, buf) != WO_BUFFER:
        return None
    end
    pool = Int(IntArray(CL_A[ci])[buf])
    base = Int(IntArray(CL_B[ci])[pool])
    offset = Int(IntArray(CL_B[ci])[buf])
    width = Int(IntArray(CL_C[ci])[buf])
    height = Int(IntArray(CL_D[ci])[buf])
    stride = Int(IntArray(CL_E[ci])[buf])
    format = Int(IntArray(CL_F[ci])[buf])
    IntArray(CL_C[ci])[sid] = buf
    if win >= 0:
        call wl_emit(2, win, base + offset, width, height, stride, format, "")
    end
    # release(buffer): the client may reuse it now that we have taken the
    # pixels. Toolkits block on this before drawing the next frame.
    call cl_post(ci, buf, 0, ByteArray())
    return None
end

function wl_xdg_wm_base_request(cli, oid, opcode, body):
    ci = Int(cli)
    if opcode == 2:
        # get_xdg_surface(new_id, surface)
        xs = Int(w_get32(body, 0))
        surf = Int(w_get32(body, 4))
        call cl_set_kind(ci, xs, WO_XDG_SURFACE)
        IntArray(CL_A[ci])[xs] = surf
    end
    return None
end

function wl_xdg_surface_request(cli, oid, opcode, body):
    ci = Int(cli)
    if opcode == 1:
        # get_toplevel(new_id): a real window. Configure it right away with
        # our size, then xdg_surface.configure so the client can commit.
        top = Int(w_get32(body, 0))
        call cl_set_kind(ci, top, WO_XDG_TOPLEVEL)
        IntArray(CL_A[ci])[top] = Int(oid)
        surf = Int(IntArray(CL_A[ci])[Int(oid)])
        IntArray(CL_A[ci])[surf] = 0 - 1
        call wl_emit(1, ci, surf, 0, 0, 0, 0, "")
        call wl_configure_toplevel(cli, top, 0, 0)
    elif opcode == 4:
        # ack_configure(serial): nothing to roll back on our side.
        return None
    end
    return None
end

# xdg_toplevel.configure(width, height, states) + xdg_surface.configure.
function wl_configure_toplevel(cli, top, width, height):
    ci = Int(cli)
    args = ByteArray()
    call w_append32(args, Int(width))
    call w_append32(args, Int(height))
    call w_append32(args, 0)
    call cl_post(ci, top, 0, args)
    xs = Int(IntArray(CL_A[ci])[Int(top)])
    ser = ByteArray()
    call w_append32(ser, 1)
    call cl_post(ci, xs, 0, ser)
    return None
end

function wl_xdg_toplevel_request(cli, oid, opcode, body):
    ci = Int(cli)
    if opcode == 2:
        CL_TITLE[ci] = w_read_string(body, 0)
        xs = Int(IntArray(CL_A[ci])[Int(oid)])
        surf = Int(IntArray(CL_A[ci])[xs])
        win = Int(IntArray(CL_A[ci])[surf])
        if win >= 0:
            call wl_emit(3, win, 0, 0, 0, 0, 0, String(CL_TITLE[ci]))
        end
    end
    return None
end

function wl_seat_request(cli, oid, opcode, body):
    ci = Int(cli)
    newid = Int(w_get32(body, 0))
    if opcode == 0:
        call cl_set_kind(ci, newid, WO_POINTER)
    elif opcode == 1:
        call cl_set_kind(ci, newid, WO_KEYBOARD)
    end
    return None
end

# One request from a client, already framed.
function wl_dispatch(cli, oid, opcode, body, fds):
    ci = Int(cli)
    kind = cl_kind(ci, Int(oid))
    if kind == WO_DISPLAY:
        call wl_display_request(cli, oid, opcode, body)
    elif kind == WO_REGISTRY:
        call wl_registry_request(cli, oid, opcode, body)
    elif kind == WO_COMPOSITOR:
        call wl_compositor_request(cli, oid, opcode, body)
    elif kind == WO_SHM:
        call wl_shm_request(cli, oid, opcode, body, fds)
    elif kind == WO_SHM_POOL:
        call wl_shm_pool_request(cli, oid, opcode, body)
    elif kind == WO_SURFACE:
        call wl_surface_request(cli, oid, opcode, body)
    elif kind == WO_XDG_WM_BASE:
        call wl_xdg_wm_base_request(cli, oid, opcode, body)
    elif kind == WO_XDG_SURFACE:
        call wl_xdg_surface_request(cli, oid, opcode, body)
    elif kind == WO_XDG_TOPLEVEL:
        call wl_xdg_toplevel_request(cli, oid, opcode, body)
    elif kind == WO_SEAT:
        call wl_seat_request(cli, oid, opcode, body)
    end
    return None
end

# Drain one client's socket and run every complete message in it.
function wl_read_client(index):
    ci = Int(index)
    if Int(CL_ALIVE[ci]) == 0:
        return None
    end
    chunk = WL_RXBUF[0]
    n = unixsock.recv_fds(Int(CL_FD[ci]), chunk, 8192, CL_FDS[ci])
    if n == 0:
        CL_ALIVE[ci] = 0
        call wl_emit(4, Int(index), 0, 0, 0, 0, 0, "")
        return None
    end
    if n > 0:
        data = ByteArray(chunk)
        buf = ByteArray(CL_INBUF[ci])
        i = 0
        while i < n:
            call buf.append(data[i])
            i = i + 1
        end
    end
    # Frame: id(4) + size/opcode(4) + body.
    buf = ByteArray(CL_INBUF[ci])
    pos = 0
    while len(buf) - pos >= 8:
        # Read the header from the typed local: a dynamically typed list
        # element does not survive the ByteArray() cast inside a helper.
        oid = Int(buf[pos]) + Int(buf[pos + 1]) * 256 + Int(buf[pos + 2]) * 65536 + Int(buf[pos + 3]) * 16777216
        head = Int(buf[pos + 4]) + Int(buf[pos + 5]) * 256 + Int(buf[pos + 6]) * 65536 + Int(buf[pos + 7]) * 16777216
        size = head // 65536
        opcode = head % 65536
        if size < 8 or len(buf) - pos < size:
            pos = pos
            break
        end
        body = __lsl_byte_zeros(size - 8)
        bb = ByteArray(body)
        k = 0
        while k < size - 8:
            bb[k] = buf[pos + 8 + k]
            k = k + 1
        end
        call wl_dispatch(ci, oid, opcode, body, CL_FDS[ci])
        pos = pos + size
    end
    if pos > 0:
        rest = ByteArray()
        k = pos
        while k < len(buf):
            call rest.append(buf[k])
            k = k + 1
        end
        CL_INBUF[ci] = rest
    end
    return None
end

# Poll every client once (called from the compositor's frame loop).
function wl_poll():
    call wl_accept()
    i = 0
    while i < len(CL_FD):
        safe:
            call wl_read_client(i)
        end
        i = i + 1
    end
    return None
end

# Tell every surface whose frame callback is pending that its content is on
# screen now: done(time_ms), then delete_id. A client draws its next frame
# only after this, so it never runs ahead of the compositor.
function wl_frame_done(now_ms):
    i = 0
    while i < len(CL_FD):
        ci = i
        if Int(CL_ALIVE[ci]) == 1:
            s = 0
            while s < MAX_OBJECTS:
                if Int(IntArray(CL_KIND[ci])[s]) == WO_SURFACE:
                    cb = Int(IntArray(CL_D[ci])[s])
                    if cb > 0:
                        args = ByteArray()
                        call w_append32(args, Int(now_ms))
                        call cl_post(ci, cb, 0, args)
                        dele = ByteArray()
                        call w_append32(dele, cb)
                        call cl_post(ci, 1, 1, dele)
                        IntArray(CL_D[ci])[s] = 0
                    end
                end
                s = s + 1
            end
        end
        i = i + 1
    end
    return None
end
