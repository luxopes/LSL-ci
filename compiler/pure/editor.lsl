# lsl --tui: a small modal text editor for LSL sources in the terminal, in
# the spirit of Vim. Normal mode moves and edits, insert mode types, ":"
# runs commands (:w, :q, :q!, :wq, :w FILE) and "/" searches. Lines are
# coloured with the same highlighter as the interactive prompt. The whole
# editor is pure LSL over the tui toolkit; nothing is executed or spawned.
load console
load fd
load highlight
load tui

TERMINAL = tui.Terminal()
UNDO_LIMIT = 200
FILE_LIMIT = 4194304

function clamp(value, low, high):
    return max(low, min(high, __lsl_typed_int(value)))
end

function new_state(path):
    return {"lines": [""], "row": 0, "col": 0, "top": 0, "left": 0, "mode": "normal", "path": path, "modified": False, "message": "", "pending": "", "yank": [], "undo": [], "search": "", "quit": False}
end

function load_file(state, path):
    if path == None or path == "":
        state["message"] = "New file. :w FILE saves, :q quits, i inserts, Esc returns to normal mode."
        return None
    end
    if exists(path):
        text = fd.read_text_limit(path, FILE_LIMIT)
        lines = String(text).split(chr(10))
        if len(lines) > 1 and lines[len(lines) - 1] == "":
            lines = lines[0:len(lines) - 1]
        end
        if len(lines) == 0:
            lines = [""]
        end
        state["lines"] = lines
        state["message"] = "\"" + path + "\" " + String(len(lines)) + " lines"
    else:
        state["message"] = "\"" + path + "\" [New File]"
    end
    return None
end

function save_file(state, path):
    if path == None or path == "":
        state["message"] = "No file name. Use :w FILE."
        return False
    end
    text = chr(10).join(state["lines"]) + chr(10)
    try:
        call writefile(path, text)
    else:
        state["message"] = "Cannot write " + console.clean(path) + ": " + String(last_error())
        return False
    end
    state["path"] = path
    state["modified"] = False
    state["message"] = "\"" + console.clean(path) + "\" " + String(len(state["lines"])) + " lines written"
    return True
end

# Snapshot before a change; undo restores the previous snapshot.
function remember(state):
    undo = state["undo"]
    undo.append([List(state["lines"]), state["row"], state["col"]])
    if len(undo) > UNDO_LIMIT:
        undo.pop(0)
    end
    state["modified"] = True
end

function undo(state):
    undo = state["undo"]
    if len(undo) == 0:
        state["message"] = "Already at oldest change"
        return None
    end
    snapshot = undo.pop()
    state["lines"] = snapshot[0]
    state["row"] = clamp(snapshot[1], 0, len(state["lines"]) - 1)
    state["col"] = clamp(snapshot[2], 0, len(state["lines"][state["row"]]))
    state["message"] = String(len(undo)) + " changes left"
    return None
end

function current_line(state):
    return String(state["lines"][state["row"]])
end

function set_line(state, text):
    lines = state["lines"]
    lines[state["row"]] = text
end

function leading_spaces(text):
    count = 0
    while count < len(text) and text[count] == " ":
        count += 1
    end
    return count
end

function is_word(character):
    code = ord(character)
    return (code >= 97 and code <= 122) or (code >= 65 and code <= 90) or (code >= 48 and code <= 57) or code == 95
end

function move_word_forward(state):
    line = current_line(state)
    col = state["col"]
    while col < len(line) and is_word(line[col]):
        col += 1
    end
    while col < len(line) and not is_word(line[col]):
        col += 1
    end
    if col >= len(line) and state["row"] + 1 < len(state["lines"]):
        state["row"] += 1
        state["col"] = leading_spaces(current_line(state))
    else:
        state["col"] = col
    end
end

