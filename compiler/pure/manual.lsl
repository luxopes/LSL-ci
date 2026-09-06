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
        for line in text.split(chr(10)):
            print console.clean(line)
        end
    end
end
