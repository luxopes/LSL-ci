# Keyboard-driven package manager and offline manual, entirely in LSL.
load catalog
load console
load manual
load tui

# The frontend uses the compiler's internal ABI (no parameter specialization).
# Keep the single terminal owner statically typed at module scope.
TERMINAL = tui.Terminal()

function clamp(value, size):
    return max(0, min(__lsl_typed_int(value), max(0, __lsl_typed_int(size) - 1)))
end

function row(number, text, selected):
    term = TERMINAL
    call term.move(number, 1)
    call term.clear_line()
    if selected:
        call term.invert()
    end
    call term.emit(tui.fit(console.clean(text), max(1, term.cols - 1)))
    call term.reset_style()
end

function frame(title, footer, status):
    term = TERMINAL
    call gc()
    call term.query_size()
    call term.clear()
    if console.colors():
        call term.set_fg(tui.color_cyan)
    end
    call term.bold()
    call row(1, title, False)
    call row(max(2, term.rows - 1), status, False)
    call row(max(3, term.rows), footer, False)
end

function navigation(key, selected, count, page_size):
    if key == "up" or key == "char:k":
        selected -= 1
    elif key == "down" or key == "char:j":
        selected += 1
    elif key == "pageup":
        selected -= page_size
    elif key == "pagedown":
        selected += page_size
    elif key == "home":
        selected = 0
    elif key == "end":
        selected = count - 1
    end
    return clamp(selected, count)
end

function prompt(title):
    term = TERMINAL
    value = ""
    loop:
        call row(max(3, term.rows), title + value + "_", False)
        call term.flush()
        key = term.read_key()
        if key == "enter":
            return value
        elif key == "esc" or key == "ctrl-c" or key == "ctrl-d" or key == "none":
            return None
        elif key == "backspace":
            value = value[0:max(0, len(value) - 1)]
        elif key.startswith("char:") and len(value) < 200:
            value += key[5:len(key)]
        end
    end
end