function move_word_back(state):
    line = current_line(state)
    col = state["col"]
    if col == 0:
        if state["row"] > 0:
            state["row"] -= 1
            state["col"] = len(current_line(state))
        end
        return None
    end
    col -= 1
    while col > 0 and not is_word(line[col]):
        col -= 1
    end
    while col > 0 and is_word(line[col - 1]):
        col -= 1
    end
    state["col"] = col
    return None
end

function clamp_cursor(state, insert):
    lines = state["lines"]
    state["row"] = clamp(state["row"], 0, len(lines) - 1)
    limit = len(current_line(state))
    if not insert and limit > 0:
        limit -= 1
    end
    state["col"] = clamp(state["col"], 0, limit)
end

function insert_text(state, text):
    line = current_line(state)
    col = state["col"]
    call set_line(state, line[0:col] + text + line[col:len(line)])
    state["col"] = col + len(text)
end

function split_line(state):
    line = current_line(state)
    col = state["col"]
    indent = line[0:leading_spaces(line)]
    call set_line(state, line[0:col])
    state["lines"].insert(state["row"] + 1, indent + line[col:len(line)])
    state["row"] += 1
    state["col"] = len(indent)
end

function backspace(state):
    line = current_line(state)
    col = state["col"]
    if col > 0:
        call set_line(state, line[0:col - 1] + line[col:len(line)])
        state["col"] = col - 1
    elif state["row"] > 0:
        previous = String(state["lines"][state["row"] - 1])
        state["lines"].pop(state["row"])
        state["row"] -= 1
        call set_line(state, previous + line)
        state["col"] = len(previous)
    end
end

function delete_at_cursor(state):
    line = current_line(state)
    col = state["col"]
    if col < len(line):
        call set_line(state, line[0:col] + line[col + 1:len(line)])
    end
end

function delete_line(state):
    lines = state["lines"]
    state["yank"] = [current_line(state)]
    lines.pop(state["row"])
    if len(lines) == 0:
        lines.append("")
    end
    call clamp_cursor(state, False)
end

function paste(state, below):
    if len(state["yank"]) == 0:
        state["message"] = "Nothing yanked"
        return None
    end
    call remember(state)
    target = state["row"]
    if below:
        target += 1
    end
    offset = 0
    for text in state["yank"]:
        state["lines"].insert(target + offset, text)
        offset += 1
    end
    state["row"] = target
    state["col"] = 0
    return None
end

function find_next(state, from_row, from_col):
    query = String(state["search"])
    if query == "":
        state["message"] = "No previous search"
        return False
    end
    lines = state["lines"]
    count = len(lines)
    for offset in rang(count + 1):
        row = (from_row + offset) % count
        text = String(lines[row])
        start = 0
        if offset == 0:
            start = from_col + 1
        end
        if start <= len(text):
            position = text[start:len(text)].find(query)
            if position >= 0:
                state["row"] = row
                state["col"] = start + position
                state["message"] = "/" + query
                return True
            end
        end
    end
    state["message"] = "Pattern not found: " + query
    return False
end

# Read a ":" or "/" line on the bottom row; None when cancelled.
function read_command(prefix):
    term = TERMINAL
    value = ""
    loop:
        call term.move(term.rows, 1)
        call term.clear_line()
        call term.emit(tui.fit(prefix + value, max(1, term.cols - 1)))
        call term.flush()
        key = term.read_key()
        if key == "enter":
            return value
        elif key == "esc" or key == "ctrl-c" or key == "none":
            return None
        elif key == "backspace":
            if len(value) == 0:
                return None
            end
            value = value[0:len(value) - 1]
        elif key.startswith("char:") and len(value) < 500:
            value += key[5:len(key)]
        end
    end
end

function run_command(state, command):
    words = String(command).strip().split(" ")
    name = words[0]
    argument = ""
    if len(words) > 1:
        argument = " ".join(words[1:len(words)]).strip()
    end
    if name == "w" or name == "write":
        target = state["path"]
        if argument != "":
            target = argument
        end
        call save_file(state, target)
    elif name == "wq" or name == "x":
        target = state["path"]
        if argument != "":
            target = argument
        end
        if save_file(state, target):
            state["quit"] = True
        end
    elif name == "q" or name == "quit":
        if state["modified"]:
            state["message"] = "No write since last change (add ! to override)"
        else:
            state["quit"] = True
        end
    elif name == "q!" or name == "quit!":
        state["quit"] = True
    elif name == "":
        state["message"] = ""
    else:
        state["message"] = "Not an editor command: " + console.clean(command)
    end
