# The same Markdown chapters as https://lsl.lux-ai.cz/, shipped offline.
load console
load fd

function pages():
    return [
        ["README", "Obsah a rozcestnik"],
        ["01-getting-started", "01. Zaciname s LSL"],
        ["02-language-basics", "02. Zaklady jazyka"],
        ["03-functions-and-classes", "03. Funkce a tridy"],
        ["04-collections", "04. Kolekce a datove struktury"],
        ["05-error-handling", "05. Zpracovani chyb"],
        ["06-modules-and-imports", "06. Moduly a standardni knihovny"],
        ["07-files-io-and-processes", "07. Soubory, I/O a procesy"],
        ["08-configuration-system", "08. Konfiguracni system"],
        ["09-gui-programming", "09. GUI programovani"],
        ["10-ai-applications", "10. AI aplikace"],
        ["11-performance-and-optimization", "11. Vykon a optimalizace"],
        ["12-compiler-internals", "12. Interni architektura compileru"],
        ["13-server-and-origin", "13. Server a puvod knihoven"],
        ["14-sandbox-and-safety", "14. Sandbox a bezpecnost"],
        ["15-cuda", "15. CUDA a GPU tenzory"],
        ["16-random", "16. Random"],
        ["17-cli-and-packages", "17. CLI, balicky a terminalovy manual"],
        ["reference", "Kompletni reference funkci"],
        ["security", "Bezpecnostni model"],
        ["CHANGELOG", "Historie zmen"]
    ]
end

function resolve(topic):
    topic = String(topic).lower()
    matches = []
    for page in pages():
        if String(page[0]).lower() == topic:
            return page
        elif topic in String(page[0]).lower() or topic in String(page[1]).lower():
            matches.append(page)
        end
    end
    if len(matches) == 1:
        return matches[0]
    elif len(matches) == 0:
        Error(ManualError: "manual topic not found; use lsl man --plain for the contents")
    end
    Error(ManualError: "ambiguous manual topic; use the full chapter ID")
end

function content(root, page):
    # Only fixed chapter IDs are used as paths, never arbitrary user strings.
    known = False
    for item in pages():
        if item[0] == page[0]:
            known = True
        end
    end
    if not known:
        Error(ManualError: "invalid manual chapter")
    end
    return fd.read_text_limit(root + "/" + page[0] + ".md", 1048576)
end

function lines(text, width):
    width = max(1, __lsl_typed_int(width))
    result = []
    for raw in String(text).split(chr(10)):
        line = console.clean(raw.replace(chr(9), "    "))
        if line == "":
            result.append("")
        end
        while len(line) > 0:
            take = min(len(line), width)
            result.append(line[0:take])
            line = line[take:len(line)]
        end
    end
    return result
end

# --- Markdown rendering -------------------------------------------------------
# A rendered line is a List of spans [text, style]; style is an SGR code or "".
# Headings, lists, code fences, tables, inline code, bold and links become
# terminal formatting instead of raw markup. Wrapping happens per span, so
# styles survive line breaks.

function span(text, style):
    return [text, style]
end

function text_of(spans):
    parts = []
    for item in spans:
        parts.append(item[0])
    end
    return "".join(parts)
end

function trimmed_cell(text):
    return String(text).strip()
end

# String.find takes no start offset; search the tail and translate the index.
function find_from(text, needle, start):
    position = String(text)[start:len(text)].find(needle)
    if position < 0:
        return -1
    end
    return position + start
end

# Inline markup: `code`, **bold**, [text](url). Other characters pass through.
function inline(text, base_style):
    result = []
    literal = []
    index = 0
    count = len(text)
    while index < count:
        character = text[index]
        if character == "`":
            closing = find_from(text, "`", index + 1)
            if closing > index:
                if len(literal) > 0:
                    result.append(span("".join(literal), base_style))
                    literal = []
                end
                result.append(span(text[index + 1:closing], "33"))
                index = closing + 1
                continue
            end
        elif character == "*" and index + 1 < count and text[index + 1] == "*":
            closing = find_from(text, "**", index + 2)
            if closing > index:
                if len(literal) > 0:
                    result.append(span("".join(literal), base_style))
                    literal = []
                end
                result.extend(inline(text[index + 2:closing], "1"))
                index = closing + 2
                continue
            end
        elif character == "[":
            closing = find_from(text, "](", index + 1)
            finish = -1
            if closing > index:
                finish = find_from(text, ")", closing + 2)
            end
            if closing > index and finish > closing:
                if len(literal) > 0:
                    result.append(span("".join(literal), base_style))
                    literal = []
                end
                label = text[index + 1:closing]
                url = text[closing + 2:finish]
                result.extend(inline(label, base_style))
                if url.startswith("http://") or url.startswith("https://"):
                    result.append(span(" (" + url + ")", "2"))
                end
                index = finish + 1
                continue
            end
        end
        literal.append(character)
        index += 1
    end
    if len(literal) > 0:
        result.append(span("".join(literal), base_style))
    end
    return result
end

