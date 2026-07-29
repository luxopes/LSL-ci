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
# What a GTK3/Firefox client needs and gets here:
#   wl_display        sync, get_registry        -> error, delete_id
#   wl_registry       bind                      -> global
#   wl_compositor     create_surface/region
#   wl_subcompositor  get_subsurface
#   wl_shm(_pool)     create_pool/buffer        -> format
#   wl_buffer                                   -> release
#   wl_surface        attach/damage/frame/commit/... (atomic pending state)
#   wl_seat           get_pointer/keyboard      -> capabilities, name
#   wl_pointer                                  -> enter/leave/motion/button/
#                                                  axis(+discrete), frame
#   wl_keyboard                                 -> keymap(xkb fd)/enter/leave/
#                                                  key/modifiers/repeat_info
#   wl_data_device_manager                      (inert clipboard stubs)
#   wl_output                                   -> geometry/mode/scale/done
#   xdg_wm_base       positioner/get_xdg_surface -> ping
#   xdg_surface       get_toplevel/get_popup/window_geometry -> configure
#   xdg_toplevel      title/app_id/move/resize/... -> configure, close
#   xdg_popup         grab                      -> configure, popup_done
#
# Frame pacing is the protocol's own ("every frame is perfect"): commits
# apply complete double-buffered state atomically, wl_buffer.release is
# posted once the pixels were taken, and frame callbacks fire only after
# the compositor actually composited the surface.
#
# Transport rules learned the hard way: every socket is nonblocking, all
# outgoing events land in a per-client buffer flushed at the end of the
# frame (a stalled client must never stall the compositor), inbound work
# is bounded per tick, and a descriptor-carrying message (the keymap) is
# its own sendmsg between buffer flushes.

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
WO_SUBSURFACE = 18
WO_DDM = 19
WO_DATA_DEVICE = 20
WO_DATA_SOURCE = 21
WO_POSITIONER = 22
WO_XDG_POPUP = 23
WO_TOUCH = 24

# Surface roles.
ROLE_NONE = 0
ROLE_TOPLEVEL = 1
ROLE_POPUP = 2
ROLE_CURSOR = 3
ROLE_SUBSURFACE = 4

# Globals advertised on the registry: name, interface, version.
GLOBAL_NAMES = [1, 2, 3, 4, 5, 6, 7]
GLOBAL_IFACES = ["wl_compositor", "wl_shm", "xdg_wm_base", "wl_seat", "wl_output", "wl_subcompositor", "wl_data_device_manager"]
GLOBAL_VERSIONS = [4, 1, 2, 5, 3, 1, 3]

WL_SHM_FORMAT_ARGB8888 = 0
WL_SHM_FORMAT_XRGB8888 = 1

MAX_CLIENTS = 32
MAX_OBJECTS = 4096
OUT_LIMIT = 4194304

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
# Server state. Per-client state as parallel lists indexed by client number
# (LSL cannot re-cast a class instance fetched from a list, and this keeps
# every access a plain array index). Object state lives in flat per-client
# arrays A..H indexed by protocol object id; what each slot means depends
# on the object's interface tag:
#   SURFACE   A win  B pending-buffer  C committed  D frame-cb  E xdg  F role
#             (damage union in CL_D0..CL_D3, subsurface pos in G/H)
#   XDGSURF   A surface  B role-object  C..F window geometry x/y/w/h
#   TOPLEVEL  A xdg-surface
#   POPUP     A xdg-surface  B parent-xdg  C grabbed
#   POSITIONER A w  B h  C..F anchor rect  G anchor*16+gravity  H offset
#   POOL      A fd  B addr  C size  D live-buffers  E destroyed
#   BUFFER    A pool  B offset  C w  D h  E stride  F format
#   SUBSURF   A surface  B parent-surface
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
CL_G = []
CL_H = []
CL_D0 = []
CL_D1 = []
CL_D2 = []
CL_D3 = []
CL_TITLE = []
CL_OUT = []
CL_OUTOFF = []
# Descriptor markers into CL_OUT: byte offset, fd, and whether the fd
# survives the send (the shared keymap does, a clipboard pipe does not).
CL_FDPOS = []
CL_FDVAL = []
CL_FDKEEP = []
CL_MAXID = []
CL_SEATV = []
CL_PTRL = []
CL_KBDL = []
CL_OUTID = []

# A client slot, reusing the first dead one: without this the server stops
# accepting after MAX_CLIENTS launches, however many have since quit.
function cl_new(handle):
    i = 0
    while i < len(CL_FD):
        if Int(CL_ALIVE[i]) == 0:
            CL_FD[i] = Int(handle)
            CL_ALIVE[i] = 1
            CL_INBUF[i] = ByteArray()
            CL_FDS[i] = []
            kinds = __lsl_int_zeros(MAX_OBJECTS)
            IntArray(kinds)[1] = WO_DISPLAY
            CL_KIND[i] = kinds
            CL_A[i] = __lsl_int_zeros(MAX_OBJECTS)
            CL_B[i] = __lsl_int_zeros(MAX_OBJECTS)
            CL_C[i] = __lsl_int_zeros(MAX_OBJECTS)
            CL_D[i] = __lsl_int_zeros(MAX_OBJECTS)
            CL_E[i] = __lsl_int_zeros(MAX_OBJECTS)
            CL_F[i] = __lsl_int_zeros(MAX_OBJECTS)
            CL_G[i] = __lsl_int_zeros(MAX_OBJECTS)
            CL_H[i] = __lsl_int_zeros(MAX_OBJECTS)
            CL_D0[i] = __lsl_int_zeros(MAX_OBJECTS)
            CL_D1[i] = __lsl_int_zeros(MAX_OBJECTS)
            CL_D2[i] = __lsl_int_zeros(MAX_OBJECTS)
            CL_D3[i] = __lsl_int_zeros(MAX_OBJECTS)
            CL_TITLE[i] = ""
            CL_OUT[i] = ByteArray()
            CL_OUTOFF[i] = 0
            CL_FDPOS[i] = []
            CL_FDVAL[i] = []
            CL_FDKEEP[i] = []
            CL_MAXID[i] = 2
            CL_SEATV[i] = 1
            CL_PTRL[i] = []
            CL_KBDL[i] = []
            CL_OUTID[i] = 0
            CL_DDEV[i] = 0
            CL_SRVID[i] = 0
            CL_OFFER[i] = 0
            return i
        end
        i = i + 1
    end
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
    call CL_G.append(__lsl_int_zeros(MAX_OBJECTS))
    call CL_H.append(__lsl_int_zeros(MAX_OBJECTS))
    call CL_D0.append(__lsl_int_zeros(MAX_OBJECTS))
    call CL_D1.append(__lsl_int_zeros(MAX_OBJECTS))
    call CL_D2.append(__lsl_int_zeros(MAX_OBJECTS))
    call CL_D3.append(__lsl_int_zeros(MAX_OBJECTS))
    call CL_TITLE.append("")
    call CL_OUT.append(ByteArray())
    call CL_OUTOFF.append(0)
    call CL_FDPOS.append([])
    call CL_FDVAL.append([])
    call CL_FDKEEP.append([])
    call CL_MAXID.append(2)
    call CL_SEATV.append(1)
    call CL_PTRL.append([])
    call CL_KBDL.append([])
    call CL_OUTID.append(0)
    call CL_DDEV.append(0)
    call CL_SRVID.append(0)
    call CL_OFFER.append(0)
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
    c = Int(ci)
    if i >= 0 and i < MAX_OBJECTS:
        IntArray(CL_KIND[c])[i] = Int(kind)
        if i >= Int(CL_MAXID[c]):
            CL_MAXID[c] = i + 1
        end
    end
    return None
end

# Queue one event into the client's outbound buffer: object id, opcode and
# already-built argument bytes. The size field counts the whole message.
# Nothing is sent here — wl_flush drains the buffer at frame end, so a
# stuck client can never block the compositor mid-dispatch.
function cl_post(ci, oid, opcode, args):
    c = Int(ci)
    if Int(CL_ALIVE[c]) == 0:
        return None
    end
    a = ByteArray(args)
    out = ByteArray(CL_OUT[c])
    if len(out) > OUT_LIMIT:
        # The client stopped reading long ago; cut it loose.
        call wl_client_drop(c)
        return None
    end
    size = 8 + len(a)
    call w_append32(out, Int(oid))
    call w_append32(out, size * 65536 + Int(opcode))
    i = 0
    n = len(a)
    while i < n:
        call out.append(a[i])
        i = i + 1
    end
    return None
end

# The same, carrying one descriptor (keymap, clipboard transfer). The fd
# must ride with ITS message and no other, so instead of writing to the
# socket behind the buffer's back — which would splice bytes into a
# half-sent message and desynchronise the client — the offset is marked
# and wl_flush sends exactly that message with the descriptor attached.
# keep = 1 leaves the descriptor open afterwards (one keymap, many
# clients); keep = 0 closes it once it is on its way.
function cl_post_fd(ci, oid, opcode, args, handle, keep):
    c = Int(ci)
    if Int(CL_ALIVE[c]) == 0:
        if Int(keep) == 0:
            call unixsock.close_fd(Int(handle))
        end
        return None
    end
    out = ByteArray(CL_OUT[c])
    call CL_FDPOS[c].append(len(out))
    call CL_FDVAL[c].append(Int(handle))
    call CL_FDKEEP[c].append(Int(keep))
    call cl_post(c, oid, opcode, args)
    return None
end

# An object destroyed by its client: forget it and let the client reuse the
# id (wl_display.delete_id) — without this a long-lived client leaks ids
# until it hits MAX_OBJECTS.
function wl_destroy_object(ci, oid):
    call cl_set_kind(ci, oid, WO_NONE)
    args = ByteArray()
    call w_append32(args, Int(oid))
    call cl_post(ci, 1, 1, args)
    return None
