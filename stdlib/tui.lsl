load _tui_platform as transport
# tui — a small terminal UI toolkit for full-screen, keyboard-driven LSL apps.
#
# It puts the controlling terminal into cbreak mode (single-key reads, no echo),
# switches to the alternate screen, and offers ANSI rendering plus a normalized
# key decoder. It is pure LSL over the fd runtime and the `stty` tool: no curses
# and no native code. One Terminal instance owns the session; call enter() once,
# render on each key from read_key(), and always call leave() to restore the
# terminal (even on error, via a safe: block in the caller).
#
# Keys returned by read_key() are strings: "up"/"down"/"left"/"right",
# "home"/"end"/"pageup"/"pagedown"/"delete", "enter"/"backspace"/"tab"/"esc",
# "ctrl-c"/"ctrl-d", "char:X" for a printable character X, or "code:N" otherwise.

load fd
load os

ESC = chr(27)

# Foreground/background SGR colour codes (bright variants add 60).
color_black = 30
color_red = 31
color_green = 32
color_yellow = 33
color_blue = 34
color_magenta = 35
color_cyan = 36
color_white = 37

function stty_tool():
    return transport.stty_tool()
end

class Terminal(True):
    ctype Public

    function init(self):
        self.saved = ""
        self.active = False
        self.rows = 24
        self.cols = 80
        self.inbuf = __lsl_byte_zeros(32)
        self.input_index = 0
        self.input_count = 0
        self.out = ByteArray()
    end

    # Enter cbreak + alternate screen. Saves the current stty state so leave()
    # can restore it exactly.
    function enter(self):
        self.saved = transport.enter_state()
        call self.query_size()
        self.active = True
        call self.emit(ESC + "[?1049h" + ESC + "[?25l" + ESC + "[2J")
        call self.flush()
        return None
    end

    # Restore the terminal: show cursor, leave the alternate screen, restore the
    # saved stty state. Safe to call more than once.
    function leave(self):
        if self.active:
            call self.emit(ESC + "[0m" + ESC + "[?25h" + ESC + "[?1049l")
            call self.flush()
            self.active = False
        end
        if self.saved != "":
            call transport.restore_state(self.saved)
            self.saved = ""
        end
        return None
    end

    # Read the terminal size (rows, cols) via `stty size`.
    function query_size(self):
        size = transport.dimensions()
        if len(size) == 2:
            self.rows = size[0]
            self.cols = size[1]
        end
        return None
    end

    # Queue a string for output; nothing is sent until flush(). Batching a whole
    # frame into one write avoids flicker. Code points above ASCII are UTF-8
    # encoded — ByteArray.append rejects values over 255, so a frame containing
    # "↑" used to abort the caller's render loop mid-frame.
    function emit(self, text):
        if type(text) != "String":
            Error(TypeError: "terminal output must be a String")
        elif __lsl_text_byte_length(String(text)) > 16777216 - len(ByteArray(self.out)):
            Error(TUIError: "queued terminal output exceeds 16 MiB")
        end
        buffer = ByteArray(self.out)
        i = 0
        limit = len(text)
        while i < limit:
            cp = ord(text[i])
            if cp < 128:
                call buffer.append(cp)
            elif cp < 2048:
                call buffer.append(192 + cp // 64)
                call buffer.append(128 + cp % 64)
            elif cp < 65536:
                call buffer.append(224 + cp // 4096)
                call buffer.append(128 + cp // 64 % 64)
                call buffer.append(128 + cp % 64)
            else:
                call buffer.append(240 + cp // 262144)
                call buffer.append(128 + cp // 4096 % 64)
                call buffer.append(128 + cp // 64 % 64)
                call buffer.append(128 + cp % 64)
            end
            i = i + 1
        end
        self.out = buffer
        return None
    end

    # Write the queued output to stdout and clear the queue.
    function flush(self):
        buffer = ByteArray(self.out)
        size = len(buffer)
        if size > 0:
            call fd.write(1, buffer, size)
        end
        self.out = ByteArray()
        return None
    end

    # ANSI helpers — all queue onto the output buffer.
    function move(self, row, col):
        call self.emit(ESC + "[" + String(row) + ";" + String(col) + "H")
        return None
    end

    function clear(self):
        call self.emit(ESC + "[2J" + ESC + "[H")
        return None
    end

    function clear_line(self):
        call self.emit(ESC + "[2K")
        return None
    end

    function reset_style(self):
        call self.emit(ESC + "[0m")
        return None
    end

    function set_fg(self, code):
        call self.emit(ESC + "[" + String(code) + "m")
        return None
    end

    function set_bg(self, code):
        call self.emit(ESC + "[" + String(code + 10) + "m")
        return None
    end

    function bold(self):
        call self.emit(ESC + "[1m")
        return None
    end

    function invert(self):
        call self.emit(ESC + "[7m")
        return None
    end

    # Place text at (row, col) with no styling.
    function text_at(self, row, col, text):
        call self.move(row, col)
        call self.emit(text)
        return None
    end

    # Buffered byte reads preserve pasted keys and split escape sequences.
    # A short poll distinguishes a standalone Escape from an ANSI key sequence.
    function read_byte(self, timeout):
        if self.input_index >= self.input_count:
            if timeout >= 0:
                ready = transport.wait_readable(timeout)
                if ready == 0:
                    return -2
                elif ready < 0:
                    Error(TUIError: "terminal input poll failed")
                end
            end
            self.input_count = fd.read(0, ByteArray(self.inbuf), 32)
            self.input_index = 0
            if self.input_count <= 0:
                return -1
            end
        end
        result = ByteArray(self.inbuf)[self.input_index]
        self.input_index += 1
        return result
    end

    function read_key(self):
        first = self.read_byte(-1)
        if first < 0:
            return "none"
        elif first == 27:
            second = self.read_byte(50)
            if second < 0:
                return "esc"
            elif second != 91 and second != 79:
                # Leave a following ordinary key queued, rather than eating it.
                self.input_index -= 1
                return "esc"
            end
            sequence = ""
            for index in rang(24):
                byte = self.read_byte(50)
                if byte < 0:
                    return "esc"
                end
                sequence += chr(byte)
                if byte >= 64 and byte <= 126:
                    break
                end
            end
            keys = {"A": "up", "B": "down", "C": "right", "D": "left", "H": "home", "F": "end", "1~": "home", "4~": "end", "5~": "pageup", "6~": "pagedown", "3~": "delete", "Z": "backtab"}
            return keys.get(sequence, "esc")
        elif first == 13 or first == 10:
            return "enter"
        elif first == 127 or first == 8:
            return "backspace"
        elif first == 9:
            return "tab"
        elif first == 3:
            return "ctrl-c"
        elif first == 4:
            return "ctrl-d"
        elif first >= 32 and first <= 126:
            return "char:" + chr(first)
        elif first >= 194 and first <= 244:
            count = 2
            if first >= 240:
                count = 4
            elif first >= 224:
                count = 3
            end
            encoded = __lsl_byte_zeros(count)
            encoded[0] = first
            for index in rang(1, count):
                byte = self.read_byte(50)
                if byte < 128 or byte > 191:
                    return "code:" + String(first)
                end
                encoded[index] = byte
            end
            return "char:" + __lsl_text_from_bytes(encoded, 0, count)
        end
        return "code:" + String(first)
    end
end

# Convenience constructor.
function open():
    return Terminal()
end

# Pad or truncate `text` to exactly `width` columns (space padded on the right).
function fit(text, width):
    length = len(text)
    if length == width:
        return text
    end
    if length > width:
        return text[0:width]
    end
    padding = ""
    i = length
    while i < width:
        padding = padding + " "
        i = i + 1
    end
    return text + padding
end
