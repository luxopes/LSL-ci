# lsl: internal-abi
# Public pure-LSL command frontend.

load codegen
load editor
load fd
load highlight
load browser
load catalog
load console
load httpserver
load linker
load manual
load os
load package
load parser
load sandbox
load tui
load update

VERSION = "0.8.8"

function print_help():
    call console.heading("Lux Simple Lang (LSL) " + VERSION)
    print ""
    print "Usage:"
    print "  lsl [SOURCE [ARG...]]"
    print "  lsl compile [--unsafe] SOURCE OUTPUT"
    print "  lsl config ENTRY"
    print "  lsl install NAME"
    print "  lsl install --config FILE"
    print "  lsl install --tui"
    print "  lsl list"
    print "  lsl search [QUERY]"
    print "  lsl check NAME"
    print "  lsl man [--plain] [TOPIC]"
    print "  lsl help [TOPIC]"
    print "  lsl about [NAME]"
    print "  lsl --tui [FILE]"
    print "  lsl update [NAME]"
    print "  lsl update [--check | --rollback] [--system] [--allow-downgrade]"
    print "  lsl origin [NAME]"
    print "  lsl server [OPTIONS]"
    print "  lsl sandbox [OPTIONS] SOURCE [ARG...]"
    print "  lsl version"
    print ""
    print "Options:"
    print "  -h, --help     Show this help"
    print "  --version      Show version"
    print "  NO_COLOR       Disable automatic terminal colors (environment variable)"
end

function print_server_help():
    print "Usage: lsl server [OPTIONS]"
    print ""
    print "Serve static files from a pinned directory. HTTP is implemented by LSL;"
    print "HTTPS uses the maintained system nginx/OpenSSL TLS stack."
    print ""
    print "Options:"
    print "  --dir ROOT          Document root (default: .)"
    print "  --bind IPV4         Numeric bind address (default: 127.0.0.1)"
    print "  --port PORT         TCP port (default: 8080)"
    print "  --once              Stop native HTTP after one request"
    print "  --max-requests N    Stop native HTTP after N requests; 0 is unlimited"
    print "  --tls-cert FILE     Enable HTTPS with this PEM certificate"
    print "  --tls-key FILE      PEM private key paired with --tls-cert"
    print "  -h, --help          Show this help"
end

function print_sandbox_help():
    print "Usage: lsl sandbox [OPTIONS] SOURCE [ARG...]"
    print ""
    print "Compile SOURCE and run it in a short-lived capability sandbox."
    print "The strict profile has a private network namespace; server shares network."
    print ""
    print "Options:"
    print "  --profile NAME      strict (default) or server"
    print "  --timeout SECONDS   Wall/CPU limit, 1..3600 (default: 30)"
    print "  --memory BYTES      Address-space limit, 64 MiB..8 GiB (default: 1 GiB)"
    print "  --read PATH         Add read-only capability as /input/N (repeatable)"
    print "  --write PATH        Add writable capability as /output/N (repeatable)"
    print "  --                   End options; useful when SOURCE begins with -"
    print "  -h, --help          Show this help"
end

function decimal_option(value, minimum, maximum, label):
    text = String(value)
    if len(text) == 0 or len(text) > 19:
        Error(CliError: String(label) + " must be a decimal integer")
    end
    result = 0
    for character in text:
        code = ord(character)
        if code < 48 or code > 57:
            Error(CliError: String(label) + " must be a decimal integer")
        end
        digit = code - 48
        if result > (Int(maximum) - digit) // 10:
            Error(CliError: String(label) + " is outside the supported range")
        end
        result = result * 10 + digit
    end
    if result < Int(minimum) or result > Int(maximum):
        Error(CliError: String(label) + " is outside " + String(minimum) + ".." + String(maximum))
    end
    return result
end

function compile_image_mode(source_path, source, safety_mode):
    stdlib_name = "compiler/pure/dynamic_stdlib.lsl"
    stdlib_path = resource_path(stdlib_name)
    stdlib_source = readfile(stdlib_path)
    program = parser.parse(stdlib_name, stdlib_source)
    call linker.annotate_statements(program, stdlib_name)
    call linker.mark_internal_abi(program, True)
    if safety_mode == 0:
        program.extend(linker.link(source_path, source))
    else:
        if String(source).find("# lsl: unchecked-intarray") >= 0:
            Error(CompileError: "unchecked-intarray requires lsl compile --unsafe")
        end
        program.extend(linker.link_checked(source_path, source, safety_mode == 2))
    end
    return codegen.generate(source_path, source, program)