end

# Flush as much buffered output as the socket accepts; keep the rest. The
# buffer is sent in segments so a marked message goes out with its
# descriptor and nothing else rides along with it.
function wl_flush(index):
    ci = Int(index)
    if Int(CL_ALIVE[ci]) == 0:
        return None
    end
    out = ByteArray(CL_OUT[ci])
    off = Int(CL_OUTOFF[ci])
    pos = CL_FDPOS[ci]
    stop = 0
    while stop == 0 and len(out) - off > 0:
        # Drop markers the stream has already passed (a partial send takes
        # the descriptor with its first byte).
        while len(pos) > 0 and Int(pos[0]) < off:
            call CL_FDPOS[ci].pop(0)
            if Int(CL_FDKEEP[ci][0]) == 0:
                call unixsock.close_fd(Int(CL_FDVAL[ci][0]))
            end
            call CL_FDVAL[ci].pop(0)
            call CL_FDKEEP[ci].pop(0)
        end
        want = len(out) - off
        h = 0 - 1
        if len(pos) > 0:
            if Int(pos[0]) == off:
                # Exactly this message, with its descriptor.
                want = Int(out[off + 6]) + Int(out[off + 7]) * 256
                h = Int(CL_FDVAL[ci][0])
            else:
                want = Int(pos[0]) - off
            end
        end
        if want > len(out) - off:
            want = len(out) - off
        end
        rc = 0 - 11
        safe:
            rc = unixsock.send_from_fd(Int(CL_FD[ci]), out, off, want, h)
        end
        if rc > 0:
            off = off + rc
        elif rc == 0 - 11 or rc == 0 - 4:
            stop = 1
        else:
            call wl_client_drop(ci)
            return None
        end
        if rc < want:
            stop = 1
        end
    end
    while len(pos) > 0 and Int(pos[0]) < off:
        call CL_FDPOS[ci].pop(0)
        if Int(CL_FDKEEP[ci][0]) == 0:
            call unixsock.close_fd(Int(CL_FDVAL[ci][0]))
        end
        call CL_FDVAL[ci].pop(0)
        call CL_FDKEEP[ci].pop(0)
    end
    if off >= len(out):
        CL_OUT[ci] = ByteArray()
        CL_OUTOFF[ci] = 0
    elif off > 65536 and off * 2 > len(out):
        # Compact once the consumed prefix dominates the buffer.
        rest = ByteArray()
        k = off
        while k < len(out):
            call rest.append(out[k])
            k = k + 1
        end
        CL_OUT[ci] = rest
        mi = 0
        while mi < len(CL_FDPOS[ci]):
            CL_FDPOS[ci][mi] = Int(CL_FDPOS[ci][mi]) - off
            mi = mi + 1
        end
        CL_OUTOFF[ci] = 0
    else:
        CL_OUTOFF[ci] = off
    end
    return None
end

function wl_flush_all():
    i = 0
    while i < len(CL_FD):
        call wl_flush(i)
        i = i + 1
    end
    return None
end

WL_NCLIENTS = [0]
WL_SERVER = [0 - 1]
WL_RXBUF = [__lsl_byte_zeros(65536)]
WL_SOCKET_PATH = [""]
WL_SERIAL = [16]
WL_TIME = [0]

# Shared-memory pools live in their own table with stable handles: protocol
# ids get reused after delete_id, and a buffer must never chase a pool id
# that now names some other object (that path reads arbitrary memory).
PL_FD = []
PL_ADDR = []
PL_SIZE = []
PL_LIVE = []
PL_DEAD = []
PL_CI = []

function wl_pool_new(ci, handle, address, size):
    call PL_FD.append(Int(handle))
    call PL_ADDR.append(Int(address))
    call PL_SIZE.append(Int(size))
    call PL_LIVE.append(0)
    call PL_DEAD.append(0)
    call PL_CI.append(Int(ci))
    return len(PL_FD) - 1
end

# A client is gone (EOF, send error, flooded buffer): release everything it
# pinned — the socket, queued descriptors, every mapped pool — and tell the
# host once. Object tables are only truly freed when the slot is reused,
# which is fine: they are plain arrays.
function wl_client_drop(index):
    ci = Int(index)
    if Int(CL_ALIVE[ci]) == 0:
        return None
    end
    CL_ALIVE[ci] = 0
    call unixsock.close_fd(Int(CL_FD[ci]))
    fds = CL_FDS[ci]
    while len(fds) > 0:
        call unixsock.close_fd(Int(fds[0]))
        call fds.pop(0)
    end
    h = 0
    while h < len(PL_CI):
        if Int(PL_CI[h]) == ci and Int(PL_ADDR[h]) > 0:
            call REAP_ADDR.append(Int(PL_ADDR[h]))
            call REAP_SIZE.append(Int(PL_SIZE[h]))
            call REAP_FD.append(Int(PL_FD[h]))
            PL_ADDR[h] = 0
        end
        h = h + 1
    end
    while len(CL_FDPOS[ci]) > 0:
        if Int(CL_FDKEEP[ci][0]) == 0:
            call unixsock.close_fd(Int(CL_FDVAL[ci][0]))
        end
        call CL_FDPOS[ci].pop(0)
        call CL_FDVAL[ci].pop(0)
        call CL_FDKEEP[ci].pop(0)
    end
    CL_OUT[ci] = ByteArray()
    CL_OUTOFF[ci] = 0
    CL_INBUF[ci] = ByteArray()
    if Int(PF_CI[0]) == ci:
        PF_CI[0] = 0 - 1
        PF_SID[0] = 0 - 1
    end
    if Int(KF_CI[0]) == ci:
        KF_CI[0] = 0 - 1
        KF_SID[0] = 0 - 1
    end
    if Int(GRAB_CI[0]) == ci:
        GRAB_CI[0] = 0 - 1
        GRAB_SID[0] = 0 - 1
    end
    CL_DDEV[ci] = 0
    if Int(SEL_OWNER[0]) == ci:
        # Its selection dies with it; the text we already mirrored stays.
        SEL_OWNER[0] = 0 - 1
        SEL_SRC[0] = 0
    end
    di = 0
    while di < len(DS_CI):
        if Int(DS_CI[di]) == ci:
            call DS_CI.pop(di)
            call DS_ID.pop(di)
            call DS_MIME.pop(di)
        else:
            di = di + 1
        end
    end
    call wl_emit(4, ci, 0, 0, 0, 0, 0, "")
    call wl_log("client " + String(ci) + " dropped")
    return None
end

# Pools never unmap inline: a commit event queued this tick may still point
# into the mapping, and the compositor only copies when it drains the queue.
# Candidates land here and wl_reap() (end of wl_frame_done, after the copy)
# does the actual munmap.
REAP_ADDR = []
REAP_SIZE = []
REAP_FD = []

function wl_pool_gc(handle):
    h = Int(handle)
    if h < 0 or h >= len(PL_FD):
        return None
    end
    if Int(PL_DEAD[h]) == 1 and Int(PL_LIVE[h]) <= 0 and Int(PL_ADDR[h]) > 0:
        call REAP_ADDR.append(Int(PL_ADDR[h]))
        call REAP_SIZE.append(Int(PL_SIZE[h]))
        call REAP_FD.append(Int(PL_FD[h]))
        PL_ADDR[h] = 0
    end
    return None
end

function wl_reap():
    while len(REAP_ADDR) > 0:
        call unixsock.munmap(Int(REAP_ADDR[0]), Int(REAP_SIZE[0]))
        if Int(REAP_FD[0]) >= 0:
            call unixsock.close_fd(Int(REAP_FD[0]))
        end
        call REAP_ADDR.pop(0)
        call REAP_SIZE.pop(0)
        call REAP_FD.pop(0)
    end
    return None
end

function wl_next_serial():
    WL_SERIAL[0] = Int(WL_SERIAL[0]) + 1
    return Int(WL_SERIAL[0])
end

# The host (a compositor) drains this queue once per frame instead of
# registering callbacks: kind 1 = map a new toplevel (client, surface),
# 2 = a surface committed new pixels (window, address, w, h, stride,
# format), 3 = title changed (window, WL_EVT text), 4 = client gone,
# 5 = map a popup (client, surface, parent window, x+32768, y+32768,
# w*65536+h), 6 = unmap a popup window, 7 = client asks to move (window),
# 8 = client asks to resize (window, edges), 9 = minimize (window),
# 12 = subsurface pixels (parent window, address, w, h, stride,
# x*65536+y).
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
    # Empty the queues IN PLACE. Rebinding the globals (`WL_EV_KIND = []`)
    # does not reach the host module — it kept draining the old, stale
    # list every frame, remapping windows and dereferencing long-reaped
    # buffer addresses.
    while len(WL_EV_KIND) > 0:
        call WL_EV_KIND.pop(len(WL_EV_KIND) - 1)
    end
    while len(WL_EV_A) > 0:
        call WL_EV_A.pop(len(WL_EV_A) - 1)
    end
    while len(WL_EV_B) > 0:
        call WL_EV_B.pop(len(WL_EV_B) - 1)
    end
    while len(WL_EV_C) > 0:
        call WL_EV_C.pop(len(WL_EV_C) - 1)
    end
    while len(WL_EV_D) > 0:
        call WL_EV_D.pop(len(WL_EV_D) - 1)
    end
    while len(WL_EV_E) > 0:
        call WL_EV_E.pop(len(WL_EV_E) - 1)
    end
    while len(WL_EV_F) > 0:
        call WL_EV_F.pop(len(WL_EV_F) - 1)
    end
    while len(WL_EVT) > 0:
        call WL_EVT.pop(len(WL_EVT) - 1)
    end
    return None
end