function package_loop(items, installed, lsl_path):
    term = TERMINAL
    visible = items
    selected = 0
    marked = {}
    message = "Space marks packages; i installs the selection after confirmation."
    query = ""
    loop:
        call frame("LSL packages | " + String(len(visible)) + " available | filter: " + query, "Up/Down  Space:mark  i:install  /:filter  Esc:clear  q:quit", message)
        page_size = max(1, term.rows - 4)
        selected = clamp(selected, len(visible))
        start = (selected // page_size) * page_size
        for index in rang(start, min(len(visible), start + page_size)):
            item = visible[index]
            name = item["name"]
            state = "available"
            found = catalog.find_installed(installed, name)
            if found != None:
                state = found["scope"]
            end
            marker = "[ ] "
            if name in marked:
                marker = "[*] "
            end
            call row(index - start + 3, marker + name + " " + item["version"] + " (" + state + ") " + item["description"], index == selected)
        end
        if len(visible) == 0:
            call row(3, "No matching packages. Press / to change the filter.", False)
        end
        call term.flush()
        key = term.read_key()
        if key == "char:q" or key == "ctrl-c" or key == "ctrl-d" or key == "none":
            return None
        elif key == "char:/":
            next_query = prompt("Filter (Enter confirms, Esc cancels): ")
            if next_query != None:
                query = next_query
                visible = catalog.search(items, query)
                selected = 0
            end
        elif key == "esc":
            query = ""
            visible = items
            selected = 0
        elif (key == "char: " or key == "enter") and len(visible) > 0:
            name = visible[selected]["name"]
            found = catalog.find_installed(installed, name)
            if found != None and found["scope"] == "bundled":
                message = name + " is bundled with LSL; update LSL to update it."
            elif name in marked:
                del(marked[name])
            else:
                marked[name] = True
            end
        elif key == "char:i":
            if len(marked) == 0:
                message = "Mark one or more packages with Space first."
                continue
            end
            call row(max(3, term.rows), "Install/reinstall " + String(len(marked)) + " selected packages? y confirms; any other key cancels", False)
            call term.flush()
            if term.read_key() != "char:y":
                message = "Installation cancelled; no packages changed."
                continue
            end
            for name in marked.keys():
                call row(max(2, term.rows - 1), "Installing " + name + " (download, SHA-256, compile, atomic install)...", False)
                call term.flush()
                # Preserve HOME/registry, use exact CLI argv, never a shell.
                output = capture(lsl_path, ["install", name])
                status = capture_status()
                if status == 0:
                    if catalog.find_installed(installed, name) == None:
                        installed.append({"name": name, "scope": "user", "path": ""})
                    end
                    del(marked[name])
                    message = "Installed " + name
                else:
                    message = "Failed " + name + ": " + console.clean(output + capture_stderr())
                    break
                end
            end
        else:
            selected = navigation(key, selected, len(visible), page_size)
        end
    end
end

function packages(items, installed, lsl_path):
    call console.require_terminal()
    term = TERMINAL
    failure = None
    try:
        call term.enter()
        call package_loop(items, installed, lsl_path)
    else:
        failure = last_error()
    end
    call term.leave()
    if failure != None:
        Error(TUIError: String(failure))
    end
end

function manual_loop(root, topic):
    term = TERMINAL
    chapters = manual.pages()
    selected = 0
    page = None
    content = ""
    top = 0
    query = ""
    message = "Offline manual from lsl.lux-ai.cz; Enter opens a chapter."
    if topic != None:
        page = manual.resolve(topic)
        content = manual.content(root, page)
    end
    loop:
        title = "LSL manual | Contents"
        footer = "Up/Down:scroll  Enter:open  /:search  q:quit"
        if page != None:
            title = "LSL manual | " + page[1]
            footer = "Up/Down/PgUp/PgDn  /:find  n:next  Esc:contents  q:quit"
        end
        call frame(title, footer, message)
        page_size = max(1, term.rows - 4)
        if page == None:
            start = (selected // page_size) * page_size
            for index in rang(start, min(len(chapters), start + page_size)):
                call row(index - start + 3, chapters[index][1], index == selected)
            end
        else:
            lines = manual.lines(content, max(1, term.cols - 1))
            top = clamp(top, len(lines))
            for index in rang(top, min(len(lines), top + page_size)):
                if String(lines[index]).startswith("#"):
                    call term.bold()
                    if console.colors():
                        call term.set_fg(tui.color_cyan)
                    end
                end
                call row(index - top + 3, lines[index], query != "" and String(query).lower() in String(lines[index]).lower())
            end
        end
        call term.flush()
        key = term.read_key()
        if key == "char:q" or key == "ctrl-c" or key == "ctrl-d" or key == "none":
            return None
        elif page == None:
            if key == "enter":
                page = chapters[selected]
                content = manual.content(root, page)
                top = 0
                query = ""
                message = "Esc returns to the contents. / searches this chapter."
            elif key == "char:/":
                topic_query = prompt("Find chapter: ")
                if topic_query != None and topic_query != "":
                    titles = [chapter[1] + " " + chapter[0] for chapter in chapters]
                    found = manual.find_line(titles, topic_query, selected + 1)
                    if found >= 0:
                        selected = found
                    else:
                        message = "Chapter not found: " + topic_query
                    end
                end
            else:
                selected = navigation(key, selected, len(chapters), page_size)
            end
        elif key == "esc" or key == "backspace":
            page = None
            message = "Enter opens a chapter."
        elif key == "char:/" or key == "char:n":
            if key == "char:/":
                next_query = prompt("Find text: ")
                if next_query != None:
                    query = next_query
                end
            end
            found = manual.find_line(lines, query, top + 1)
            if found >= 0:
                top = found
                message = "Match: " + query + " | n finds next (wraps at end)"
            else:
                message = "Text not found: " + query
            end
        else:
            top = navigation(key, top, len(lines), page_size)
        end
    end
end

function manual_view(root, topic):
    call console.require_terminal()
    term = TERMINAL
    failure = None
    try:
        call term.enter()
        call manual_loop(root, topic)
    else:
        failure = last_error()
    end
    call term.leave()
    if failure != None:
        Error(TUIError: String(failure))
    end
end