end

function compile_source_mode(source_path, source, output_path, safety_mode):
    call writebytes(output_path, compile_image_mode(source_path, source, safety_mode))
end

function compile_source(source_path, source, output_path):
    call compile_source_mode(source_path, source, output_path, 1)
end

function compile_file(source_path, output_path):
    call compile_source(source_path, readfile(source_path), output_path)
end

function compile_file_unsafe(source_path, output_path):
    call compile_source_mode(source_path, readfile(source_path), output_path, 0)
end

function compile_file_sandbox(source_path, output_path):
    call compile_source_mode(source_path, readfile(source_path), output_path, 2)
end

function compile_file_image(source_path, safety_mode):
    return compile_image_mode(source_path, readfile(source_path), safety_mode)
end

function dirname(path):
    slash = -1
    index = 0
    while index < len(path):
        if path[index] == "/":
            slash = index
        end
        index += 1
    end
    if slash < 0:
        return "."
    elif slash == 0:
        return "/"
    end
    return path[0:slash]
end

function resource_path(path):
    executable = executable_path()
    binary_directory = dirname(executable)
    root_candidate = binary_directory + "/" + path
    if exists(root_candidate):
        return root_candidate
    end
    root_candidate = dirname(dirname(dirname(executable))) + "/" + path
    if exists(root_candidate):
        return root_candidate
    end
    prefix = dirname(binary_directory)
    prefix_bin = prefix + "/bin"
    if prefix == "/":
        prefix_bin = "/bin"
    end
    if binary_directory == prefix_bin:
        return prefix + "/lib/lsl/" + path
    end
    # Repository fallback is last so an attacker-controlled working directory
    # cannot shadow resources beside an installed executable.
    return path
end

function tool_path(repository_path, installed_name):
    binary_directory = dirname(executable_path())
    adjacent = binary_directory + "/" + installed_name
    if exists(adjacent):
        return adjacent
    end
    prefix = dirname(binary_directory)
    prefix_bin = prefix + "/bin"
    if prefix == "/":
        prefix_bin = "/bin"
    end
    if binary_directory == prefix_bin:
        # An incomplete installation must not execute a same-named tool from
        # the caller's working directory.
        return adjacent
    end
    return repository_path
end

function required_system_tool(primary, fallback, label):
    if exists(primary):
        return primary
    elif exists(fallback):
        return fallback
    end
    Error(ProcessError: "trusted " + label + " executable is required")
end

function registry_server():
    server = __lsl_getenv("LSL_REGISTRY")
    if server == None or server == "":
        server = "https://lsl.lux-ai.cz/packages"
    end
    return package.normalize_server(server)
end

function user_home():
    home = __lsl_getenv("HOME")
    if home == None or home == "":
        Error(PackageError: "HOME is required for per-user library installation")
    end
    return home
end

# Scratch path for a compiled program. Atomic 0700 mkdir prevents other users
# from replacing the ELF between compilation and execution.
function scratch_program_path():
    process = String(__lsl_syscall(39, 0, 0, 0, 0))
    attempt = 0
    directory = "/tmp/lsl-program-" + process
    while __lsl_mkdir_private(directory) != 0:
        attempt += 1
        if attempt > 100:
            Error(FileError: "cannot create a private CLI scratch directory")
        end
        directory = "/tmp/lsl-program-" + process + "-" + String(attempt)
    end
    return directory + "/program"
end

function cleanup_program(path):
    call unlink(path)
    call rmdir(dirname(path))
end

function materialize_scratch(image):
    path = scratch_program_path()
    failure = None
    try:
        call writebytes(path, image)
    else:
        failure = last_error()
    end
    if failure != None:
        call cleanup_program(path)
        Error(FileError: failure)
    end
    return path
end