# The host force-closed a client window: detach the surface so any further
# commits stop targeting the (soon reused) window id.
function wl_unbind_window(client_index, surface_id):
    ci = Int(client_index)
    sid = Int(surface_id)
    if ci >= 0 and ci < len(CL_FD) and sid > 0 and sid < MAX_OBJECTS:
        IntArray(CL_A[ci])[sid] = 0 - 1
    end
    return None
end

# The host calls this once it has created a window for a mapped surface.
# If the surface already committed pixels while unbound (toolkits attach
# in the same burst as get_toplevel), replay that commit right away — the
# host drains events with a live len() check, so the appended event is
# still handled in the same pass.
function wl_bind_window(client_index, surface_id, window_id):
    ci = Int(client_index)
    sid = Int(surface_id)
    IntArray(CL_A[ci])[sid] = Int(window_id)
    buf = Int(IntArray(CL_C[ci])[sid])
    if buf > 0 and cl_kind(ci, buf) == WO_BUFFER:
        pool = Int(IntArray(CL_A[ci])[buf])
        base = 0
        if pool >= 0 and pool < len(PL_ADDR):
            base = Int(PL_ADDR[pool])
        end
        offset = Int(IntArray(CL_B[ci])[buf])
        if base > 0:
            call wl_emit(2, Int(window_id), base + offset, Int(IntArray(CL_C[ci])[buf]), Int(IntArray(CL_D[ci])[buf]), Int(IntArray(CL_E[ci])[buf]), Int(IntArray(CL_F[ci])[buf]), "")
        end
    end
    return None
end

# Window geometry + accumulated damage of a surface, for the host's copy:
# [geo_x, geo_y, geo_w, geo_h, dmg_x0, dmg_y0, dmg_x1, dmg_y1]. Geometry
# falls back to the full buffer when the client never set one; the damage
# union is cleared by this read.
function wl_surface_geo(client_index, surface_id, bw, bh):
    ci = Int(client_index)
    sid = Int(surface_id)
    gx = 0
    gy = 0
    gw = Int(bw)
    gh = Int(bh)
    xs = Int(IntArray(CL_E[ci])[sid])
    if xs > 0 and cl_kind(ci, xs) == WO_XDG_SURFACE:
        if Int(IntArray(CL_E[ci])[xs]) > 0 and Int(IntArray(CL_F[ci])[xs]) > 0:
            gx = Int(IntArray(CL_C[ci])[xs])
            gy = Int(IntArray(CL_D[ci])[xs])
            gw = Int(IntArray(CL_E[ci])[xs])
            gh = Int(IntArray(CL_F[ci])[xs])
        end
    end
    dx0 = Int(IntArray(CL_D0[ci])[sid])
    dy0 = Int(IntArray(CL_D1[ci])[sid])
    dx1 = Int(IntArray(CL_D2[ci])[sid])
    dy1 = Int(IntArray(CL_D3[ci])[sid])
    IntArray(CL_D0[ci])[sid] = 0
    IntArray(CL_D1[ci])[sid] = 0
    IntArray(CL_D2[ci])[sid] = 0
    IntArray(CL_D3[ci])[sid] = 0
    if dx1 <= dx0 or dy1 <= dy0:
        dx0 = 0
        dy0 = 0
        dx1 = Int(bw)
        dy1 = Int(bh)
    end
    return [gx, gy, gw, gh, dx0, dy0, dx1, dy1]
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
    live = 0
    i = 0
    while i < len(CL_FD):
        if Int(CL_ALIVE[i]) == 1:
            live = live + 1
        end
        i = i + 1
    end
    if live >= MAX_CLIENTS:
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
# The xkb keymap every wl_keyboard gets. The desktop loads the file for the
# active layout into a memfd; SCM_RIGHTS hands the same descriptor to every
# client, which maps it read-only.
WL_KM_FD = [0 - 1]
WL_KM_SIZE = [0]

function wl_set_keymap(path):
    data = ByteArray()
    safe:
        h = fd.open(String(path), fd.read_only)
        if h >= 0:
            chunk = __lsl_byte_zeros(8192)
            cb = ByteArray(chunk)
            more = 1
            while more == 1:
                got = fd.read(h, cb, 8192)
                if got <= 0:
                    more = 0
                else:
                    i = 0
                    while i < got:
                        call data.append(cb[i])
                        i = i + 1
                    end
                end
            end
            call fd.close(h)
        end
    end
    if len(data) == 0:
        return 0 - 1
    end
    call data.append(0)
    m = unixsock.memfd("luxos-keymap", len(data))
    if m < 0:
        return m
    end
    # fd.write raises on failure and returns nothing, so a short write is
    # not something to test for here.
    ok = 1
    safe:
        call fd.write(m, data, len(data))
        ok = 2
    end
    if ok != 2:
        call unixsock.close_fd(m)
        call wl_log("keymap write failed for " + String(path))
        return 0 - 1
    end
    old = Int(WL_KM_FD[0])
    WL_KM_FD[0] = m
    WL_KM_SIZE[0] = len(data)
    if old >= 0:
        call unixsock.close_fd(old)
    end
    # A layout switch reaches every connected keyboard immediately.
    i = 0
    while i < len(CL_FD):
        if Int(CL_ALIVE[i]) == 1:
            kl = CL_KBDL[i]
            ki = 0
            while ki < len(kl):
                call wl_send_keymap(i, Int(kl[ki]))
                ki = ki + 1
            end
        end
        i = i + 1
    end
    return 0
end

# keymap(format=1 xkb_v1, fd, size), queued in stream order like any other
# event; the flush attaches the descriptor to this message alone.
function wl_send_keymap(index, kbd):
    ci = Int(index)
    if Int(WL_KM_FD[0]) < 0:
        return None
    end
    args = ByteArray()
    call w_append32(args, 1)
    call w_append32(args, Int(WL_KM_SIZE[0]))
    call cl_post_fd(ci, Int(kbd), 0, args, Int(WL_KM_FD[0]), 1)
    # repeat_info(rate chars/s, delay ms) — v4+ keyboards.
    if Int(CL_SEATV[ci]) >= 4:
        ri = ByteArray()
        call w_append32(ri, 30)
        call w_append32(ri, 400)
        call cl_post(ci, Int(kbd), 5, ri)
    end
    return None
end

# ---------------------------------------------------------------------------
# Input state the compositor feeds in. Modifier masks match the shipped
# xkb keymaps: Shift 1, Lock 2, Control 4, Mod1/Alt 8, Mod2/Num 16,
# Mod4/Super 64, Mod5/AltGr 128. Num Lock starts on (init sets the LED).
WL_DEPRESSED = [0]
WL_LOCKED = [16]
PF_CI = [0 - 1]
PF_SID = [0 - 1]
KF_CI = [0 - 1]
KF_SID = [0 - 1]
GRAB_CI = [0 - 1]
GRAB_SID = [0 - 1]

function wl_mod_bit(code):
    c = Int(code)
    if c == 42 or c == 54:
        return 1
    end
    if c == 29 or c == 97:
        return 4
    end
    if c == 56:
        return 8
    end
    if c == 100:
        return 128
    end
    if c == 125 or c == 126:
        return 64
    end
    return 0
end

function wl_post_modifiers(ci):
    # Serial + payload rebuilt per keyboard: toolkits (Firefox) bind the
    # seat more than once and every instance must hear the same state.
    kl = CL_KBDL[Int(ci)]
    ki = 0
    while ki < len(kl):
        args = ByteArray()
        call w_append32(args, wl_next_serial())
        call w_append32(args, Int(WL_DEPRESSED[0]))
        call w_append32(args, 0)
        call w_append32(args, Int(WL_LOCKED[0]))
        call w_append32(args, 0)
        call cl_post(Int(ci), Int(kl[ki]), 4, args)
        ki = ki + 1
    end
    return None
end