end

function handle_insert(state, key):
    if key == "esc":
        state["mode"] = "normal"
        if state["col"] > 0:
            state["col"] -= 1
        end
        call clamp_cursor(state, False)
    elif key == "enter":
        call remember(state)
        call split_line(state)
    elif key == "backspace":
        call remember(state)
        call backspace(state)
    elif key == "delete":
        call remember(state)
        call delete_at_cursor(state)
    elif key == "tab":
        call remember(state)
        call insert_text(state, "    ")
    elif key.startswith("char:"):
        call remember(state)
        call insert_text(state, key[5:len(key)])
    else:
        call handle_motion(state, key, True)
    end
end

# Shared cursor keys; returns True when the key was a motion.
function handle_motion(state, key, insert):
    lines = state["lines"]
    if key == "left" or (not insert and key == "char:h"):
        state["col"] -= 1
    elif key == "right" or (not insert and key == "char:l"):
        state["col"] += 1
    elif key == "up" or (not insert and key == "char:k"):
        state["row"] -= 1
    elif key == "down" or (not insert and key == "char:j"):
        state["row"] += 1
    elif key == "home" or (not insert and key == "char:0"):
        state["col"] = 0
    elif key == "end" or (not insert and key == "char:$"):
        state["col"] = len(current_line(state))
    elif key == "pageup":
        state["row"] -= max(1, TERMINAL.rows - 3)
    elif key == "pagedown":
        state["row"] += max(1, TERMINAL.rows - 3)
    else:
        return False
    end
    call clamp_cursor(state, insert)
    return True
end

function handle_normal(state, key):
    pending = state["pending"]
    state["pending"] = ""
    if pending == "d":
        if key == "char:d":
            call remember(state)
            call delete_line(state)
        end
        return None
    elif pending == "y":
        if key == "char:y":
            state["yank"] = [current_line(state)]
            state["message"] = "1 line yanked"
        end
        return None
    elif pending == "g":
        if key == "char:g":
            state["row"] = 0
            state["col"] = 0
        end
        return None
    end
    if handle_motion(state, key, False):
        return None
    elif key == "char:i":
        state["mode"] = "insert"
    elif key == "char:a":
        state["mode"] = "insert"
        if len(current_line(state)) > 0:
            state["col"] += 1
        end
    elif key == "char:A":
        state["mode"] = "insert"
        state["col"] = len(current_line(state))
    elif key == "char:I":
        state["mode"] = "insert"
        state["col"] = leading_spaces(current_line(state))
    elif key == "char:o" or key == "char:O":
        call remember(state)
        indent = current_line(state)[0:leading_spaces(current_line(state))]
        target = state["row"]
        if key == "char:o":
            target += 1
        end
        state["lines"].insert(target, indent)
        state["row"] = target
        state["col"] = len(indent)
        state["mode"] = "insert"
    elif key == "char:x":
        call remember(state)
        call delete_at_cursor(state)
        call clamp_cursor(state, False)
    elif key == "char:d" or key == "char:y" or key == "char:g":
        state["pending"] = key[5:6]
    elif key == "char:G":
        state["row"] = len(state["lines"]) - 1
        state["col"] = 0
    elif key == "char:w":
        call move_word_forward(state)
        call clamp_cursor(state, False)
    elif key == "char:b":
        call move_word_back(state)
    elif key == "char:p":
        call paste(state, True)
    elif key == "char:P":
        call paste(state, False)
    elif key == "char:u":
        call undo(state)
    elif key == "char:n":
        call find_next(state, state["row"], state["col"])
    elif key == "char:/":
        query = read_command("/")
        if query != None and query != "":
            state["search"] = query
            call find_next(state, state["row"], state["col"])
        end
    elif key == "char::":
        command = read_command(":")
        if command != None:
            call run_command(state, command)
        end
    elif key == "ctrl-c":
        state["message"] = "Type :q to quit (or :q! to discard changes)"
    end
    return None
