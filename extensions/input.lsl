# Linux evdev keyboard input. The keyboard is found by parsing
# /proc/bus/input/devices and events are read nonblocking from
# /dev/input/eventN, so no display server is needed. The process must
# have read access to the device (root or the input group).
#
# Functions are free (not methods) so display.Display can reuse them for
# the framebuffer backend; key codes match X11's (evdev code) so both
# display backends emit identical ("key", code, pressed) events.

load fd

# Common key codes from linux input-event-codes.h.
key_esc = 1
key_enter = 28
key_space = 57
key_up = 103
key_left = 105
key_right = 106
key_down = 108
key_q = 16

press = 1
release = 0
repeat = 2

# One input_event is 24 bytes on 64-bit: time (16), type u16, code u16,
# value s32.
event_size = 24

function keyboard_device():
    listing = fd.read_text_limit("/proc/bus/input/devices", 1048576)
    for block in listing.split("\n\n"):
        if block.find("Handlers=") < 0:
            continue
        end
        for line in block.split("\n"):
            if line.startswith("H: ") and line.find("kbd") >= 0:
                for token in line.split(" "):
                    if token.startswith("event"):
                        name = token.strip()
                        suffix = name[5:len(name)]
                        if suffix == "" or len(suffix) > 6:
                            continue
                        end
                        valid = True
                        for character in suffix:
                            code = ord(character)
                            if code < 48 or code > 57:
                                valid = False
                            end
                        end
                        if valid:
                            return "/dev/input/" + name
                        end
                    end
                end
            end
        end
    end
    Error(InputError: "no keyboard found in /proc/bus/input/devices")
end

function open_keyboard_device():
    return fd.open(keyboard_device(), fd.nonblock)
end

# Drain pending key events from an evdev handle. Returns a List of
# ("key", code, value) tuples; value is press/release/repeat and code is
# a Linux key code, matching the X11 backend.
function read_key_events(handle):
    events = []
    buffer = ByteArray()
    index = 0
    while index < event_size * 64:
        buffer.append(0)
        index += 1
    end
    reads = 0
    loop:
        if reads >= 256 or len(events) >= 4096:
            break
        end
        count = fd.read(handle, buffer, event_size * 64)
        if count == fd.again or count == 0:
            break
        end
        offset = 0
        while offset + event_size <= count:
            kind = buffer[offset + 16] + buffer[offset + 17] * 256
            if kind == 1:
                code = buffer[offset + 18] + buffer[offset + 19] * 256
                value = buffer[offset + 20]
                events.append(("key", code, value))
            end
            offset += event_size
        end
        reads += 1
    end
    return events
end