# One key from the compositor's evdev stream (state 1 press, 0 release).
# Lands on the current keyboard focus; modifiers ride along when they
# change. Repeats are the client's job (repeat_info).
function wl_key(code, state, now_ms):
    c = Int(code)
    st = Int(state)
    bit = Int(wl_mod_bit(c))
    changed = 0
    if bit != 0:
        old = Int(WL_DEPRESSED[0])
        if st == 1:
            WL_DEPRESSED[0] = old + bit - (old % (bit * 2) // bit) * bit
        else:
            had = old % (bit * 2) // bit
            if had == 1:
                WL_DEPRESSED[0] = old - bit
            end
        end
        if Int(WL_DEPRESSED[0]) != old:
            changed = 1
        end
    end
    if st == 1 and c == 58:
        lk = Int(WL_LOCKED[0])
        if lk % 4 // 2 == 1:
            WL_LOCKED[0] = lk - 2
        else:
            WL_LOCKED[0] = lk + 2
        end
        changed = 1
    end
    if st == 1 and c == 69:
        lk = Int(WL_LOCKED[0])
        if lk % 32 // 16 == 1:
            WL_LOCKED[0] = lk - 16
        else:
            WL_LOCKED[0] = lk + 16
        end
        changed = 1
    end
    ci = Int(KF_CI[0])
    if ci < 0 or ci >= len(CL_FD):
        return None
    end
    if Int(CL_ALIVE[ci]) == 0 or len(CL_KBDL[ci]) == 0:
        return None
    end
    kl = CL_KBDL[ci]
    ki = 0
    while ki < len(kl):
        args = ByteArray()
        call w_append32(args, wl_next_serial())
        call w_append32(args, Int(now_ms))
        call w_append32(args, c)
        call w_append32(args, st)
        call cl_post(ci, Int(kl[ki]), 3, args)
        ki = ki + 1
    end
    if changed == 1:
        call wl_post_modifiers(ci)
    end
    return None
end

function wl_kbd_enter(client_index, surface_id):
    ci = Int(client_index)
    sid = Int(surface_id)
    if Int(KF_CI[0]) == ci and Int(KF_SID[0]) == sid:
        return None
    end
    call wl_kbd_leave()
    if ci < 0 or ci >= len(CL_FD):
        return None
    end
    if Int(CL_ALIVE[ci]) == 0 or len(CL_KBDL[ci]) == 0:
        return None
    end
    KF_CI[0] = ci
    KF_SID[0] = sid
    kl = CL_KBDL[ci]
    ki = 0
    while ki < len(kl):
        args = ByteArray()
        call w_append32(args, wl_next_serial())
        call w_append32(args, sid)
        call w_append32(args, 0)
        call cl_post(ci, Int(kl[ki]), 1, args)
        ki = ki + 1
    end
    call wl_post_modifiers(ci)
    return None
end

function wl_kbd_leave():
    ci = Int(KF_CI[0])
    sid = Int(KF_SID[0])
    KF_CI[0] = 0 - 1
    KF_SID[0] = 0 - 1
    if ci < 0 or ci >= len(CL_FD):
        return None
    end
    if Int(CL_ALIVE[ci]) == 0 or len(CL_KBDL[ci]) == 0:
        return None
    end
    kl = CL_KBDL[ci]
    ki = 0
    while ki < len(kl):
        args = ByteArray()
        call w_append32(args, wl_next_serial())
        call w_append32(args, sid)
        call cl_post(ci, Int(kl[ki]), 2, args)
        ki = ki + 1
    end
    return None
end

# Pointer events, all in surface-local coordinates (fixed point 24.8).
function wl_ptr_frame(ci):
    if Int(CL_SEATV[Int(ci)]) < 5:
        return None
    end
    pl = CL_PTRL[Int(ci)]
    pi = 0
    while pi < len(pl):
        call cl_post(Int(ci), Int(pl[pi]), 5, ByteArray())
        pi = pi + 1
    end
    return None
end

function wl_pointer_enter(client_index, surface_id, sx, sy):
    ci = Int(client_index)
    sid = Int(surface_id)
    if Int(PF_CI[0]) == ci and Int(PF_SID[0]) == sid:
        return None
    end
    call wl_pointer_leave()
    if ci < 0 or ci >= len(CL_FD):
        return None
    end
    if Int(CL_ALIVE[ci]) == 0 or len(CL_PTRL[ci]) == 0:
        return None
    end
    PF_CI[0] = ci
    PF_SID[0] = sid
    pl = CL_PTRL[ci]
    pi = 0
    while pi < len(pl):
        args = ByteArray()
        call w_append32(args, wl_next_serial())
        call w_append32(args, sid)
        call w_append32(args, Int(sx) * 256)
        call w_append32(args, Int(sy) * 256)
        call cl_post(ci, Int(pl[pi]), 0, args)
        pi = pi + 1
    end
    call wl_ptr_frame(ci)
    return None
end

function wl_pointer_leave():
    ci = Int(PF_CI[0])
    sid = Int(PF_SID[0])
    PF_CI[0] = 0 - 1
    PF_SID[0] = 0 - 1
    if ci < 0 or ci >= len(CL_FD):
        return None
    end
    if Int(CL_ALIVE[ci]) == 0 or len(CL_PTRL[ci]) == 0:
        return None
    end
    pl = CL_PTRL[ci]
    pi = 0
    while pi < len(pl):
        args = ByteArray()
        call w_append32(args, wl_next_serial())
        call w_append32(args, sid)
        call cl_post(ci, Int(pl[pi]), 1, args)
        pi = pi + 1
    end
    call wl_ptr_frame(ci)
    return None
end

function wl_pointer_motion(sx, sy, now_ms):
    ci = Int(PF_CI[0])
    if ci < 0 or Int(CL_ALIVE[ci]) == 0 or len(CL_PTRL[ci]) == 0:
        return None
    end
    pl = CL_PTRL[ci]
    pi = 0
    while pi < len(pl):
        args = ByteArray()
        call w_append32(args, Int(now_ms))
        call w_append32(args, Int(sx) * 256)
        call w_append32(args, Int(sy) * 256)
        call cl_post(ci, Int(pl[pi]), 2, args)
        pi = pi + 1
    end
    call wl_ptr_frame(ci)
    return None
end

# button: BTN_LEFT 272, BTN_RIGHT 273, BTN_MIDDLE 274; state 1 press.
function wl_pointer_button(button, state, now_ms):
    ci = Int(PF_CI[0])
    if ci < 0 or Int(CL_ALIVE[ci]) == 0 or len(CL_PTRL[ci]) == 0:
        return None
    end
    pl = CL_PTRL[ci]
    pi = 0
    while pi < len(pl):
        args = ByteArray()
        call w_append32(args, wl_next_serial())
        call w_append32(args, Int(now_ms))
        call w_append32(args, Int(button))
        call w_append32(args, Int(state))
        call cl_post(ci, Int(pl[pi]), 3, args)
        pi = pi + 1
    end
    call wl_ptr_frame(ci)
    return None
end

# Vertical wheel: steps > 0 scroll down. v5 clients also get the discrete
# count, which is what toolkits turn into list rows.
function wl_pointer_axis(steps, now_ms):
    ci = Int(PF_CI[0])
    if ci < 0 or Int(CL_ALIVE[ci]) == 0 or len(CL_PTRL[ci]) == 0:
        return None
    end
    n = Int(steps)
    if n == 0:
        return None
    end
    pl = CL_PTRL[ci]
    pi = 0
    while pi < len(pl):
        ptr = Int(pl[pi])
        if Int(CL_SEATV[ci]) >= 5:
            asrc = ByteArray()
            call w_append32(asrc, 0)
            call cl_post(ci, ptr, 6, asrc)
            dis = ByteArray()
            call w_append32(dis, 0)
            call w_append32(dis, n)
            call cl_post(ci, ptr, 8, dis)
        end
        args = ByteArray()
        call w_append32(args, Int(now_ms))
        call w_append32(args, 0)
        call w_append32(args, n * 10 * 256)
        call cl_post(ci, ptr, 4, args)
        pi = pi + 1
    end
    call wl_ptr_frame(ci)
    return None
end

# The desktop dismisses an open popup grab (click elsewhere, Esc).
function wl_popup_dismiss(client_index, surface_id):
    ci = Int(client_index)
    sid = Int(surface_id)
    if ci < 0 or ci >= len(CL_FD):
        return None
    end
    xs = Int(IntArray(CL_E[ci])[sid])
    pop = 0
    if xs > 0:
        pop = Int(IntArray(CL_B[ci])[xs])
    end
    if pop > 0 and cl_kind(ci, pop) == WO_XDG_POPUP:
        call cl_post(ci, pop, 1, ByteArray())
    end
    if Int(GRAB_CI[0]) == ci and Int(GRAB_SID[0]) == sid:
        GRAB_CI[0] = 0 - 1
        GRAB_SID[0] = 0 - 1
    end
    return None
end

# xdg_toplevel.close — the polite "the user clicked X".
function wl_send_close(client_index, surface_id):
    ci = Int(client_index)
    sid = Int(surface_id)
    if ci < 0 or ci >= len(CL_FD):
        return None
    end
    xs = Int(IntArray(CL_E[ci])[sid])
    top = 0
    if xs > 0:
        top = Int(IntArray(CL_B[ci])[xs])
    end
    if top > 0 and cl_kind(ci, top) == WO_XDG_TOPLEVEL:
        call cl_post(ci, top, 1, ByteArray())
    end
    return None
end

# The desktop resized a client window: configure the toplevel with the new
# content size; the client acks and commits a matching buffer.
function wl_configure_window(client_index, surface_id, width, height):
    ci = Int(client_index)
    sid = Int(surface_id)
    if ci < 0 or ci >= len(CL_FD):
        return None
    end
    if Int(CL_ALIVE[ci]) == 0:
        return None
    end
    xs = Int(IntArray(CL_E[ci])[sid])
    top = 0
    if xs > 0:
        top = Int(IntArray(CL_B[ci])[xs])
    end
    if top > 0 and cl_kind(ci, top) == WO_XDG_TOPLEVEL:
        call wl_configure_toplevel(ci, top, Int(width), Int(height))
    end
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
        call w_append32(args, wl_next_serial())
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
    version = Int(w_get32(body, after))
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
        if version < 5:
            CL_SEATV[ci] = version
        else:
            CL_SEATV[ci] = 5
        end
        caps = ByteArray()
        call w_append32(caps, 3)
        call cl_post(ci, newid, 0, caps)
        if Int(CL_SEATV[ci]) >= 2:
            nm = ByteArray()
            call w_append_string(nm, "luxos-seat0")
            call cl_post(ci, newid, 1, nm)
        end
    elif iface == "wl_output":
        call cl_set_kind(ci, newid, WO_OUTPUT)
        CL_OUTID[ci] = newid
        call wl_send_output(cli, newid)
    elif iface == "wl_subcompositor":
        call cl_set_kind(ci, newid, WO_SUBCOMPOSITOR)
    elif iface == "wl_data_device_manager":
        call cl_set_kind(ci, newid, WO_DDM)
    end
    call wl_log("bind " + iface + " v" + String(version) + " -> " + String(newid))
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
        IntArray(CL_E[ci])[newid] = 0
        IntArray(CL_F[ci])[newid] = ROLE_NONE
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
    IntArray(CL_A[ci])[pool] = Int(wl_pool_new(ci, pfd, addr, size))
    call wl_log("pool " + String(pool) + " size " + String(size))
    return None
end

function wl_shm_pool_request(cli, oid, opcode, body):
    ci = Int(cli)
    h = Int(IntArray(CL_A[ci])[Int(oid)])
    if opcode == 0:
        # create_buffer(new_id, offset, width, height, stride, format)
        buf = Int(w_get32(body, 0))
        call cl_set_kind(ci, buf, WO_BUFFER)
        IntArray(CL_A[ci])[buf] = h
        IntArray(CL_B[ci])[buf] = Int(w_get32(body, 4))
        IntArray(CL_C[ci])[buf] = Int(w_get32(body, 8))
        IntArray(CL_D[ci])[buf] = Int(w_get32(body, 12))
        IntArray(CL_E[ci])[buf] = Int(w_get32(body, 16))
        IntArray(CL_F[ci])[buf] = Int(w_get32(body, 20))
        if h >= 0 and h < len(PL_LIVE):
            PL_LIVE[h] = Int(PL_LIVE[h]) + 1
        end
    elif opcode == 1:
        # destroy: the mapping stays until the last buffer in it goes.
        call wl_destroy_object(ci, Int(oid))
        if h >= 0 and h < len(PL_DEAD):
            PL_DEAD[h] = 1
            call wl_pool_gc(h)
        end
    elif opcode == 2:
        # resize(size): remap at the new length; the old mapping goes to
        # the reaper in case a queued commit still reads from it.
        size = Int(w_get32(body, 0))
        if h >= 0 and h < len(PL_FD):
            addr = fd.mmap(Int(PL_FD[h]), size, 0)
            if addr >= 0:
                oldaddr = Int(PL_ADDR[h])
                oldsize = Int(PL_SIZE[h])
                PL_ADDR[h] = addr
                PL_SIZE[h] = size
                if oldaddr > 0 and oldaddr != addr:
                    call REAP_ADDR.append(oldaddr)
                    call REAP_SIZE.append(oldsize)
                    call REAP_FD.append(0 - 1)
                end
            end
        end
    end
    return None
end

function wl_buffer_request(cli, oid, opcode, body):
    ci = Int(cli)
    if opcode == 0:
        h = Int(IntArray(CL_A[ci])[Int(oid)])
        call wl_destroy_object(ci, Int(oid))
        if h >= 0 and h < len(PL_LIVE):
            PL_LIVE[h] = Int(PL_LIVE[h]) - 1
            call wl_pool_gc(h)
        end
    end
    return None
end

# Fold client damage into the per-surface union (surface coords ~ buffer
# coords at scale 1; both damage and damage_buffer land here).
function wl_surface_damage_add(ci, sid, x, y, w, h):
    c = Int(ci)
    s = Int(sid)
    x0 = Int(x)
    y0 = Int(y)
    if x0 < 0:
        x0 = 0
    end
    if y0 < 0:
        y0 = 0
    end
    x1 = Int(x) + Int(w)
    y1 = Int(y) + Int(h)
    if Int(IntArray(CL_D2[c])[s]) <= Int(IntArray(CL_D0[c])[s]):
        IntArray(CL_D0[c])[s] = x0
        IntArray(CL_D1[c])[s] = y0
        IntArray(CL_D2[c])[s] = x1
        IntArray(CL_D3[c])[s] = y1
    else:
        if x0 < Int(IntArray(CL_D0[c])[s]):
            IntArray(CL_D0[c])[s] = x0
        end
        if y0 < Int(IntArray(CL_D1[c])[s]):
            IntArray(CL_D1[c])[s] = y0
        end
        if x1 > Int(IntArray(CL_D2[c])[s]):
            IntArray(CL_D2[c])[s] = x1
        end
        if y1 > Int(IntArray(CL_D3[c])[s]):
            IntArray(CL_D3[c])[s] = y1
        end
    end
    return None
end

function wl_surface_request(cli, oid, opcode, body):
    ci = Int(cli)
    sid = Int(oid)
    if opcode == 0:
        # destroy
        if Int(IntArray(CL_F[ci])[sid]) == ROLE_POPUP:
            win = Int(IntArray(CL_A[ci])[sid])
            if win >= 0:
                call wl_emit(6, win, 0, 0, 0, 0, 0, "")
            end
        end
        call wl_destroy_object(ci, sid)
    elif opcode == 1:
        # attach(buffer, x, y): pending state, applied on commit.
        b = Int(w_get32(body, 0))
        if b == 0:
            IntArray(CL_B[ci])[sid] = 0 - 1
        else:
            IntArray(CL_B[ci])[sid] = b
        end
    elif opcode == 2:
        call wl_surface_damage_add(ci, sid, w_get_int(body, 0), w_get_int(body, 4), w_get_int(body, 8), w_get_int(body, 12))
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
    elif opcode == 9:
        call wl_surface_damage_add(ci, sid, w_get_int(body, 0), w_get_int(body, 4), w_get_int(body, 8), w_get_int(body, 12))
    end
    # set_opaque_region(4), set_input_region(5), transform(7), scale(8),
    # offset(10): accepted and irrelevant at scale 1.
    return None
end

function wl_surface_commit(cli, sid):
    ci = Int(cli)
    buf = Int(IntArray(CL_B[ci])[sid])
    role = Int(IntArray(CL_F[ci])[sid])
    if buf == 0 - 1:
        # Explicit null attach: the surface goes away from the screen. The
        # window closes too — toolkits hide-and-remap through this.
        IntArray(CL_B[ci])[sid] = 0
        IntArray(CL_C[ci])[sid] = 0
        win0 = Int(IntArray(CL_A[ci])[sid])
        call wl_log("null attach sid=" + String(sid) + " win=" + String(win0))
        if win0 >= 0:
            IntArray(CL_A[ci])[sid] = 0 - 1
            call wl_emit(6, win0, 0, 0, 0, 0, 0, "")
        end
        return None
    end
    if buf == 0:
        # State-only commit (initial xdg commit, damage bookkeeping).
        return None
    end
    if cl_kind(ci, buf) != WO_BUFFER:
        return None
    end
    IntArray(CL_B[ci])[sid] = 0
    IntArray(CL_C[ci])[sid] = buf
    pool = Int(IntArray(CL_A[ci])[buf])
    base = 0
    if pool >= 0 and pool < len(PL_ADDR):
        base = Int(PL_ADDR[pool])
    end
    if base <= 0:
        call cl_post(ci, buf, 0, ByteArray())
        return None
    end
    offset = Int(IntArray(CL_B[ci])[buf])
    width = Int(IntArray(CL_C[ci])[buf])
    height = Int(IntArray(CL_D[ci])[buf])
    stride = Int(IntArray(CL_E[ci])[buf])
    format = Int(IntArray(CL_F[ci])[buf])
    if role == ROLE_CURSOR:
        call cl_post(ci, buf, 0, ByteArray())
        return None
    end
    if role == ROLE_SUBSURFACE:
        parent = Int(IntArray(CL_H[ci])[sid])
        win = 0 - 1
        if parent > 0:
            win = Int(IntArray(CL_A[ci])[parent])
        end
        if win >= 0:
            call wl_emit(12, win, base + offset, width, height, stride, Int(IntArray(CL_G[ci])[sid]), "")
        end
        call cl_post(ci, buf, 0, ByteArray())
        return None
    end
    win = Int(IntArray(CL_A[ci])[sid])
    if win >= 0:
        call wl_emit(2, win, base + offset, width, height, stride, format, "")
    end
    # release(buffer): the client may reuse it now that we have taken the
    # pixels. It only learns of this after the frame's flush, which is
    # always after the compositor copied them.
    call cl_post(ci, buf, 0, ByteArray())
    return None
end

function wl_xdg_wm_base_request(cli, oid, opcode, body):
    ci = Int(cli)
    if opcode == 0:
        call wl_destroy_object(ci, Int(oid))
    elif opcode == 1:
        # create_positioner(new_id)
        pos = Int(w_get32(body, 0))
        call cl_set_kind(ci, pos, WO_POSITIONER)
        IntArray(CL_A[ci])[pos] = 0
        IntArray(CL_B[ci])[pos] = 0
        IntArray(CL_C[ci])[pos] = 0
        IntArray(CL_D[ci])[pos] = 0
        IntArray(CL_E[ci])[pos] = 0
        IntArray(CL_F[ci])[pos] = 0
        IntArray(CL_G[ci])[pos] = 0
        IntArray(CL_H[ci])[pos] = 32768 * 65536 + 32768
    elif opcode == 2:
        # get_xdg_surface(new_id, surface)
        xs = Int(w_get32(body, 0))
        surf = Int(w_get32(body, 4))
        call cl_set_kind(ci, xs, WO_XDG_SURFACE)
        IntArray(CL_A[ci])[xs] = surf
        IntArray(CL_B[ci])[xs] = 0
        IntArray(CL_C[ci])[xs] = 0
        IntArray(CL_D[ci])[xs] = 0
        IntArray(CL_E[ci])[xs] = 0
        IntArray(CL_F[ci])[xs] = 0
        IntArray(CL_E[ci])[surf] = xs
    end
    # pong(3): accepted.
    return None
end

function wl_positioner_request(cli, oid, opcode, body):
    ci = Int(cli)
    pos = Int(oid)
    if opcode == 0:
        call wl_destroy_object(ci, pos)
    elif opcode == 1:
        IntArray(CL_A[ci])[pos] = Int(w_get_int(body, 0))
        IntArray(CL_B[ci])[pos] = Int(w_get_int(body, 4))
    elif opcode == 2:
        IntArray(CL_C[ci])[pos] = Int(w_get_int(body, 0))
        IntArray(CL_D[ci])[pos] = Int(w_get_int(body, 4))
        IntArray(CL_E[ci])[pos] = Int(w_get_int(body, 8))
        IntArray(CL_F[ci])[pos] = Int(w_get_int(body, 12))
    elif opcode == 3:
        anchor = Int(w_get32(body, 0))
        IntArray(CL_G[ci])[pos] = anchor * 16 + Int(IntArray(CL_G[ci])[pos]) % 16
    elif opcode == 4:
        gravity = Int(w_get32(body, 0))
        IntArray(CL_G[ci])[pos] = Int(IntArray(CL_G[ci])[pos]) // 16 * 16 + gravity
    elif opcode == 6:
        ox = Int(w_get_int(body, 0))
        oy = Int(w_get_int(body, 4))
        IntArray(CL_H[ci])[pos] = (ox + 32768) * 65536 + (oy + 32768)
    end
    # set_constraint_adjustment(5), reactive(7)...: accepted.
    return None
end

# Where a popup lands relative to the parent's window geometry: pick the
# anchor point on the anchor rect, then let gravity decide which corner of
# the popup touches it.
function wl_popup_place(ci, pos):
    c = Int(ci)
    p = Int(pos)
    pw = Int(IntArray(CL_A[c])[p])
    ph = Int(IntArray(CL_B[c])[p])
    ax = Int(IntArray(CL_C[c])[p])
    ay = Int(IntArray(CL_D[c])[p])
    aw = Int(IntArray(CL_E[c])[p])
    ah = Int(IntArray(CL_F[c])[p])
    ag = Int(IntArray(CL_G[c])[p])
    anchor = ag // 16
    gravity = ag % 16
    off = Int(IntArray(CL_H[c])[p])
    ox = off // 65536 - 32768
    oy = off % 65536 - 32768
    # Anchor: 0 none/center, 1 top, 2 bottom, 3 left, 4 right, 5 top-left,
    # 6 bottom-left, 7 top-right, 8 bottom-right.
    px = ax + aw // 2
    py = ay + ah // 2
    if anchor == 1 or anchor == 5 or anchor == 7:
        py = ay
    end
    if anchor == 2 or anchor == 6 or anchor == 8:
        py = ay + ah
    end
    if anchor == 3 or anchor == 5 or anchor == 6:
        px = ax
    end
    if anchor == 4 or anchor == 7 or anchor == 8:
        px = ax + aw
    end
    # Gravity mirrors the same numbering: which way the popup extends.
    rx = px - pw // 2
    ry = py - ph // 2
    if gravity == 1 or gravity == 5 or gravity == 7:
        ry = py - ph
    end
    if gravity == 2 or gravity == 6 or gravity == 8:
        ry = py
    end
    if gravity == 3 or gravity == 5 or gravity == 6:
        rx = px - pw
    end
    if gravity == 4 or gravity == 7 or gravity == 8:
        rx = px
    end
    return [rx + ox, ry + oy, pw, ph]
end

function wl_xdg_surface_request(cli, oid, opcode, body):
    ci = Int(cli)
    xs = Int(oid)
    if opcode == 0:
        call wl_destroy_object(ci, xs)
    elif opcode == 1:
        # get_toplevel(new_id): a real window. Configure it right away with
        # our size, then xdg_surface.configure so the client can commit.
        top = Int(w_get32(body, 0))
        call cl_set_kind(ci, top, WO_XDG_TOPLEVEL)
        IntArray(CL_A[ci])[top] = xs
        IntArray(CL_B[ci])[xs] = top
        surf = Int(IntArray(CL_A[ci])[xs])
        IntArray(CL_A[ci])[surf] = 0 - 1
        IntArray(CL_F[ci])[surf] = ROLE_TOPLEVEL
        call wl_log("get_toplevel xs=" + String(xs) + " top=" + String(top) + " surf=" + String(surf))
        call wl_emit(1, ci, surf, 0, 0, 0, 0, "")
        # Suggest a size that fits the desktop with room for the frame —
        # size 0 ("you pick") makes browsers open output-sized windows
        # that overflow the cascade position.
        cw = Int(WL_OUT_W[0]) * 3 // 4
        ch = Int(WL_OUT_H[0]) * 3 // 4
        if cw > 1400:
            cw = 1400
        end
        if ch > 900:
            ch = 900
        end
        call wl_configure_toplevel(cli, top, cw, ch)
    elif opcode == 2:
        # get_popup(new_id, parent xdg_surface, positioner)
        pop = Int(w_get32(body, 0))
        parent = Int(w_get32(body, 4))
        pos = Int(w_get32(body, 8))
        call cl_set_kind(ci, pop, WO_XDG_POPUP)
        IntArray(CL_A[ci])[pop] = xs
        IntArray(CL_B[ci])[pop] = parent
        IntArray(CL_B[ci])[xs] = pop
        surf = Int(IntArray(CL_A[ci])[xs])
        IntArray(CL_A[ci])[surf] = 0 - 1
        IntArray(CL_F[ci])[surf] = ROLE_POPUP
        place = wl_popup_place(ci, pos)
        px = Int(place[0])
        py = Int(place[1])
        pw = Int(place[2])
        ph = Int(place[3])
        if pw < 1:
            pw = 1
        end
        if ph < 1:
            ph = 1
        end
        parentwin = 0 - 1
        if parent > 0 and cl_kind(ci, parent) == WO_XDG_SURFACE:
            psurf = Int(IntArray(CL_A[ci])[parent])
            parentwin = Int(IntArray(CL_A[ci])[psurf])
        end
        call wl_emit(5, ci, surf, parentwin, px + 32768, py + 32768, pw * 65536 + ph, "")
        # xdg_popup.configure(x, y, w, h) + xdg_surface.configure(serial).
        args = ByteArray()
        call w_append32(args, px)
        call w_append32(args, py)
        call w_append32(args, pw)
        call w_append32(args, ph)
        call cl_post(ci, pop, 0, args)
        ser = ByteArray()
        call w_append32(ser, wl_next_serial())
        call cl_post(ci, xs, 0, ser)
    elif opcode == 3:
        # set_window_geometry(x, y, w, h): the visible bounds inside the
        # buffer — everything outside is client-side shadow to crop away.
        IntArray(CL_C[ci])[xs] = Int(w_get_int(body, 0))
        IntArray(CL_D[ci])[xs] = Int(w_get_int(body, 4))
        IntArray(CL_E[ci])[xs] = Int(w_get_int(body, 8))
        IntArray(CL_F[ci])[xs] = Int(w_get_int(body, 12))
    end
    # ack_configure(4): nothing to roll back on our side.
    return None
end

# xdg_toplevel.configure(width, height, states) + xdg_surface.configure.
# states: 4 = activated, so clients paint themselves focused.
function wl_configure_toplevel(cli, top, width, height):
    ci = Int(cli)
    args = ByteArray()
    call w_append32(args, Int(width))
    call w_append32(args, Int(height))
    call w_append32(args, 4)
    call w_append32(args, 4)
    call cl_post(ci, top, 0, args)
    xs = Int(IntArray(CL_A[ci])[Int(top)])
    ser = ByteArray()
    call w_append32(ser, wl_next_serial())
    call cl_post(ci, xs, 0, ser)
    return None
end

function wl_xdg_toplevel_request(cli, oid, opcode, body):
    ci = Int(cli)
    top = Int(oid)
    xs = Int(IntArray(CL_A[ci])[top])
    surf = 0
    win = 0 - 1
    if xs > 0:
        surf = Int(IntArray(CL_A[ci])[xs])
        if surf > 0:
            win = Int(IntArray(CL_A[ci])[surf])
        end
    end
    if opcode == 0:
        call wl_log("toplevel destroy top=" + String(top) + " win=" + String(win))
        call wl_destroy_object(ci, top)
        if surf > 0:
            IntArray(CL_F[ci])[surf] = ROLE_NONE
            IntArray(CL_A[ci])[surf] = 0 - 1
        end
        if xs > 0:
            IntArray(CL_B[ci])[xs] = 0
        end
        if win >= 0:
            call wl_emit(6, win, 0, 0, 0, 0, 0, "")
        end
    elif opcode == 2:
        CL_TITLE[ci] = w_read_string(body, 0)
        if win >= 0:
            call wl_emit(3, win, 0, 0, 0, 0, 0, String(CL_TITLE[ci]))
        end
    elif opcode == 5:
        if win >= 0:
            call wl_emit(7, win, 0, 0, 0, 0, 0, "")
        end
    elif opcode == 6:
        edges = Int(w_get32(body, 4))
        if win >= 0:
            call wl_emit(8, win, edges, 0, 0, 0, 0, "")
        end
    elif opcode == 13:
        if win >= 0:
            call wl_emit(9, win, 0, 0, 0, 0, 0, "")
        end
    end
    # set_parent(1), app_id(3), show_window_menu(4), min/max size (7,8),
    # maximized/fullscreen (9..12): accepted; the desktop keeps its layout.
    return None
end

function wl_xdg_popup_request(cli, oid, opcode, body):
    ci = Int(cli)
    pop = Int(oid)
    if opcode == 0:
        xs = Int(IntArray(CL_A[ci])[pop])
        surf = 0
        win = 0 - 1
        if xs > 0:
            surf = Int(IntArray(CL_A[ci])[xs])
            if surf > 0:
                win = Int(IntArray(CL_A[ci])[surf])
            end
        end
        call wl_destroy_object(ci, pop)
        if win >= 0:
            call wl_emit(6, win, 0, 0, 0, 0, 0, "")
        end
        if Int(GRAB_CI[0]) == ci and Int(GRAB_SID[0]) == surf:
            GRAB_CI[0] = 0 - 1
            GRAB_SID[0] = 0 - 1
        end
    elif opcode == 1:
        # grab(seat, serial): dismiss on any click outside.
        xs = Int(IntArray(CL_A[ci])[pop])
        if xs > 0:
            GRAB_CI[0] = ci
            GRAB_SID[0] = Int(IntArray(CL_A[ci])[xs])
        end
    end
    return None
end

function wl_seat_request(cli, oid, opcode, body):
    ci = Int(cli)
    if opcode == 3:
        call wl_destroy_object(ci, Int(oid))
        return None
    end
    newid = Int(w_get32(body, 0))
    if opcode == 0:
        call cl_set_kind(ci, newid, WO_POINTER)
        call CL_PTRL[ci].append(newid)
    elif opcode == 1:
        call cl_set_kind(ci, newid, WO_KEYBOARD)
        call CL_KBDL[ci].append(newid)
        call wl_send_keymap(ci, newid)
    elif opcode == 2:
        call cl_set_kind(ci, newid, WO_TOUCH)
    end
    return None
end

function wl_pointer_request(cli, oid, opcode, body):
    ci = Int(cli)
    if opcode == 0:
        # set_cursor(serial, surface, hx, hy): the named surface becomes a
        # cursor image — it must never map as a window.
        surf = Int(w_get32(body, 4))
        if surf > 0 and cl_kind(ci, surf) == WO_SURFACE:
            IntArray(CL_F[ci])[surf] = ROLE_CURSOR
        end
    elif opcode == 1:
        call wl_destroy_object(ci, Int(oid))
        pl = CL_PTRL[ci]
        pi = 0
        while pi < len(pl):
            if Int(pl[pi]) == Int(oid):
                call pl.pop(pi)
            else:
                pi = pi + 1
            end
        end
    end
    return None
end

function wl_keyboard_request(cli, oid, opcode, body):
    ci = Int(cli)
    if opcode == 0:
        call wl_destroy_object(ci, Int(oid))
        kl = CL_KBDL[ci]
        ki = 0
        while ki < len(kl):
            if Int(kl[ki]) == Int(oid):
                call kl.pop(ki)
            else:
                ki = ki + 1
            end
        end
    end
    return None
end

function wl_subcompositor_request(cli, oid, opcode, body):
    ci = Int(cli)
    if opcode == 0:
        call wl_destroy_object(ci, Int(oid))
    elif opcode == 1:
        # get_subsurface(new_id, surface, parent)
        sub = Int(w_get32(body, 0))
        surf = Int(w_get32(body, 4))
        parent = Int(w_get32(body, 8))
        call cl_set_kind(ci, sub, WO_SUBSURFACE)
        IntArray(CL_A[ci])[sub] = surf
        IntArray(CL_B[ci])[sub] = parent
        IntArray(CL_F[ci])[surf] = ROLE_SUBSURFACE
        IntArray(CL_G[ci])[surf] = 0
        IntArray(CL_H[ci])[surf] = parent
    end
    return None
end

function wl_subsurface_request(cli, oid, opcode, body):
    ci = Int(cli)
    sub = Int(oid)
    surf = Int(IntArray(CL_A[ci])[sub])
    if opcode == 0:
        call wl_destroy_object(ci, sub)
        if surf > 0:
            IntArray(CL_F[ci])[surf] = ROLE_NONE
        end
    elif opcode == 1:
        x = Int(w_get_int(body, 0))
        y = Int(w_get_int(body, 4))
        if x < 0:
            x = 0
        end
        if y < 0:
            y = 0
        end
        if surf > 0:
            IntArray(CL_G[ci])[surf] = x * 65536 + y
        end
    end
    # place_above/below(2,3), set_sync/desync(4,5): accepted (desync-ish).
    return None
end

# ---------------------------------------------------------------------------
# CLIPBOARD (wl_data_device). Without it a toolkit cannot even copy inside
# itself: in Wayland the compositor owns every selection.
#
# Ownership is one of: a client (SEL_OWNER >= 0, with its wl_data_source),
# or the desktop itself (SEL_OWNER = -2, text in WL_CLIP). Either way every
# client is told there is a selection through a server-allocated
# wl_data_offer, and the paste path just forwards the reader's descriptor:
# a client-owned selection has its source write straight into the pasting
# client's pipe, so no bytes pass through here at all.
SERVER_ID_BASE = 4278190080
SEL_OWNER = [0 - 1]
SEL_SRC = [0]
SEL_MIMES = []
WL_CLIP = [""]
CL_DDEV = []
CL_SRVID = []
CL_OFFER = []
# Mime types offered per data source: parallel lists (client, source, mime).
DS_CI = []
DS_ID = []
DS_MIME = []
# In-flight read of a client-owned selection into WL_CLIP.
CLIP_FD = [0 - 1]
CLIP_BUF = [""]
CLIP_NEW = [0]

# Server-allocated ids must start at exactly 0xff000000 and climb by one:
# the client grows its server-object table by a single entry per id, and
# a gap makes libwayland reject the message outright (EINVAL, and the
# connection is gone).
function wl_next_server_id(ci):
    c = Int(ci)
    v = Int(CL_SRVID[c])
    CL_SRVID[c] = v + 1
    return SERVER_ID_BASE + v
end

function wl_clip_text():
    return String(WL_CLIP[0])
end

# 1 once a client's selection has been mirrored into WL_CLIP.
function wl_clip_taken():
    if Int(CLIP_NEW[0]) == 1:
        CLIP_NEW[0] = 0
        return 1
    end
    return 0
end

function wl_send_offer(ci):
    c = Int(ci)
    if Int(CL_ALIVE[c]) == 0 or Int(CL_DDEV[c]) <= 0:
        return None
    end
    if len(SEL_MIMES) == 0:
        return None
    end
    off = Int(wl_next_server_id(c))
    CL_OFFER[c] = off
    # wl_data_device.data_offer(new_id) then the mime list, then selection.
    args = ByteArray()
    call w_append32(args, off)
    call cl_post(c, Int(CL_DDEV[c]), 0, args)
    mi = 0
    while mi < len(SEL_MIMES):
        m = ByteArray()
        call w_append_string(m, String(SEL_MIMES[mi]))
        call cl_post(c, off, 0, m)
        mi = mi + 1
    end
    sel = ByteArray()
    call w_append32(sel, off)
    call cl_post(c, Int(CL_DDEV[c]), 5, sel)
    return None
end

function wl_broadcast_selection():
    i = 0
    while i < len(CL_FD):
        call wl_send_offer(i)
        i = i + 1
    end
    return None
end

# The desktop copied something: it becomes the selection owner.
function wl_set_clipboard(text):
    if Int(SEL_OWNER[0]) >= 0:
        # cancelled: the previous owner must drop its source.
        call cl_post(Int(SEL_OWNER[0]), Int(SEL_SRC[0]), 1, ByteArray())
    end
    WL_CLIP[0] = String(text)
    SEL_OWNER[0] = 0 - 2
    SEL_SRC[0] = 0
    while len(SEL_MIMES) > 0:
        call SEL_MIMES.pop(len(SEL_MIMES) - 1)
    end
    call SEL_MIMES.append("text/plain;charset=utf-8")
    call SEL_MIMES.append("text/plain")
    call SEL_MIMES.append("UTF8_STRING")
    call SEL_MIMES.append("STRING")
    call SEL_MIMES.append("TEXT")
    call wl_broadcast_selection()
    return None
end

# Ask the owning client to write its selection into a pipe we then read
# across frames, so the desktop's own paste sees what a client copied.
function wl_clip_pull():
    if Int(SEL_OWNER[0]) < 0:
        return None
    end
    want = ""
    mi = 0
    while mi < len(SEL_MIMES):
        m = String(SEL_MIMES[mi])
        if want == "" and (m == "text/plain;charset=utf-8" or m == "UTF8_STRING" or m == "text/plain"):
            want = m
        end
        mi = mi + 1
    end
    if want == "":
        return None
    end
    if Int(CLIP_FD[0]) >= 0:
        call unixsock.close_fd(Int(CLIP_FD[0]))
        CLIP_FD[0] = 0 - 1
    end
    p = unixsock.pipe_nonblock()
    if len(p) < 2:
        return None
    end
    ci = Int(SEL_OWNER[0])
    body = ByteArray()
    call w_append_string(body, want)
    call cl_post_fd(ci, Int(SEL_SRC[0]), 1, body, Int(p[1]), 0)
    CLIP_FD[0] = Int(p[0])
    CLIP_BUF[0] = ""
    return None
end

# Drain that pipe a little every frame; EOF publishes the text.
function wl_clip_tick():
    h = Int(CLIP_FD[0])
    if h < 0:
        return None
    end
    chunk = __lsl_byte_zeros(4096)
    cb = ByteArray(chunk)
    rounds = 0
    while rounds < 4:
        rounds = rounds + 1
        n = 0 - 1
        safe:
            n = fd.read(h, cb, 4096)
        end
        if n > 0:
            out = String(CLIP_BUF[0])
            i = 0
            while i < n:
                out = out + chr(cb[i])
                i = i + 1
            end
            CLIP_BUF[0] = out
            if len(out) > 262144:
                n = 0
            end
        end
        if n == 0:
            WL_CLIP[0] = String(CLIP_BUF[0])
            CLIP_NEW[0] = 1
            call unixsock.close_fd(h)
            CLIP_FD[0] = 0 - 1
            return None
        end
        if n < 0:
            return None
        end
    end
    return None
end

function wl_ddm_request(cli, oid, opcode, body):
    ci = Int(cli)
    newid = Int(w_get32(body, 0))
    if opcode == 0:
        call cl_set_kind(ci, newid, WO_DATA_SOURCE)
    elif opcode == 1:
        call cl_set_kind(ci, newid, WO_DATA_DEVICE)
        CL_DDEV[ci] = newid
        # A client that connects after a copy still learns about it.
        call wl_send_offer(ci)
    end
    return None
end

function wl_data_device_request(cli, oid, opcode, body):
    ci = Int(cli)
    if opcode == 1:
        # set_selection(source, serial): this client now owns the clipboard.
        src = Int(w_get32(body, 0))
        if Int(SEL_OWNER[0]) >= 0 and (Int(SEL_OWNER[0]) != ci or Int(SEL_SRC[0]) != src):
            call cl_post(Int(SEL_OWNER[0]), Int(SEL_SRC[0]), 1, ByteArray())
        end
        while len(SEL_MIMES) > 0:
            call SEL_MIMES.pop(len(SEL_MIMES) - 1)
        end
        if src == 0:
            SEL_OWNER[0] = 0 - 1
            SEL_SRC[0] = 0
            return None
        end
        SEL_OWNER[0] = ci
        SEL_SRC[0] = src
        di = 0
        while di < len(DS_CI):
            if Int(DS_CI[di]) == ci and Int(DS_ID[di]) == src:
                call SEL_MIMES.append(String(DS_MIME[di]))
            end
            di = di + 1
        end
        call wl_broadcast_selection()
        call wl_clip_pull()
    elif opcode == 2:
        call wl_destroy_object(ci, Int(oid))
        if Int(CL_DDEV[ci]) == Int(oid):
            CL_DDEV[ci] = 0
        end
    end
    # start_drag(0): accepted, no drag session on our side.
    return None
end

function wl_data_source_request(cli, oid, opcode, body):
    ci = Int(cli)
    if opcode == 0:
        # offer(mime_type)
        call DS_CI.append(ci)
        call DS_ID.append(Int(oid))
        call DS_MIME.append(w_read_string(body, 0))
    elif opcode == 1:
        call wl_destroy_object(ci, Int(oid))
        di = 0
        while di < len(DS_CI):
            if Int(DS_CI[di]) == ci and Int(DS_ID[di]) == Int(oid):
                call DS_CI.pop(di)
                call DS_ID.pop(di)
                call DS_MIME.pop(di)
            else:
                di = di + 1
            end
        end
        if Int(SEL_OWNER[0]) == ci and Int(SEL_SRC[0]) == Int(oid):
            SEL_OWNER[0] = 0 - 1
            SEL_SRC[0] = 0
        end
    end
    return None
end

# Requests on a server-allocated wl_data_offer id.
function wl_data_offer_request(cli, oid, opcode, body, fds):
    ci = Int(cli)
    if opcode == 1:
        # receive(mime_type, fd): the pasting client handed us a pipe.
        if len(fds) == 0:
            return None
        end
        pfd = Int(fds[0])
        call fds.pop(0)
        mime = w_read_string(body, 0)
        owner = Int(SEL_OWNER[0])
        if owner == 0 - 2:
            # The desktop owns it: write the text and close.
            text = String(WL_CLIP[0])
            data = ByteArray()
            i = 0
            while i < len(text):
                c = ord(text[i])
                if c < 256:
                    call data.append(c)
                else:
                    # UTF-8 for the codepoints a terminal can produce.
                    if c < 2048:
                        call data.append(192 + c // 64)
                        call data.append(128 + c % 64)
                    else:
                        call data.append(224 + c // 4096)
                        call data.append(128 + c // 64 % 64)
                        call data.append(128 + c % 64)
                    end
                end
                i = i + 1
            end
            if len(data) > 0:
                # A pasting client that goes away mid-write only raises here.
                safe:
                    call fd.write(pfd, data, len(data))
                end
            end
            call unixsock.close_fd(pfd)
            return None
        end
        if owner < 0 or owner >= len(CL_FD) or Int(CL_ALIVE[owner]) == 0:
            call unixsock.close_fd(pfd)
            return None
        end
        # A client owns it: hand the descriptor straight to its source, so
        # the two clients copy between themselves and no bytes pass here.
        bd = ByteArray()
        call w_append_string(bd, mime)
        call cl_post_fd(owner, Int(SEL_SRC[0]), 1, bd, pfd, 0)
    end
    # accept(0), destroy(2), finish(3), set_actions(4): nothing to do.
    return None
end

function wl_output_request(cli, oid, opcode, body):
    ci = Int(cli)
    if opcode == 0:
        call wl_destroy_object(ci, Int(oid))
        if Int(CL_OUTID[ci]) == Int(oid):
            CL_OUTID[ci] = 0
        end
    end
    return None
end

function wl_region_request(cli, oid, opcode, body):
    ci = Int(cli)
    if opcode == 0:
        call wl_destroy_object(ci, Int(oid))
    end
    return None
end

# One request from a client, already framed.
function wl_dispatch(cli, oid, opcode, body, fds):
    ci = Int(cli)
    if Int(oid) >= SERVER_ID_BASE:
        call wl_data_offer_request(cli, oid, opcode, body, fds)
        return None
    end
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
    elif kind == WO_BUFFER:
        call wl_buffer_request(cli, oid, opcode, body)
    elif kind == WO_SURFACE:
        call wl_surface_request(cli, oid, opcode, body)
    elif kind == WO_XDG_WM_BASE:
        call wl_xdg_wm_base_request(cli, oid, opcode, body)
    elif kind == WO_XDG_SURFACE:
        call wl_xdg_surface_request(cli, oid, opcode, body)
    elif kind == WO_XDG_TOPLEVEL:
        call wl_xdg_toplevel_request(cli, oid, opcode, body)
    elif kind == WO_XDG_POPUP:
        call wl_xdg_popup_request(cli, oid, opcode, body)
    elif kind == WO_POSITIONER:
        call wl_positioner_request(cli, oid, opcode, body)
    elif kind == WO_SEAT:
        call wl_seat_request(cli, oid, opcode, body)
    elif kind == WO_POINTER:
        call wl_pointer_request(cli, oid, opcode, body)
    elif kind == WO_KEYBOARD:
        call wl_keyboard_request(cli, oid, opcode, body)
    elif kind == WO_SUBCOMPOSITOR:
        call wl_subcompositor_request(cli, oid, opcode, body)
    elif kind == WO_SUBSURFACE:
        call wl_subsurface_request(cli, oid, opcode, body)
    elif kind == WO_DDM:
        call wl_ddm_request(cli, oid, opcode, body)
    elif kind == WO_DATA_DEVICE:
        call wl_data_device_request(cli, oid, opcode, body)
    elif kind == WO_DATA_SOURCE:
        call wl_data_source_request(cli, oid, opcode, body)
    elif kind == WO_OUTPUT:
        call wl_output_request(cli, oid, opcode, body)
    elif kind == WO_REGION:
        call wl_region_request(cli, oid, opcode, body)
    end
    return None
end

# Drain one client's socket and run the complete messages in it, bounded
# so one busy client cannot own the frame: up to 4 reads of 64K and 512
# dispatches per tick; the rest stays buffered for the next frame.
function wl_read_client(index):
    ci = Int(index)
    if Int(CL_ALIVE[ci]) == 0:
        return None
    end
    chunk = WL_RXBUF[0]
    buf = ByteArray(CL_INBUF[ci])
    reads = 0
    more = 1
    while more == 1 and reads < 4:
        reads = reads + 1
        n = unixsock.recv_fds(Int(CL_FD[ci]), chunk, 65536, CL_FDS[ci])
        if n == 0:
            call wl_client_drop(ci)
            return None
        end
        if n < 0:
            more = 0
        else:
            data = ByteArray(chunk)
            i = 0
            while i < n:
                call buf.append(data[i])
                i = i + 1
            end
            if n < 65536:
                more = 0
            end
        end
    end
    # Frame: id(4) + size/opcode(4) + body.
    pos = 0
    msgs = 0
    run = 1
    while run == 1 and len(buf) - pos >= 8 and msgs < 512:
        # Read the header from the typed local: a dynamically typed list
        # element does not survive the ByteArray() cast inside a helper.
        oid = Int(buf[pos]) + Int(buf[pos + 1]) * 256 + Int(buf[pos + 2]) * 65536 + Int(buf[pos + 3]) * 16777216
        head = Int(buf[pos + 4]) + Int(buf[pos + 5]) * 256 + Int(buf[pos + 6]) * 65536 + Int(buf[pos + 7]) * 16777216
        size = head // 65536
        opcode = head % 65536
        if size < 8 or len(buf) - pos < size:
            run = 0
        else:
            body = __lsl_byte_zeros(size - 8)
            bb = ByteArray(body)
            k = 0
            while k < size - 8:
                bb[k] = buf[pos + 8 + k]
                k = k + 1
            end
            call wl_dispatch(ci, oid, opcode, body, CL_FDS[ci])
            pos = pos + size
            msgs = msgs + 1
        end
    end
    if pos > 0:
        rest = ByteArray()
        k = pos
        while k < len(buf):
            call rest.append(buf[k])
            k = k + 1
        end
        CL_INBUF[ci] = rest
    else:
        CL_INBUF[ci] = buf
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
    safe:
        call wl_clip_tick()
    end
    return None
end

# Tell every surface whose frame callback is pending that its content is on
# screen now: done(time_ms), then delete_id. A client draws its next frame
# only after this, so it never runs ahead of the compositor. The scan stops
# at the highest object id the client ever allocated.
function wl_frame_done(now_ms):
    WL_TIME[0] = Int(now_ms)
    i = 0
    while i < len(CL_FD):
        ci = i
        if Int(CL_ALIVE[ci]) == 1:
            kinds = IntArray(CL_KIND[ci])
            cbs = IntArray(CL_D[ci])
            top = Int(CL_MAXID[ci])
            s = 0
            while s < top:
                if kinds[s] == WO_SURFACE:
                    cb = cbs[s]
                    if cb > 0:
                        args = ByteArray()
                        call w_append32(args, Int(now_ms))
                        call cl_post(ci, cb, 0, args)
                        dele = ByteArray()
                        call w_append32(dele, cb)
                        call cl_post(ci, 1, 1, dele)
                        cbs[s] = 0
                    end
                end
                s = s + 1
            end
        end
        i = i + 1
    end
    call wl_flush_all()
    # Mappings retired this tick are safe to drop now: the compositor has
    # copied every committed buffer it was told about.
    call wl_reap()
    return None
end
