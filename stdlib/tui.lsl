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
    command = os.which_trusted("stty")
    if command == None:
        Error(TUIError: "trusted stty executable is unavailable")
    end
    return command
end

class Terminal(True):
    ctype Public

    function init(self):
        self.saved = ""
        self.rows = 24
        self.cols = 80
        self.inbuf = __lsl_byte_zeros(32)
        self.out = ByteArray()
    end

    # Enter cbreak + alternate screen. Saves the current stty state so leave()
    # can restore it exactly.
    function enter(self):
        command = stty_tool()
        self.saved = os.capture_argv_clean(command, ["-g"]).strip()
        if capture_status() != 0 or len(self.saved) == 0 or len(self.saved) > 4096 or chr(0) in self.saved:
            Error(TUIError: "cannot read terminal state")
        end
        if os.run_argv_clean(command, ["-echo", "-icanon", "min", "1", "time", "0"]) != 0:
            Error(TUIError: "cannot enter terminal raw mode")
        end
        call self.query_size()
        call self.emit(ESC + "[?1049h" + ESC + "[?25l" + ESC + "[2J")
        call self.flush()
        return None
    end

    # Restore the terminal: show cursor, leave the alternate screen, restore the
    # saved stty state. Safe to call more than once.
    function leave(self):
        call self.emit(ESC + "[?25h" + ESC + "[?1049l")
        call self.flush()
        if self.saved != "":
            if os.run_argv_clean(stty_tool(), [self.saved]) != 0:
                Error(TUIError: "cannot restore terminal state")
            end
        end
        return None
    end

    # Read the terminal size (rows, cols) via `stty size`.
    function query_size(self):
        size = os.capture_argv_clean(stty_tool(), ["size"]).strip()
        parts = size.split(" ")
        if capture_status() == 0 and len(parts) == 2:
            rows = Int(parts[0])
            cols = Int(parts[1])
            if rows >= 1 and rows <= 10000 and cols >= 1 and cols <= 10000:
                self.rows = rows
                self.cols = cols
            end
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

    # Block until a key is available, returning a normalized key string.
    function read_key(self):
        buffer = ByteArray(self.inbuf)
        count = fd.read(0, buffer, 8)
        if count <= 0:
            return "none"
        end
        first = buffer[0]
        if first == 27:
            if count == 1:
                return "esc"
            end
            second = buffer[1]
            if second == 91 or second == 79:
                if count < 3:
                    return "esc"
                end
                third = buffer[2]
                if third == 65:
                    return "up"
                end
                if third == 66:
                    return "down"
                end
                if third == 67:
                    return "right"
                end
                if third == 68:
                    return "left"
                end
                if third == 72:
                    return "home"
                end
                if third == 70:
                    return "end"
                end
                if third == 53:
                    return "pageup"
                end
                if third == 54:
                    return "pagedown"
                end
                if third == 51:
                    return "delete"
                end
            end
            return "esc"
        end
        if first == 13 or first == 10:
            return "enter"
        end
        if first == 127 or first == 8:
            return "backspace"
        end
        if first == 9:
            return "tab"
        end
        if first == 3:
            return "ctrl-c"
        end
        if first == 4:
            return "ctrl-d"
        end
        if first >= 32 and first <= 126:
            return "char:" + chr(first)
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