function cleanup_config_snapshots(directory):
    index = 0
    while index < 256:
        call unlink(directory + "/lsl_config_snapshot_" + String(index) + ".lsl")
        index += 1
    end
end

# Interactive prompt: raw-mode line editor with syntax colours, history and
# block-aware continuation prompts. Falls back to plain line input when the
# terminal cannot be switched (no stty) or stdin is not a terminal.
BLOCK_OPENERS = ["function", "if", "while", "for", "loop", "try", "safe", "unsafe", "class"]
# One statically typed terminal owner for the prompt (method calls need a
# typed receiver, so functions take it from this module-level binding).
PROMPT_TERMINAL = tui.Terminal()

function block_delta(line):
    words = String(line).strip().split(" ")
    first = words[0]
    if first == "end":
        return -1
    elif first in BLOCK_OPENERS and String(line).strip().endswith(":"):
        return 1
    end
    return 0
end

# Redraw the prompt line in place with the cursor at `cursor`.
function draw_prompt_line(prompt, buffer, cursor, colors):
    text = chr(13) + prompt + highlight.render(buffer, colors) + chr(27) + "[K"
    back = len(buffer) - cursor
    if back > 0:
        text += chr(27) + "[" + String(back) + "D"
    end
    bytes = ByteArray()
    for character in text:
        code = ord(character)
        if code < 128:
            call bytes.append(code)
        elif code < 2048:
            call bytes.append(192 + code // 64)
            call bytes.append(128 + code % 64)
        elif code < 65536:
            call bytes.append(224 + code // 4096)
            call bytes.append(128 + code // 64 % 64)
            call bytes.append(128 + code % 64)
        else:
            call bytes.append(240 + code // 262144)
            call bytes.append(128 + code // 4096 % 64)
            call bytes.append(128 + code // 64 % 64)
            call bytes.append(128 + code % 64)
        end
    end
    call fd.write(1, bytes, len(bytes))
end

# One edited line; None means end of input (Ctrl-D on an empty line).
function edit_line(prompt, initial, history, colors):
    term = PROMPT_TERMINAL
    buffer = String(initial)
    cursor = len(buffer)
    position = len(history)
    loop:
        call draw_prompt_line(prompt, buffer, cursor, colors)
        key = term.read_key()
        if key == "enter":
            print ""
            return buffer
        elif key == "none" or (key == "ctrl-d" and buffer.strip() == ""):
            print ""
            return None
        elif key == "ctrl-c":
            print "^C"
            buffer = String(initial)
            cursor = len(buffer)
        elif key == "backspace":
            if cursor > 0:
                buffer = buffer[0:cursor - 1] + buffer[cursor:len(buffer)]
                cursor -= 1
            end
        elif key == "delete":
            if cursor < len(buffer):
                buffer = buffer[0:cursor] + buffer[cursor + 1:len(buffer)]
            end
        elif key == "left":
            cursor = max(0, cursor - 1)
        elif key == "right":
            cursor = min(len(buffer), cursor + 1)
        elif key == "home":
            cursor = 0
        elif key == "end":
            cursor = len(buffer)
        elif key == "up" or key == "down":
            if key == "up" and position > 0:
                position -= 1
            elif key == "down" and position < len(history):
                position += 1
            end
            if position < len(history):
                buffer = String(history[position])
            else:
                buffer = String(initial)
            end
            cursor = len(buffer)
        elif key == "tab":
            buffer = buffer[0:cursor] + "    " + buffer[cursor:len(buffer)]
            cursor += 4
        elif key.startswith("char:") and len(buffer) < 4096:
            character = key[5:len(key)]
            buffer = buffer[0:cursor] + character + buffer[cursor:len(buffer)]
            cursor += 1
        end
    end
end

function read_interactive_source(stty):
    colors = console.colors()
    call console.heading("Lux Simple Lang " + VERSION + " interactive source mode")
    print console.style("Enter code; type exit on its own line (or press Ctrl-D) to compile and run. Ctrl-C clears the line.", "2")
    saved = os.capture_argv_clean(stty, ["-g"]).strip()
    if capture_status() != 0 or len(saved) == 0 or len(saved) > 4096:
        Error(CliError: "cannot read terminal state")
    end
    if os.run_argv_clean(stty, ["-echo", "-icanon", "min", "1", "time", "0"]) != 0:
        Error(CliError: "cannot enter terminal raw mode")
    end
    lines = []
    history = []
    total = 0
    depth = 0
    failure = None
    try:
        loop:
            prompt = console.style(">>> ", "1;36")
            indent = ""
            if depth > 0:
                prompt = console.style("... ", "36")
                indent = "    " * depth
            end
            line = edit_line(prompt, indent, history, colors)
            if line == None or line.strip() == "exit":
                break
            end
            if line.strip() != "":
                history.append(line)
            end
            total += __lsl_text_byte_length(String(line)) + 1
            if total > 4194304:
                Error(CompileError: "stdin source exceeds the 4 MiB compiler limit")
            end
            lines.append(line)
            depth = max(0, depth + block_delta(line))
        end
    else:
        failure = last_error()
    end
    call os.run_argv_clean(stty, [saved])
    if failure != None:
        Error(CliError: String(failure))
    end
    if len(lines) == 0:
        return ""
    end
    return chr(10).join(lines) + chr(10)
end

function read_stdin_source():
    lines = []
    total = 0
    terminal = __lsl_isatty(0)
    if terminal and __lsl_isatty(1) and __lsl_getenv("TERM") != "dumb":
        stty = os.which_trusted("stty")
        if stty != None:
            return read_interactive_source(stty)
        end
    end
    if terminal:
        print "Lux Simple Lang " + VERSION + " interactive source mode"
        print "Enter code; type exit on its own line to compile and run."
    end
    loop:
        prompt = ""
        if terminal:
            prompt = ">>> "
        end
        line = input(prompt)
        eof = __lsl_stdin_eof()
        if line == "exit":
            break
        elif eof and line == "":
            break
        end
        total += __lsl_text_byte_length(String(line)) + 1
        if total > 4194304:
            Error(CompileError: "stdin source exceeds the 4 MiB compiler limit")
        end
        lines.append(line)
        if eof:
            break
        end
    end
    if len(lines) == 0:
        return ""
    end
    return chr(10).join(lines) + chr(10)
end

function main():
    command = arg(1)
    if command == None:
        source = read_stdin_source()
        if source == "":
            exit(0)
        end
        scratch = materialize_scratch(compile_image_mode("<stdin>", source, 1))
        status = run(scratch, [])
        call cleanup_program(scratch)
        exit(status)
    end

    if command == "--tui":
        if arg(3) != None:
            print "usage: lsl --tui [FILE]"
            exit(2)
        end
        call editor.edit(arg(2))
        exit(0)
    end

    if arg(2) == "--help" or arg(2) == "-h":
        if command in ["compile", "config", "update", "origin", "version"]:
            print __lsl_help_text(command)
            exit(0)
        end
    end

    if command == "--help" or command == "-h" or command == "help":
        if arg(3) != None:
            print "usage: lsl help [TOPIC]"
            exit(2)
        elif arg(2) == "server":
            call print_server_help()
        elif arg(2) == "sandbox":
            call print_sandbox_help()
        elif arg(2) != None:
            print __lsl_help_text(arg(2))
        else:
            call print_help()
        end
        exit(0)
    elif command == "version" or command == "--version":
        print VERSION
        exit(0)
    elif command == "about":
        name = arg(2)
        if name == "--help" or name == "-h":
            print __lsl_help_text("about")
            exit(0)
        elif arg(3) != None:
            print "usage: lsl about [NAME]"
            exit(2)
        elif name == None:
            lines = __lsl_about_text("").split(chr(10))
            call console.heading(lines[0])
            for index in rang(1, len(lines)):
                print console.clean(lines[index])
            end
            exit(0)
        end
        if not package.valid_name(name):
            call console.error("invalid library name: " + console.clean(name))
            exit(1)
        end
        about = ""
        try:
            about = __lsl_about_text(name)
        else:
            about = ""
        end
        if about == "":
            # Bundled inventory covers an installed prefix that is not the
            # per-user directory the runtime helper checks.
            inventory = catalog.installed(__lsl_getenv("HOME"), resource_path("stdlib"))
            found = catalog.find_installed(inventory, name)
            if found != None:
                header = __lsl_comment_header(fd.read_text_limit(found["path"], 1048576))
                if header != "":
                    about = name + ": " + header
                else:
                    about = name + ": installed library without a descriptive header comment."
                end
            end
        end
        if about == "":
            call console.warning(console.clean(name) + " is not a bundled or installed library. Use lsl search " + console.clean(name) + ".")
            exit(1)
        end
        colon = about.find(":")
        call console.heading(about[0:colon])
        print console.clean(about[colon + 1:len(about)].strip())
        exit(0)
    elif command == "compile":
        source_path = arg(2)
        output_path = arg(3)
        unsafe_compile = False
        if source_path == "--unsafe":
            unsafe_compile = True
            source_path = arg(3)
            output_path = arg(4)
            extra = arg(5)
        else:
            extra = arg(4)
        end
        if source_path == None or output_path == None or extra != None:
            print "usage: lsl compile [--unsafe] SOURCE OUTPUT"
            exit(2)
        end
        if unsafe_compile:
            call compile_file_unsafe(source_path, output_path)
        else:
            call compile_file(source_path, output_path)
        end
        exit(0)
    elif command == "config":
        entry = arg(2)
        if entry == None:
            print "usage: lsl config ENTRY"
            exit(2)
        end
        evaluator = scratch_program_path()
        snapshot_directory = dirname(evaluator)
        wrapper = capture_clean(tool_path("./compiler/pure/lsl-configure", "lsl-configure"), [entry, "-", snapshot_directory])
        status = capture_status()
        if status != 0:
            if wrapper != "":
                print wrapper
            end
            detail = capture_stderr()
            if detail != "":
                print detail
            end
            call cleanup_config_snapshots(snapshot_directory)
            call cleanup_program(evaluator)
            exit(status)
        end
        synthetic_path = snapshot_directory + "/lsl_config_wrapper.lsl"
        # configure has already validated and snapshotted the complete user graph.
        # Its generated evaluator intentionally uses private runtime helpers for
        # identity-safe merging, so compile this trusted synthetic source through
        # the compiler-internal path rather than treating it as user-authored code.
        failure = None
        status = 70
        try:
            call compile_source_mode(synthetic_path, wrapper, evaluator, 0)
            # Even lexically pure configuration may contain an infinite loop or an
            # allocation bomb. Evaluate it in a clean subprocess with wall-clock,
            # CPU, address-space, file-size and descriptor limits.
            timeout = required_system_tool("/usr/bin/timeout", "/bin/timeout", "timeout")
            prlimit = required_system_tool("/usr/bin/prlimit", "/bin/prlimit", "prlimit")
            limits = [
                "--signal=TERM", "--kill-after=1s", "--", "30s", prlimit,
                "--as=1073741824", "--cpu=30", "--fsize=16777216",
                "--nofile=64", "--nproc=32", "--", evaluator
            ]
            status = run_clean(timeout, limits)
        else:
            failure = last_error()
        end
        call cleanup_config_snapshots(snapshot_directory)
        call cleanup_program(evaluator)
        if failure != None:
            Error(CliError: failure)
        end
        exit(status)
    elif command == "install":
        name = arg(2)
        if name == "--help" or name == "-h":
            print __lsl_help_text("install")
        elif name == "--tui" and arg(3) == None:
            call console.require_terminal()
            call console.heading("Loading package catalog from " + registry_server())
            items = catalog.fetch(registry_server(), "/usr/bin/curl")
            inventory = catalog.installed(__lsl_getenv("HOME"), resource_path("stdlib"))
            call browser.packages(items, inventory, executable_path())
        elif name == "--config" and arg(3) != None and arg(4) == None:
            call package.install_config(arg(3), user_home(), registry_server(), "/usr/bin/curl", "/usr/bin/sha256sum", "/usr/bin/mv", "/usr/bin/chmod", executable_path())
        elif name != None and arg(3) == None:
            call package.install(name, user_home(), registry_server(), "/usr/bin/curl", "/usr/bin/sha256sum", "/usr/bin/mv", "/usr/bin/chmod", executable_path())
        else:
            print "usage: lsl install NAME | lsl install --config FILE | lsl install --tui"
            exit(2)
        end
        exit(0)
    elif command == "list" or command == "check":
        name = arg(2)
        if name == "--help" or name == "-h":
            print __lsl_help_text(command)
            exit(0)
        end
        if (command == "list" and name != None) or (command == "check" and (name == None or arg(3) != None)):
            print "usage: lsl list | lsl check NAME"
            exit(2)
        end
        inventory = catalog.installed(__lsl_getenv("HOME"), resource_path("stdlib"))
        if command == "list":
            call console.heading("Installed libraries (bundled = supplied with LSL, user = per-user installation)")
            for item in inventory:
                print console.clean(item["name"] + "  " + item["scope"] + "  " + item["path"])
            end
            if len(inventory) == 0:
                print "No installed libraries."
            end
            exit(0)
        end
        found = catalog.find_installed(inventory, name)
        if found == None:
            call console.warning(String(name) + " is not installed. Use lsl search " + String(name) + ".")
            exit(1)
        end
        call console.success(found["name"] + " is installed (" + found["scope"] + "): " + found["path"])
        exit(0)
    elif command == "search":
        query = arg(2)
        if query == "--help" or query == "-h":
            print __lsl_help_text("search")
            exit(0)
        elif arg(3) != None:
            print "usage: lsl search [QUERY]"
            exit(2)
        end
        if query == None:
            query = ""
        end
        items = catalog.search(catalog.fetch(registry_server(), "/usr/bin/curl"), query)
        inventory = catalog.installed(__lsl_getenv("HOME"), resource_path("stdlib"))
        call console.heading("Registry: " + registry_server())
        for item in items:
            found = catalog.find_installed(inventory, item["name"])
            state = "available; lsl install " + item["name"]
            if found != None:
                state = "installed (" + found["scope"] + ")"
            end
            print item["name"] + " " + item["version"] + " [" + state + "]"
            print "  " + item["description"]
        end
        if len(items) == 0:
            call console.warning("No matching library in the registry.")
            exit(1)
        end
        exit(0)
    elif command == "man":
        topic = arg(2)
        plain = False
        if topic == "--help" or topic == "-h":
            print __lsl_help_text("man")
            exit(0)
        elif topic == "--plain":
            plain = True
            topic = arg(3)
            extra = arg(4)
        else:
            extra = arg(3)
        end
        if extra != None:
            print "usage: lsl man [--plain] [TOPIC]"
            exit(2)
        end
        if plain or not __lsl_isatty(0) or not __lsl_isatty(1) or __lsl_getenv("TERM") == "dumb":
            call manual.plain(resource_path("docs/developer_guides"), topic)
        else:
            call browser.manual_view(resource_path("docs/developer_guides"), topic)
        end
        exit(0)
    elif command == "update":
        name = arg(2)
        if name == None or String(name).startswith("--"):
            call update.main(VERSION)
        elif arg(3) != None:
            print "usage: lsl update [NAME]"
            exit(2)
        else:
            call package.update(name, user_home(), registry_server(), "/usr/bin/curl", "/usr/bin/sha256sum", "/usr/bin/mv", "/usr/bin/chmod", executable_path())
        end
        exit(0)
    elif command == "origin":
        name = arg(2)
        if arg(3) != None:
            print "usage: lsl origin [NAME]"
            exit(2)
        end
        if name == None:
            print registry_server()
        else:
            provenance = package.verified_origin(name, user_home(), "/usr/bin/sha256sum")
            print "name", provenance["name"]
            print "origin", provenance["origin"]
            print "source", provenance["source"]
            print "sha256", provenance["sha256"]
        end
        exit(0)
    elif command == "server":
        root = "."
        address = "127.0.0.1"
        port = 8080
        maximum_requests = 0
        certificate = None
        private_key = None
        option_index = 2
        while option_index < arg_count():
            option = arg(option_index)
            if option == "--help" or option == "-h":
                call print_server_help()
                exit(0)
            elif option == "--once":
                maximum_requests = 1
            elif option == "--dir" or option == "--bind" or option == "--port" or option == "--max-requests" or option == "--tls-cert" or option == "--tls-key":
                option_index += 1
                if option_index >= arg_count():
                    Error(CliError: String(option) + " requires a value")
                end
                value = arg(option_index)
                if option == "--dir":
                    root = value
                elif option == "--bind":
                    address = value
                elif option == "--port":
                    port = decimal_option(value, 1, 65535, "port")
                elif option == "--max-requests":
                    maximum_requests = decimal_option(value, 0, 1000000000, "maximum request count")
                elif option == "--tls-cert":
                    certificate = value
                else:
                    private_key = value
                end
            else:
                Error(CliError: "unknown server option: " + String(option))
            end
            option_index += 1
        end
        if (certificate == None) != (private_key == None):
            Error(CliError: "--tls-cert and --tls-key must be supplied together")
        elif certificate == None:
            call httpserver.serve_static(root, address, port, maximum_requests)
            exit(0)
        else:
            exit(httpserver.serve_static_tls(root, address, port, certificate, private_key, maximum_requests))
        end
    elif command == "sandbox":
        selected_profile = "strict"
        wall_seconds = 30
        memory_bytes = 1073741824
        read_capabilities = []
        write_capabilities = []
        source_path = None
        option_index = 2
        while option_index < arg_count() and source_path == None:
            option = arg(option_index)
            if option == "--help" or option == "-h":
                call print_sandbox_help()
                exit(0)
            elif option == "--":
                option_index += 1
                if option_index >= arg_count():
                    Error(CliError: "sandbox source is required after --")
                end
                source_path = arg(option_index)
            elif option == "--profile" or option == "--timeout" or option == "--memory" or option == "--read" or option == "--write":
                option_index += 1
                if option_index >= arg_count():
                    Error(CliError: String(option) + " requires a value")
                end
                value = arg(option_index)
                if option == "--profile":
                    if value != "strict" and value != "server":
                        Error(CliError: "sandbox profile must be strict or server")
                    end
                    selected_profile = value
                elif option == "--timeout":
                    wall_seconds = decimal_option(value, 1, 3600, "sandbox timeout")
                elif option == "--memory":
                    memory_bytes = decimal_option(value, 67108864, 8589934592, "sandbox memory")
                elif option == "--read":
                    read_capabilities.append(value)
                else:
                    write_capabilities.append(value)
                end
            elif String(option).startswith("-"):
                Error(CliError: "unknown sandbox option: " + String(option))
            else:
                source_path = option
            end
            option_index += 1
        end
        if source_path == None:
            print "usage: lsl sandbox [OPTIONS] SOURCE [ARG...]"
            exit(2)
        end
        if not sandbox.available():
            Error(SandboxError: "lsl sandbox requires bubblewrap, systemd-run, timeout, prlimit, realpath and env")
        end
        sandbox_arguments = []
        while option_index < arg_count():
            sandbox_arguments.append(arg(option_index))
            option_index += 1
        end
        policy = {
            "profile": selected_profile,
            "timeout": wall_seconds,
            "memory": memory_bytes,
            "read": read_capabilities,
            "write": write_capabilities
        }
        # Resolve and validate every caller-controlled capability before creating
        # an executable scratch file.
        call sandbox.checked_policy(policy)
        call sandbox.checked_arguments(sandbox_arguments)
        runtime_directory = __lsl_getenv("XDG_RUNTIME_DIR")
        bus = __lsl_getenv("DBUS_SESSION_BUS_ADDRESS")
        if runtime_directory == None or runtime_directory == "" or bus == None or bus == "":
            Error(SandboxError: "a systemd user session is required for cgroup limits")
        end
        scratch = materialize_scratch(compile_file_image(source_path, 2))
        failure = None
        status = 70
        try:
            status = sandbox.run(scratch, sandbox_arguments, policy)
        else:
            failure = last_error()
        end
        call cleanup_program(scratch)
        if failure != None:
            Error(SandboxError: failure)
        end
        exit(status)
    end

    image = compile_file_image(command, 1)
    arguments = []
    index = 2
    while index < arg_count():
        arguments.append(arg(index))
        index += 1
    end
    scratch = materialize_scratch(image)
    status = run(scratch, arguments)
    call cleanup_program(scratch)
    exit(status)
end

try:
    call main()
else:
    call console.error(last_error())
    exit(1)
end
