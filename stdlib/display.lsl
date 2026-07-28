# Unified display for gfx surfaces with two interchangeable backends:
# an X11 window (desktop) and the Linux framebuffer (LuxOS console). One
# Display class drives both so an application written against present()/
# poll()/should_close() runs unchanged on either. Pure LSL: X11 is a
# socket protocol client, the framebuffer is /dev/fb0 — no display server
# library and no native code.
#
# Both backends emit the same event tuples: ("key", linux_code, 1/0),
# ("button", n, 1/0), ("motion", x, y), ("expose", 0, 0), ("close",0,0).

load env
load fd
load x11
load input
load time

# Frame-rate ceiling enforced inside present(): even an application that
# redraws in a tight loop with no sleep of its own cannot spin faster than
# this, which bounds CPU and power. 60 Hz is plenty for a GUI.
frame_interval = 0.0166

function sysfs_int(path):
    return Int(readfile(path).strip())
end

# ---------------------------------------------------------------------------
# DRM/KMS backend plumbing. The GPU's kernel driver scans out a dumb buffer
# we map and write pixels into directly: no fbdev shadow copy, no deferred-io
# flush latency, and explicit per-rectangle damage (DIRTYFB) so drivers with
# a host upload step (virtio-gpu) transfer only what changed. When the last
# DRM descriptor closes — clean exit or crash alike — the kernel restores
# the framebuffer console scanout itself.

DRM_SET_MASTER = 25630
DRM_DROP_MASTER = 25631
DRM_GETRESOURCES = 3225445536
DRM_GETCRTC = 3228066977
DRM_SETCRTC = 3228066978
DRM_GETENCODER = 3222561958
DRM_GETCONNECTOR = 3226494119
DRM_ADDFB = 3223086254
DRM_DIRTYFB = 3222824113
DRM_CREATE_DUMB = 3223348402
DRM_MAP_DUMB = 3222299827

# Descriptor of the DRM card currently open, -1 when none: a failed
# initialisation is closed through this, which releases the master lease.
DRM_HANDLE = [0 - 1]
# Set when the DRM backend was available but its initialisation failed.
DRM_FALLBACK = [""]

function put16(buffer, offset, value):
    b = ByteArray(buffer)
    v = Int(value)
    b[offset] = v % 256
    b[offset + 1] = v // 256 % 256
    return None
end

function put32(buffer, offset, value):
    b = ByteArray(buffer)
    v = Int(value)
    b[offset] = v % 256
    b[offset + 1] = v // 256 % 256
    b[offset + 2] = v // 65536 % 256
    b[offset + 3] = v // 16777216 % 256
    return None
end