function table_cells(line):
    cells = []
    for piece in String(line).split("|"):
        cells.append(trimmed_cell(piece))
    end
    if len(cells) > 0 and cells[0] == "":
        cells = cells[1:len(cells)]
    end
    if len(cells) > 0 and cells[len(cells) - 1] == "":
        cells = cells[0:len(cells) - 1]
    end
    return cells
end

function separator_row(cells):
    if len(cells) == 0:
        return False
    end
    for cell in cells:
        for character in cell:
            if character != "-" and character != ":":
                return False
            end
        end
    end
    return True
end

function pad_text(text, width):
    result = String(text)
    while len(result) < width:
        result += " "
    end
    return result
end

# Rows of a Markdown table as span lines: header bold, columns aligned.
function render_table(rows):
    parsed = []
    header = True
    for row in rows:
        cells = table_cells(row)
        if separator_row(cells):
            continue
        end
        parsed.append([cells, header])
        header = False
    end
    widths = []
    for entry in parsed:
        cells = entry[0]
        for index in rang(len(cells)):
            plain_text = text_of(inline(cells[index], ""))
            if index >= len(widths):
                widths.append(0)
            end
            widths[index] = min(48, max(widths[index], len(plain_text)))
        end
    end
    result = []
    for entry in parsed:
        cells = entry[0]
        style = ""
        if entry[1]:
            style = "1"
        end
        spans = []
        for index in rang(len(widths)):
            cell = ""
            if index < len(cells):
                cell = cells[index]
            end
            rendered = inline(cell, style)
            plain_text = text_of(rendered)
            spans.extend(rendered)
            spans.append(span(pad_text("", max(0, widths[index] - len(plain_text))), ""))
            if index + 1 < len(widths):
                spans.append(span(" │ ", "2"))
            end
        end
        result.append(spans)
    end
    return result
end

# Hard-wrap a span line at width, keeping every span's style.
function wrap_spans(spans, width):
    lines = []
    current = []
    used = 0
    for item in spans:
        text = String(item[0])
        style = item[1]
        while len(text) > 0:
            room = width - used
            if room <= 0:
                lines.append(current)
                current = []
                used = 0
                room = width
            end
            take = min(len(text), room)
            current.append(span(text[0:take], style))
            used += take
            text = text[take:len(text)]
        end
    end
    if len(current) > 0 or len(lines) == 0:
        lines.append(current)
    end
    return lines
end

# Render Markdown text into wrapped span lines for a terminal of `width`.
function render(text, width):
    width = max(8, __lsl_typed_int(width))
    result = []
    code = False
    table = []
    for raw in String(text).split(chr(10)):
        line = console.clean(String(raw).replace(chr(9), "    "))
        if line.strip().startswith("```"):
            if len(table) > 0:
                result.extend(render_table(table))
                table = []
            end
            code = not code
            continue
        end
        if code:
            result.extend(wrap_spans([span("    " + line, "32")], width))
            continue
        end
        stripped = line.strip()
        if stripped.startswith("|"):
            table.append(line)
            continue
        elif len(table) > 0:
            result.extend(render_table(table))
            table = []
        end
        if stripped == "":
            result.append([])
        elif stripped.startswith("#"):
            level = 0
            while level < len(stripped) and stripped[level] == "#":
                level += 1
            end
            title = stripped[level:len(stripped)].strip()
            prefix = ""
            if level >= 3:
                prefix = "  "
            end
            result.extend(wrap_spans([span(prefix, ""), span(text_of(inline(title, "")), "1;36")], width))
        elif stripped == "---" or stripped == "***":
            result.append([span(pad_text("", min(width, 40)).replace(" ", "─"), "2")])
        elif stripped.startswith("- ") or stripped.startswith("* "):
            indent = len(line) - len(line.lstrip())
            spans = [span(pad_text("", indent) + "• ", "36")]
            spans.extend(inline(stripped[2:len(stripped)], ""))
            result.extend(wrap_spans(spans, width))
        elif stripped.startswith("> "):
            spans = [span("│ ", "2")]
            spans.extend(inline(stripped[2:len(stripped)], "2"))
            result.extend(wrap_spans(spans, width))
        else:
            indent = len(line) - len(line.lstrip())
            spans = [span(pad_text("", indent), "")]
            spans.extend(inline(stripped, ""))
            result.extend(wrap_spans(spans, width))
        end
    end
    if len(table) > 0:
        result.extend(render_table(table))
    end
    return result
end

function styled_line(spans):
    parts = []
    for item in spans:
        if item[1] == "":
            parts.append(String(item[0]))
        else:
            parts.append(console.style(item[0], item[1]))
        end
    end
    return "".join(parts)
end

function find_line(lines, query, start):
    if len(lines) == 0 or query == "":
        return -1
    end
    for offset in rang(len(lines)):
        index = (__lsl_typed_int(start) + offset) % len(lines)
        if String(query).lower() in String(lines[index]).lower():
            return index
        end
    end
    return -1
end

function plain(root, topic):
    if topic == None:
        print "LSL manual (offline copy of https://lsl.lux-ai.cz/)"
        for page in pages():
            print page[0] + "  " + page[1]
        end
        print "Read a chapter: lsl man --plain TOPIC"
    else:
        text = content(root, resolve(topic))
        for spans in render(text, 100):
            print styled_line(spans)
        end
    end
end