end

function render(state):
    term = TERMINAL
    call term.query_size()
    lines = state["lines"]
    text_rows = max(1, term.rows - 2)
    number_width = max(3, len(String(len(lines))))
    text_width = max(1, term.cols - number_width - 2)
    state["top"] = clamp(state["top"], 0, max(0, len(lines) - 1))
    if state["row"] < state["top"]:
        state["top"] = state["row"]
    elif state["row"] >= state["top"] + text_rows:
        state["top"] = state["row"] - text_rows + 1
    end
    if state["col"] < state["left"]:
        state["left"] = state["col"]
    elif state["col"] >= state["left"] + text_width:
        state["left"] = state["col"] - text_width + 1
    end
    left = state["left"]
    colors = console.colors()
    call term.clear()
    for screen_row in rang(text_rows):
        index = state["top"] + screen_row
        call term.move(screen_row + 1, 1)
        if index >= len(lines):
            if colors:
                call term.set_fg(tui.color_blue)
            end
            call term.emit("~")
            call term.reset_style()
            continue
        end
        number = String(index + 1)
        while len(number) < number_width:
            number = " " + number
        end
        if colors:
            call term.emit(chr(27) + "[2m")
        end
        call term.emit(number + " ")
        call term.reset_style()
        line = console.clean(String(lines[index]))
        visible = line[min(len(line), left):min(len(line), left + text_width)]
        if colors:
            # Highlight the whole line, then keep only the visible window.
            column = 0
            for item in highlight.spans(line):
                piece = String(item[0])
                start = max(0, left - column)
                stop = min(len(piece), left + text_width - column)
                if stop > start:
                    if item[1] != "":
                        call term.emit(chr(27) + "[" + String(item[1]) + "m" + piece[start:stop] + chr(27) + "[0m")
                    else:
                        call term.emit(piece[start:stop])
                    end
                end
                column += len(piece)
            end
        else:
            call term.emit(visible)
        end
    end
    mode = "NORMAL"
    if state["mode"] == "insert":
        mode = "INSERT"
    end
    name = "[No Name]"
    if state["path"] != None and state["path"] != "":
        name = console.clean(state["path"])
    end
    flag = ""
    if state["modified"]:
        flag = " [+]"
    end
    position = String(state["row"] + 1) + ":" + String(state["col"] + 1)
    status = " " + mode + "  " + name + flag
    while len(status) + len(position) + 2 < term.cols:
        status += " "
    end
    status += position + " "
    call term.move(term.rows - 1, 1)
    call term.clear_line()
    call term.invert()
    call term.emit(tui.fit(status, max(1, term.cols - 1)))
    call term.reset_style()
    call term.move(term.rows, 1)
    call term.clear_line()
    call term.emit(tui.fit(console.clean(state["message"]), max(1, term.cols - 1)))
    call term.move(state["row"] - state["top"] + 1, number_width + 2 + state["col"] - left)
    call term.emit(chr(27) + "[?25h")
    call term.flush()
end

function edit_loop(state):
    term = TERMINAL
    loop:
        call render(state)
        key = term.read_key()
        if key == "none":
            return None
        end
        if state["mode"] == "insert":
            call handle_insert(state, key)
        else:
            call handle_normal(state, key)
        end
        if state["quit"]:
            return None
        end
    end
end

# Entry point for lsl --tui [FILE].
function edit(path):
    call console.require_terminal()
    state = new_state(path)
    call load_file(state, path)
    term = TERMINAL
    failure = None
    try:
        call term.enter()
        call edit_loop(state)
    else:
        failure = last_error()
    end
    call term.leave()
    if failure != None:
        Error(TUIError: String(failure))
    end
end