function put64(buffer, offset, value):
    call put32(buffer, offset, Int(value) % 4294967296)
    call put32(buffer, offset + 4, Int(value) // 4294967296)
    return None
end

function get16(buffer, offset):
    b = ByteArray(buffer)
    return Int(b[offset]) + Int(b[offset + 1]) * 256
end

function get32(buffer, offset):
    b = ByteArray(buffer)
    return Int(b[offset]) + Int(b[offset + 1]) * 256 + Int(b[offset + 2]) * 65536 + Int(b[offset + 3]) * 16777216
end

# Raw data pointer of a ByteArray's payload (the kernel writes there).
function data_address(buffer):
    return Int(__lsl_data_address(buffer))
end

class Display(True):
    ctype Public

    function init(self, kind, width, height, title, stride):
        self.kind = kind
        self.width = Int(width)
        self.height = Int(height)
        self.stride = Int(stride)
        self.closed = False
        self.keyboard = 0 - 1
        self.last_present = 0.0
        self.last_checksum = 0 - 1
        self.frame_index = 0
        if kind == "x11":
            info = x11.create_window(width, height, title)
            self.handle = info["handle"]
            self.window_id = info["window_id"]
            self.gc_id = info["gc_id"]
            self.depth = info["depth"]
            self.wm_delete = info["wm_delete"]
            self.carry = ByteArray()
            self.scratch = __lsl_byte_zeros(4096)
            self.request = __lsl_byte_zeros(70000)
        elif kind == "drm":
            self.device = title
            self.handle = fd.open(title, fd.read_write)
            # Recorded before anything can fail: if initialisation throws,
            # open() closes this descriptor, which is what releases the
            # master lease that would otherwise leave fbdev dead.
            DRM_HANDLE[0] = self.handle
            master_rc = fd.ioctl(self.handle, DRM_SET_MASTER, ByteArray())
            if master_rc < 0:
                Error(DisplayError: "DRM SET_MASTER failed (" + String(master_rc) + ")")
            end
            # Resource discovery: first call returns counts, second fills
            # the id arrays. Layout: crtc_ptr @8, connector_ptr @16,
            # count_crtcs @36, count_connectors @40.
            res = __lsl_byte_zeros(64)
            if fd.ioctl(self.handle, DRM_GETRESOURCES, res) < 0:
                Error(DisplayError: "DRM GETRESOURCES failed")
            end
            count_crtcs = get32(res, 36)
            count_connectors = get32(res, 40)
            if count_connectors < 1 or count_crtcs < 1:
                Error(DisplayError: "DRM device has no outputs")
            end
            crtc_ids = __lsl_byte_zeros(count_crtcs * 4)
            conn_ids = __lsl_byte_zeros(count_connectors * 4)
            call put64(res, 8, data_address(crtc_ids))
            call put64(res, 16, data_address(conn_ids))
            call put32(res, 36, count_crtcs)
            call put32(res, 40, count_connectors)
            # The framebuffer and encoder arrays are not wanted: their
            # counts must be zeroed too, or the kernel writes through the
            # NULL pointers left in the request and the call fails EFAULT.
            call put32(res, 32, 0)
            call put32(res, 44, 0)
            if fd.ioctl(self.handle, DRM_GETRESOURCES, res) < 0:
                Error(DisplayError: "DRM GETRESOURCES(ids) failed")
            end
            # First connected connector with at least one mode.
            conn_id = 0
            enc_id = 0
            self.mode = __lsl_byte_zeros(68)
            found = 0
            ci = 0
            while ci < count_connectors and found == 0:
                cid = get32(conn_ids, ci * 4)
                probe = __lsl_byte_zeros(80)
                call put32(probe, 48, cid)
                if fd.ioctl(self.handle, DRM_GETCONNECTOR, probe) >= 0:
                    nmodes = get32(probe, 32)
                    if get32(probe, 60) == 1 and nmodes > 0:
                        modes = __lsl_byte_zeros(nmodes * 68)
                        fetch = __lsl_byte_zeros(80)
                        call put64(fetch, 8, data_address(modes))
                        call put32(fetch, 32, nmodes)
                        call put32(fetch, 48, cid)
                        if fd.ioctl(self.handle, DRM_GETCONNECTOR, fetch) >= 0:
                            modeb = ByteArray(self.mode)
                            srcb = ByteArray(modes)
                            mi = 0
                            while mi < 68:
                                modeb[mi] = srcb[mi]
                                mi += 1
                            end
                            conn_id = cid
                            enc_id = get32(fetch, 44)
                            found = 1
                        end
                    end
                end
                ci += 1
            end
            if found == 0:
                Error(DisplayError: "DRM: no connected output")
            end
            # CRTC behind the connector's current encoder, else the first.
            crtc_id = get32(crtc_ids, 0)
            if enc_id != 0:
                enc = __lsl_byte_zeros(20)
                call put32(enc, 0, enc_id)
                if fd.ioctl(self.handle, DRM_GETENCODER, enc) >= 0:
                    if get32(enc, 8) != 0:
                        crtc_id = get32(enc, 8)
                    end
                end
            end
            # Prefer the mode the firmware already set (keeps the desktop's
            # sysfs-derived size and avoids a visible mode switch).
            crtc = __lsl_byte_zeros(104)
            call put32(crtc, 12, crtc_id)
            got_crtc = fd.ioctl(self.handle, DRM_GETCRTC, crtc)
            # Everything needed to put the console's scanout back exactly as
            # it was: the driver is supposed to restore it on the last close,
            # but not every driver does, and a session that leaves a dead
            # screen behind is worse than one that never took it.
            self.restore = __lsl_byte_zeros(104)
            self.restore_ok = 0
            if got_crtc >= 0:
                if get32(crtc, 32) == 1 and get16(crtc, 40) > 0:
                    modeb = ByteArray(self.mode)
                    crtcb = ByteArray(crtc)
                    mi = 0
                    while mi < 68:
                        modeb[mi] = crtcb[36 + mi]
                        mi += 1
                    end
                end
            end
            self.width = get16(self.mode, 4)
            self.height = get16(self.mode, 14)
            if self.width < 16 or self.height < 16:
                Error(DisplayError: "DRM: no usable mode")
            end
            # Dumb buffer -> framebuffer object -> mapped pixels.
            dumb = __lsl_byte_zeros(32)
            call put32(dumb, 0, self.height)
            call put32(dumb, 4, self.width)
            call put32(dumb, 8, 32)
            rc = fd.ioctl(self.handle, DRM_CREATE_DUMB, dumb)
            if rc < 0:
                Error(DisplayError: "DRM CREATE_DUMB failed (" + String(rc) + ")")
            end
            self.bo_handle = get32(dumb, 16)
            self.stride = get32(dumb, 20)
            bo_size = get32(dumb, 24) + get32(dumb, 28) * 4294967296
            addfb = __lsl_byte_zeros(28)
            call put32(addfb, 4, self.width)
            call put32(addfb, 8, self.height)
            call put32(addfb, 12, self.stride)
            call put32(addfb, 16, 32)
            call put32(addfb, 20, 24)
            call put32(addfb, 24, self.bo_handle)
            rc = fd.ioctl(self.handle, DRM_ADDFB, addfb)
            if rc < 0:
                Error(DisplayError: "DRM ADDFB failed (" + String(rc) + ")")
            end
            self.fb_id = get32(addfb, 0)
            mapreq = __lsl_byte_zeros(16)
            call put32(mapreq, 0, self.bo_handle)
            rc = fd.ioctl(self.handle, DRM_MAP_DUMB, mapreq)
            if rc < 0:
                Error(DisplayError: "DRM MAP_DUMB failed (" + String(rc) + ")")
            end
            self.vram = fd.mmap(self.handle, bo_size, get32(mapreq, 8) + get32(mapreq, 12) * 4294967296)
            if self.vram < 0:
                Error(DisplayError: "DRM mmap failed")
            end
            # Throughput gate. A dumb buffer can land in uncached video
            # memory (firmware-style KMS drivers, discrete cards over PCIe),
            # where writing a frame is several times slower than the fbdev
            # path this replaces — fbdev renders into a cached RAM shadow the
            # driver flushes itself. Measure the real thing once and refuse
            # the backend when it would be a downgrade; the caller then falls
            # back to fbdev and the descriptor is closed, releasing master.
            probe_px = __lsl_int_zeros(self.width)
            probe_rows = Int(min(64, self.height))
            probe_w = Int(self.width)
            probe_stride = Int(self.stride)
            probe_vram = Int(self.vram)
            row = 0
            while row < probe_rows:
                call __lsl_mem_pack(probe_vram, probe_px, 0, row * probe_stride, probe_w)
                row += 1
            end
            probe_t0 = time.monotonic()
            row = 0
            while row < probe_rows:
                call __lsl_mem_pack(probe_vram, probe_px, 0, row * probe_stride, probe_w)
                row += 1
            end
            probe_elapsed = time.monotonic() - probe_t0
            probe_bytes = probe_rows * probe_w * 4
            if probe_elapsed > 0.0:
                probe_rate = Float(probe_bytes) / probe_elapsed
                if probe_rate < 700000000.0:
                    Error(DisplayError: "DRM scanout memory is too slow (" + String(Int(probe_rate / 1000000.0)) + " MB/s)")
                end
            end
            # Scan out our framebuffer. A fresh request buffer: the one used
            # for GETCRTC carries fields (gamma_size and the driver's own
            # reply state) that must not be fed back into SETCRTC. The
            # connector-id array lives in a member so its address stays
            # valid for the call.
            self.conn_buf = __lsl_byte_zeros(4)
            call put32(self.conn_buf, 0, conn_id)
            if got_crtc >= 0:
                restb = ByteArray(self.restore)
                crtcb0 = ByteArray(crtc)
                ri = 0
                while ri < 104:
                    restb[ri] = crtcb0[ri]
                    ri += 1
                end
                call put64(self.restore, 0, data_address(self.conn_buf))
                call put32(self.restore, 8, 1)
                call put32(self.restore, 12, crtc_id)
                self.restore_ok = 1
            end
            setreq = __lsl_byte_zeros(104)
            call put64(setreq, 0, data_address(self.conn_buf))
            call put32(setreq, 8, 1)
            call put32(setreq, 12, crtc_id)
            call put32(setreq, 16, self.fb_id)
            call put32(setreq, 32, 1)
            setb = ByteArray(setreq)
            modeb = ByteArray(self.mode)
            mi = 0
            while mi < 68:
                setb[36 + mi] = modeb[mi]
                mi += 1
            end
            rc = fd.ioctl(self.handle, DRM_SETCRTC, setreq)
            if rc < 0:
                Error(DisplayError: "DRM SETCRTC failed (" + String(rc) + ")")
            end
            self.crtc_id = crtc_id
            # Reusable damage request: one clip rectangle per flush.
            self.clip = __lsl_byte_zeros(8)
            self.dirty = __lsl_byte_zeros(24)
            call put32(self.dirty, 0, self.fb_id)
            call put32(self.dirty, 12, 1)
            call put64(self.dirty, 16, data_address(self.clip))
            safe:
                self.keyboard = input.open_keyboard_device()
            end
        else:
            self.device = title
            self.handle = fd.open(title, fd.write_only + fd.create)
            safe:
                self.keyboard = input.open_keyboard_device()
            end
        end
        if kind == "drm":
            # Frames go straight into the mapped buffer; no pack staging.
            self.packed = __lsl_byte_zeros(1)
        else:
            self.packed = __lsl_byte_zeros(self.stride * self.height)
        end
    end

    # Report damage to the driver (virtio-gpu uploads only these rows;
    # VRAM-backed drivers ignore it). x2/y2 are exclusive.
    function flush_rect(self, x1, y1, x2, y2):
        if self.kind != "drm":
            return None
        end
        call put16(self.clip, 0, x1)
        call put16(self.clip, 2, y1)
        call put16(self.clip, 4, x2)
        call put16(self.clip, 6, y2)
        call fd.ioctl(self.handle, DRM_DIRTYFB, self.dirty)
        return None
    end

    # Pack a gfx surface to little-endian BGRX and send it to the active
    # backend. Caller passes the surface fields: d.present(s.pixels,
    # s.width, s.height).
    function present(self, pixels, width, height):
        if self.kind == "drm":
            call self.present_drm(pixels, width, height)
            return None
        end
        # Every loop value is a typed Int local: reading self.width/height
        # (boxed members) directly inside the pack loop boxed a fresh Int
        # PER PIXEL (~8 MB of garbage per full-HD-ish frame), which the
        # conservative GC could not always reclaim.
        src = IntArray(pixels)
        src_width = Int(width)
        rows = min(Int(height), Int(self.height))
        columns = min(src_width, Int(self.width))
        packed = ByteArray(self.packed)
        row_stride = Int(self.stride)
        row = 0
        while row < rows:
            call __lsl_raster_pack(src, packed, row * src_width, row * row_stride, columns)
            row += 1
        end
        # put_image and the pack loop reuse self.request/self.packed and use
        # only typed Int locals, so a full frame allocates no garbage — the
        # app can present every frame without a growing heap.
        if self.kind == "x11":
            call x11.put_image(self.handle, self.window_id, self.gc_id, self.depth, self.width, rows, packed, self.request)
        else:
            call fd.seek(self.handle, 0)
            call fd.write(self.handle, packed, row_stride * rows)
        end
        return None
    end

    # DRM full present: pack every row straight into the mapped buffer and
    # report the whole screen dirty.
    function present_drm(self, pixels, width, height):
        src = IntArray(pixels)
        src_width = Int(width)
        rows = min(Int(height), Int(self.height))
        columns = min(src_width, Int(self.width))
        vram = Int(self.vram)
        row_stride = Int(self.stride)
        row = 0
        while row < rows:
            call __lsl_mem_pack(vram, src, row * src_width, row * row_stride, columns)
            row += 1
        end
        call self.flush_rect(0, 0, columns, rows)
        return None
    end

    # Pack and send only the given rectangle. On the file/framebuffer backend
    # this writes just the touched rows/columns — far cheaper than a full
    # present for small updates (a cursor, a progress bar): framebuffer VRAM
    # writes are uncached, so cost is proportional to bytes written. Falls
    # back to a full present on the X11 backend.
    function present_rect(self, pixels, width, height, rx, ry, rw, rh):
        if self.kind == "x11":
            call self.present(pixels, width, height)
            return None
        end
        if self.kind == "drm":
            src9 = IntArray(pixels)
            sw9 = Int(width)
            y09 = Int(ry)
            y19 = Int(ry) + Int(rh)
            if y09 < 0:
                y09 = 0
            end
            limit9 = min(Int(height), Int(self.height))
            if y19 > limit9:
                y19 = limit9
            end
            cols9 = min(sw9, Int(self.width))
            if y19 <= y09:
                return None
            end
            vram9 = Int(self.vram)
            stride9 = Int(self.stride)
            row9 = y09
            while row9 < y19:
                call __lsl_mem_pack(vram9, src9, row9 * sw9, row9 * stride9, cols9)
                row9 += 1
            end
            call self.flush_rect(0, y09, cols9, y19)
            return None
        end
        src = IntArray(pixels)
        src_width = Int(width)
        x0 = Int(rx)
        y0 = Int(ry)
        x1 = x0 + Int(rw)
        y1 = y0 + Int(rh)
        if x0 < 0:
            x0 = 0
        end
        if y0 < 0:
            y0 = 0
        end
        limit_x = min(src_width, Int(self.width))
        limit_y = min(Int(height), Int(self.height))
        if x1 > limit_x:
            x1 = limit_x
        end
        if y1 > limit_y:
            y1 = limit_y
        end
        if x1 <= x0 or y1 <= y0:
            return None
        end
        packed = ByteArray(self.packed)
        row_stride = Int(self.stride)
        # Pack the touched rows full-width and send them as ONE contiguous
        # write. The previous per-row seek+write pair issued hundreds of
        # syscalls per frame, and deferred-io framebuffers (virtio-gpu/bochs
        # fbdev) schedule a flush per write — animations took seconds and
        # the pointer lagged. One write per present keeps one flush.
        columns = limit_x
        row = y0
        while row < y1:
            call __lsl_raster_pack(src, packed, row * src_width, (row - y0) * row_stride, columns)
            row += 1
        end
        call fd.seek(self.handle, y0 * row_stride)
        call fd.write(self.handle, packed, (y1 - y0) * row_stride)
        return None
    end

    # Sleep to hold a target frame rate. Call once per loop after present.
    function wait_frame(self):
        call time.sleep(frame_interval)
        return None
    end

    # Reclaim garbage explicitly. Safe to call right after a frame's events
    # are fully processed (e.g. inside the redraw branch); calling it while
    # input may be mid-arrival can drop events, so it is not automatic.
    function collect(self):
        call gc()
        return None
    end

    # Nonblocking event drain, normalized across backends.
    function poll(self):
        if self.kind == "x11":
            result = x11.read_events(self.handle, self.carry, self.wm_delete, self.scratch)
            self.carry = result["carry"]
            if result["closed"]:
                self.closed = True
            end
            return result["events"]
        end
        if self.keyboard < 0:
            return []
        end
        return input.read_key_events(self.keyboard)
    end

    function should_close(self):
        return self.closed
    end

    function close(self):
        if self.keyboard >= 0:
            call fd.close(self.keyboard)
        end
        if self.kind == "x11":
            call x11.close(self.handle)
        elif self.kind == "drm":
            # Hand the console's scanout back before letting go of master.
            if Int(self.restore_ok) == 1:
                safe:
                    call fd.ioctl(self.handle, DRM_SETCRTC, self.restore)
                end
            end
            call fd.ioctl(self.handle, DRM_DROP_MASTER, ByteArray())
            call fd.close(self.handle)
            DRM_HANDLE[0] = 0 - 1
        else:
            call fd.close(self.handle)
        end
        return None
    end
end

# Open a window on the best available backend. With DISPLAY set and an X
# socket present this is a desktop window; on a console the GPU's DRM/KMS
# path is preferred (direct dumb-buffer scanout, per-rect damage), with the
# legacy fbdev write path as the fallback. LSL_DISPLAY=fb, =x11 or =drm
# forces a backend.
function open(width, height, title):
    forced = env.get("LSL_DISPLAY", "")
    if forced == "x11" or (forced != "fb" and forced != "drm" and x11_available()):
        return Display("x11", width, height, title, Int(width) * 4)
    end
    if forced == "drm":
        return open_drm()
    end
    # GPU scanout is tried first on a console: the KMS dumb buffer is
    # written directly, with no fbdev shadow copy and no deferred-io flush.
    # Every failure path (including a buffer too slow to be worth it) closes
    # the descriptor, which releases the master lease — holding it would
    # stop the kernel's fbdev emulation from scanning out and black out the
    # machine. LSL_DISPLAY=fb forces the legacy path.
    if forced != "fb" and exists("/dev/dri/card0"):
        # The return stays inside the safe block: binding the result to a
        # local first would widen this function's inferred return type away
        # from Display, and every caller's d.width/d.height would stop
        # type-checking.
        safe:
            return open_drm()
        end
        # Why the GPU path was refused, for the caller's diagnostics: a
        # silent fall back to fbdev is otherwise indistinguishable from a
        # machine with no KMS driver at all.
        DRM_FALLBACK[0] = last_error()
        # CRITICAL: a half-initialised DRM client still holds the master
        # lease, and while anyone holds it the kernel's fbdev emulation
        # stops scanning out — the fbdev fall back below would draw into a
        # dead framebuffer ("display output is not active"). Close every
        # card node so the lease is released before falling back.
        safe:
            call drm_release()
        end
    end
    return open_framebuffer()
end

# Close the descriptor a failed DRM Display() left behind. The master
# lease belongs to that exact open file, so dropping it through a fresh
# open would do nothing — the failed descriptor is recorded in DRM_HANDLE
# the moment it exists, precisely so this can close it.
function drm_release():
    handle = Int(DRM_HANDLE[0])
    if handle >= 0:
        safe:
            call fd.ioctl(handle, DRM_DROP_MASTER, ByteArray())
        end
        call fd.close(handle)
        DRM_HANDLE[0] = 0 - 1
    end
    return None
end

# Open the DRM/KMS backend directly: /dev/dri/card0, the firmware's current
# mode, a mapped dumb buffer as the frame target.
function open_drm():
    return Display("drm", 0, 0, "/dev/dri/card0", 4)
end

function x11_available():
    display = env.get("DISPLAY", "")
    if display == "":
        return False
    end
    number = x11.display_number()
    return exists("/tmp/.X11-unix/X" + String(number))
end

# Open the framebuffer backend directly. Honours LSL_FB_DEV/LSL_FB_MODE
# ("WIDTHxHEIGHTxSTRIDE") for testing into a plain file.
function open_framebuffer():
    device = env.get("LSL_FB_DEV", None)
    mode = env.get("LSL_FB_MODE", None)
    if device != None and mode != None:
        parts = mode.split("x")
        if len(parts) != 3:
            Error(DisplayError: "LSL_FB_MODE must be WIDTHxHEIGHTxSTRIDE")
        end
        return Display("file", Int(parts[0]), Int(parts[1]), device, Int(parts[2]))
    end
    return open_device("fb0")
end

function open_device(name):
    sys_base = "/sys/class/graphics/" + name + "/"
    if not exists(sys_base + "virtual_size"):
        Error(DisplayError: "framebuffer " + name + " is not available")
    end
    depth = sysfs_int(sys_base + "bits_per_pixel")
    if depth != 32:
        Error(DisplayError: "only 32bpp framebuffers are supported")
    end
    size = readfile(sys_base + "virtual_size").strip().split(",")
    width = Int(size[0])
    height = Int(size[1])
    stride = sysfs_int(sys_base + "stride")
    return Display("file", width, height, "/dev/" + name, stride)
end
