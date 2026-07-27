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
        else:
            self.device = title
            self.handle = fd.open(title, fd.write_only + fd.create)
            safe:
                self.keyboard = input.open_keyboard_device()
            end
        end
        self.packed = __lsl_byte_zeros(self.stride * self.height)
    end

    # Pack a gfx surface to little-endian BGRX and send it to the active
    # backend. Caller passes the surface fields: d.present(s.pixels,
    # s.width, s.height).
    function present(self, pixels, width, height):
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
        else:
            call fd.close(self.handle)
        end
        return None
    end
end

# Open a window on the best available backend. With DISPLAY set and an X
# socket present this is a desktop window; otherwise it falls back to the
# framebuffer (fitting the requested size). LSL_DISPLAY=fb or =x11 forces
# a backend.
function open(width, height, title):
    forced = env.get("LSL_DISPLAY", "")
    if forced == "x11" or (forced != "fb" and x11_available()):
        return Display("x11", width, height, title, Int(width) * 4)
    end
    return open_framebuffer()
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
