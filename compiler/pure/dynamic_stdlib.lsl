# Dynamic operations implemented in LSL and compiled by the direct backend.

function __lsl_is_space(character):
    return character == " " or character == "\t" or character == "\r" or character == "\n"
end

function __lsl_ext_case(code):
    # Latin Extended-A: 1 = uppercase (lower is code+1), -1 = lowercase
    # (upper is code-1), 0 = no simple single-char mapping. Reversed subblocks
    # 0x139-0x148 and 0x179-0x17E have odd=upper; elsewhere even=upper.
    if code == 304 or code == 305 or code == 312 or code == 329 or code == 383 or code == 376:
        return 0
    end
    even = code % 2 == 0
    if (code >= 313 and code <= 328) or (code >= 377 and code <= 382):
        if even:
            return -1
        end
        return 1
    end
    if even:
        return 1
    end
    return -1
end

function __lsl_lower_code(code):
    if code >= 65 and code <= 90:
        return code + 32
    elif code >= 192 and code <= 222 and code != 215:
        return code + 32
    elif code == 376:
        return 255
    elif code >= 256 and code <= 383:
        if __lsl_ext_case(code) == 1:
            return code + 1
        end
    end
    return code
end

function __lsl_upper_code(code):
    if code >= 97 and code <= 122:
        return code - 32
    elif code == 181:
        return 924
    elif code >= 224 and code <= 254 and code != 247:
        return code - 32
    elif code == 255:
        return 376
    elif code == 305:
        return 73
    elif code == 383:
        return 83
    elif code >= 256 and code <= 382:
        if __lsl_ext_case(code) == -1:
            return code - 1
        end
    end
    return code
end

function __lsl_lower(text):
    result = []
    for character in text:
        result.append(chr(__lsl_lower_code(ord(character))))
    end
    return "".join(result)
end

function __lsl_upper(text):
    result = []
    for character in text:
        result.append(chr(__lsl_upper_code(ord(character))))
    end
    return "".join(result)
end

function __lsl_capitalize(text):
    if len(text) == 0:
        return text
    end
    return __lsl_upper(text[0]) + __lsl_lower(text[1:len(text)])
end

function __lsl_title(text):
    result = []
    word_start = True
    for character in text:
        code = ord(character)
        if code >= 65 and code <= 90:
            if word_start:
                result.append(character)
            else:
                result.append(chr(code + 32))
            end
            word_start = False
        elif code >= 97 and code <= 122:
            if word_start:
                result.append(chr(code - 32))
            else:
                result.append(character)
            end
            word_start = False
        else:
            result.append(character)
            word_start = True
        end
    end
    return "".join(result)
end

function __lsl_startswith(text, prefix):
    text = __lsl_require_string(text)
    prefix = __lsl_require_string_value(prefix)
    if len(prefix) > len(text):
        return False
    end
    index = 0
    while index < len(prefix):
        if text[index] != prefix[index]:
            return False
        end
        index += 1
    end
    return True
end

function __lsl_endswith(text, suffix):
    text = __lsl_require_string(text)
    suffix = __lsl_require_string_value(suffix)
    if len(suffix) > len(text):
        return False
    end
    offset = len(text) - len(suffix)
    index = 0
    while index < len(suffix):
        if text[offset + index] != suffix[index]:
            return False
        end
        index += 1
    end
    return True
end

function __lsl_lstrip(text):
    start = 0
    while start < len(text) and __lsl_is_space(text[start]):
        start += 1
    end
    return text[start:len(text)]
end

function __lsl_rstrip(text):
    stop = len(text)
    while stop > 0 and __lsl_is_space(text[stop - 1]):
        stop -= 1
    end
    return text[0:stop]
end

function __lsl_strip(text):
    return __lsl_rstrip(__lsl_lstrip(text))
end

function __lsl_find(text, needle):
    text = __lsl_require_string(text)
    needle = __lsl_require_string_value(needle)
    if len(needle) == 0:
        return 0
    end
    limit = len(text) - len(needle)
    if len(needle) > 0 and len(text) > 100000000 // len(needle):
        Error(ValueError: "substring search exceeds the safe work limit")
    end
    start = 0
    while start <= limit:
        matches = True
        index = 0
        while index < len(needle):
            if text[start + index] != needle[index]:
                matches = False
                break
            end
            index += 1
        end
        if matches:
            return start
        end
        start += 1
    end
    return -1
end

# Embedded topic help: available in standalone ELF programs, without files/network.
function __lsl_help_text(topic):
    if type(topic) != "String":
        Error(TypeError: "help topic must be a String")
    end
    if len(topic) > 128:
        Error(ValueError: "help topic exceeds 128 characters")
    end
    topics = {
        "help": "help() prints the topic index. help(\"TOPIC\") prints help for a command, keyword, builtin or module.\nTopics may be runtime String values. The return value is None.\nExamples: help(\"print\"), help(\"random\"), help(\"install\"). Full manual: lsl man.",
        "install": "lsl install NAME\nDownload a per-user library from the configured HTTPS registry, verify SHA-256,\ncompile it without executing it, and install atomically under ~/.local/lib/lsl/stdlib.\nlsl install --config FILE  Install names from an LF-separated config file.\nlsl install --tui          Browse catalog; Space marks, i installs, y confirms.\nNo sudo is needed for per-user packages. LSL_REGISTRY overrides the registry.",
        "list": "lsl list\nList installed source libraries with their scope (bundled/user) and path.\nThis command is offline and does not create installation directories.\nBundled libraries take priority over per-user libraries with the same name.",
        "search": "lsl search [QUERY]\nSearch the registry catalog by name or description (case-insensitive).\nWithout QUERY, list all catalog packages. Results show version and installation status.\nExit status: 0 = match, 1 = no match or registry error, 2 = invalid arguments.\nAvailability is catalog metadata; install still verifies source integrity and compilation.",
        "check": "lsl check NAME\nCheck whether a library file is installed (bundled or per-user).\nExit status: 0 = installed, 1 = missing/error, 2 = invalid arguments.\nOffline, no compilation or execution. Use lsl origin NAME to verify recorded provenance.",
        "man": "lsl man [TOPIC]\nOpen the offline version of the web manual in a terminal browser.\nArrows/PgUp/PgDn scroll; Enter opens; / searches; n finds next; Esc returns; q exits.\nlsl man --plain [TOPIC] prints plain text (also used automatically for pipes).\nExamples: lsl man random; lsl man --plain reference.",
        "update": "lsl update                     Update LSL itself from the signed stable channel.\nlsl update NAME                Update an installed per-user library.\nlsl update --check             Check for a new LSL version without installing.\nsudo /usr/local/bin/lsl update --system  Update the system installation.\nsudo /usr/local/bin/lsl update --system --rollback  Restore the previous version.\nEd25519 signature, version, platform, size and SHA-256 are verified before activation.\n--allow-downgrade is an explicit developer override.",
        "origin": "lsl origin [NAME]\nWithout NAME print the active registry URL. With NAME verify the installed library\nagainst its recorded SHA-256 and print its name, origin, source URL and hash.",
        "compile": "lsl compile [--unsafe] SOURCE OUTPUT\nCompile LSL source into a native Linux x86_64 ELF. The default is checked compilation.\n--unsafe explicitly enables the unsafe compiler mode. Compilation does not run the program.",
        "config": "lsl config ENTRY\nEvaluate a validated LSL configuration graph and print its merged configuration.\nEvaluation runs with time and resource limits.",
        "server": "lsl server [OPTIONS]\nServe static files: --dir ROOT --bind IPV4 --port PORT --once --max-requests N.\nFor HTTPS supply both --tls-cert FILE and --tls-key FILE (system nginx/OpenSSL).\nRun lsl server --help for defaults and all options.",
        "sandbox": "lsl sandbox [OPTIONS] SOURCE [ARG...]\nCompile and run with capability and resource limits.\n--profile strict|server --timeout SECONDS --memory BYTES --read PATH --write PATH.\nRequires the system sandbox tools and a systemd user session. See lsl sandbox --help.",
        "version": "lsl version\nPrint the installed LSL version, suitable for scripts. Equivalent: lsl --version.",
        "print": "print VALUE [, VALUE...]\nPrint values separated by spaces and end with a newline.\nExample: print \"answer\", 42",
        "printl": "printl \"text {EXPRESSION}\"\nPrint an interpolated Lux String and a newline. Equivalent: print l\"text {EXPRESSION}\".",
        "input": "input(PROMPT) -> String\nRead one input line after displaying PROMPT.\nExample: name = input(\"Name: \")",
        "function": "function NAME(PARAMETERS): ... end\nDeclare a function. return VALUE returns a result; omitted return yields None.\nImmutable default values and named arguments are supported for declared functions.",
        "return": "return VALUE\nReturn a value from a function. A bare return returns None.",
        "class": "class NAME(True): ... end\nDeclare a class. Define init(self, ...) as the constructor.\nclass Child(Parent) inherits methods; origin.method(...) invokes the parent.",
        "ctype": "ctype Public | Private\nSelect class export visibility. Public is the default; Private prevents module export.",
        "if": "if CONDITION: ... elif CONDITION: ... else: ... end\nConditional execution; elif and else are optional.",
        "for": "for ITEM in ITERABLE: ... end\nIterate over a collection. Comprehensions additionally support flat unpacking.\nExample: [x*x for x in rang(10) if x % 2 == 0].",
        "while": "while CONDITION: ... end\nRepeat while the condition is true; break exits, continue advances the loop.",
        "loop": "loop: ... end\nAn unconditional loop. Use break to leave it.",
        "break": "break\nExit the innermost loop.",
        "continue": "continue\nSkip the rest of the current loop iteration.",
        "try": "try: ... else: ... end\nCatch an LSL error. In else, last_error() provides the error text.",
        "Error": "Error(NAME: MESSAGE)\nRaise a catchable named error. Example: Error(ValueError: \"bad value\").",
        "safe": "safe: ... end\nOn an LSL runtime error, skip the rest of the block and continue after end.\nUse try/else when you need an explicit error handler. This is not a security sandbox.",
        "unsafe": "unsafe: ... end\nExplicitly enter the unsafe boundary. Do not use it on untrusted data.",
        "load": "load MODULE\nLoad an LSL source library. Bundled modules cannot be shadowed by local/user files.\nUse lsl install NAME to obtain a registry library.",
        "del": "del(COLLECTION[KEY])\nDelete a dictionary entry or collection element. Deleting a variable removes its binding.",
        "len": "len(VALUE) -> Int\nReturn the number of elements in a collection or Unicode characters in a String.",
        "type": "type(VALUE) -> String\nReturn the runtime type name.",
        "abs": "abs(NUMBER)\nReturn the absolute value of an Int, Bool or Float.",
        "sqrt": "sqrt(NUMBER) -> Float\nReturn the square root of a nonnegative number.",
        "sum": "sum(ITERABLE)\nAdd the elements of a numeric iterable.",
        "min": "min(ITERABLE) or min(A, B)\nReturn the smallest element or operand.",
        "max": "max(ITERABLE) or max(A, B)\nReturn the largest element or operand.",
        "rang": "rang(STOP), rang(START, STOP), rang(START, STOP, STEP)\nConstruct an integer range excluding STOP; STEP must not be zero.",
        "range": "range(...) is an alias of rang(...). See help(\"rang\") for start/stop/step.",
        "String": "String(VALUE)\nConvert a value to text. Strings are UTF-8; indexing uses Unicode characters.",
        "Int": "Int(VALUE)\nConvert a supported numeric value or decimal String to a signed 64-bit integer.",
        "Float": "Float(VALUE)\nConvert a number or numeric String to IEEE-754 Float64.",
        "Bool": "Bool(VALUE)\nConvert a value to its truth value.",
        "List": "List(VALUE)\nCreate a mutable list. Literal: [1, 2, 3]. Comprehension: [x*x for x in rang(4)].",
        "Tuple": "Tuple(VALUE)\nCreate an immutable tuple. Literal: (1, 2). Tuple([x for x in rang(3)]) is eager.",
        "Dictionary": "Dictionary(VALUE)\nCreate a key/value dictionary. Literal: {\"a\": 1}.\nComprehension: {x:x*x for x in rang(4)}.",
        "IntArray": "IntArray() creates a packed signed 64-bit array; IntArray(existing) is a checked cast.",
        "FloatArray": "FloatArray() creates a packed Float64 array; FloatArray(existing) is a checked cast.",
        "ByteArray": "ByteArray() creates a byte array (0..255); ByteArray(existing) is a checked cast.",
        "RealArray": "RealArray(VALUE)\nCreate a fixed-length sequence. Elements can change; the length cannot.\nLiteral: ![1, 2, 3]. See lsl man collections.",
        "readfile": "readfile(PATH) -> String\nRead a UTF-8 text file. For bounded reads, load fd and use fd.read_text_limit.",
        "writefile": "writefile(PATH, TEXT)\nWrite text to a file, replacing existing contents.",
        "appendfile": "appendfile(PATH, TEXT)\nAppend text to a file.",
        "readbytes": "readbytes(PATH) -> ByteArray\nRead a file as binary bytes.",
        "writebytes": "writebytes(PATH, BYTES)\nWrite bytes to a file. ELF output is made executable by the runtime.",
        "run": "run(EXECUTABLE, ARGUMENTS) -> Int\nExecute a program with an argv list, without a shell; return its exit status.",
        "capture": "capture(EXECUTABLE, ARGUMENTS) -> String\nCapture stdout from direct argv execution. Inspect capture_status() and capture_stderr().",
        "exit": "exit(STATUS)\nTerminate the program with an integer exit status.",
        "arg": "arg(INDEX) -> String or None\nRead a program argument; arg(1) is the first user argument.",
        "arg_count": "arg_count() -> Int\nReturn the number of program arguments including the executable name.",
        "last_error": "last_error() -> String\nReturn the most recent caught LSL error text.",
        "gc": "gc()\nRequest garbage collection. References still reachable from the program remain alive.",
        "clock": "clock() -> Float\nReturn the runtime clock value for timing. See the time module for sleep and wall time.",
        "chr": "chr(CODEPOINT) -> String\nConstruct a one-character Unicode String.",
        "ord": "ord(CHARACTER) -> Int\nReturn the Unicode codepoint of one character.",
        "random": "load random\nPython-style MT19937 Random and OS-backed SystemRandom. Supports seed/state,\nrandom/randrange/randint/getrandbits/randbytes, choice/choices/sample/shuffle,\nand probability distributions. Example: rng = random.Random(42)\nSee lsl man random for compatibility and exact limits.",
        "cuda": "load cuda\nPersistent CUDA sessions and device buffers. Requires NVIDIA hardware and the CUDA worker.\nSee lsl man cuda for resource lifetime, API and hardware requirements.",
        "tensor": "load tensor\nCPU tensors and persistent GPU DeviceTensor operations. See lsl man cuda.",
        "json": "load json\njson.encode(VALUE) serializes data; json.decode(TEXT) parses JSON.",
        "os": "load os\nSafe direct-argv process execution and executable lookup, never implicit shell execution.",
        "time": "load time\nSleep and time utilities. See lsl man --plain reference.",
        "tui": "load tui\nPure-LSL full-screen terminal toolkit: Terminal, enter/leave, read_key and rendering.\nAlways restore the terminal on errors and cancellation.",
        "math": "load math\nMathematical constants and numeric functions. See lsl man --plain reference.",
        "bigint": "load bigint\nArbitrary-precision integer arithmetic. Construct bigint.BigInt(VALUE).",
        "ai": "load ai\nAI service client utilities; see lsl man ai.",
        "httpserver": "load httpserver\nNative HTTP server and managed HTTPS support; also available via lsl server.",
        "process": "load process\nDirect-argv process utilities. See lsl man --plain reference.",
        "fd": "load fd\nChecked descriptor I/O, bounded file reads and binary transport helpers."
    }
    if topic == "":
        names = topics.keys()
        call names.sort()
        return "Lux Simple Lang (LSL) 0.8.0" + chr(10) + "Use help(\"TOPIC\") for details; lsl man opens the full offline manual." + chr(10) + "topics: " + " ".join(names)
    end
    if topic not in topics:
        Error(HelpError: "unknown help topic; call help() to list supported topics")
    end
    return topics[topic]
end

function __lsl_help(topic):
    print __lsl_help_text(topic)
    return None
end

function __lsl_string_index(text, needle):
    position = __lsl_find(text, needle)
    if position < 0:
        Error(ValueError: "substring is not in String")
    end
    return position
end

# Copy the byte range [start, start + count) of a String into a new String.
# UTF-8 sequences are preserved verbatim, and the cost is linear in the
# piece length instead of a code-point walk from the beginning.
function __lsl_byte_piece(s, start, count):
    if count <= 0:
        return ""
    end
    buffer = __lsl_byte_zeros(count)
    index = 0
    while index < count:
        buffer[index] = __lsl_text_byte(s, start + index)
        index += 1
    end
    return __lsl_text_from_bytes(buffer, 0, count)
end

function __lsl_split(text, separator):
    # Pure byte probes and byte-range pieces. The earlier version probed
    # bytes but sliced by code points, which returned wrong pieces for any
    # multi-byte String and cost a code-point walk from the start per
    # piece (quadratic on large inputs).
    s = __lsl_require_string(text)
    sep = __lsl_require_string_value(separator)
    n = __lsl_text_byte_length(String(s))
    m = __lsl_text_byte_length(String(sep))
    result = []
    if m == 0 or m > n:
        call result.append(s)
        return result
    end
    if n > 100000000 // m:
        Error(ValueError: "String split exceeds the safe work limit")
    end
    first = __lsl_text_byte(sep, 0)
    start = 0
    index = 0
    while index + m <= n:
        if __lsl_text_byte(s, index) == first:
            matches = True
            offset = 1
            while offset < m:
                if __lsl_text_byte(s, index + offset) != __lsl_text_byte(sep, offset):
                    matches = False
                    break
                end
                offset += 1
            end
            if matches:
                call result.append(__lsl_byte_piece(s, start, index - start))
                index += m
                start = index
            else:
                index += 1
            end
        else:
            index += 1
        end
    end
    call result.append(__lsl_byte_piece(s, start, n - start))
    return result
end

function __lsl_join(separator, values):
    # Pairwise balanced merge: repeated `result += piece` is quadratic in
    # the total length, which made joining a few thousand one-character
    # strings (fd.read_text on /proc) cost hundreds of milliseconds.
    separator = __lsl_require_string(separator)
    values = __lsl_require_sequence(values)
    count = len(values)
    if count == 0:
        return ""
    end
    work = []
    index = 0
    while index < count:
        piece = __lsl_require_string_value(values[index])
        if index > 0:
            piece = separator + piece
        end
        work.append(piece)
        index += 1
    end
    while len(work) > 1:
        merged = []
        index = 0
        while index < len(work):
            if index + 1 < len(work):
                merged.append(work[index] + work[index + 1])
            else:
                merged.append(work[index])
            end
            index += 2
        end
        work = merged
    end
    return work[0]
end

function __lsl_extend(target, values):
    # Normalize typed arrays to boxed List elements before the internal helper
    # appends them to a public List.
    values = __lsl_list(values)
    for value in values:
        call target.append(value)
    end
end

function __lsl_list(values):
    values = __lsl_require_sequence(values)
    result = []
    value_code = __lsl_type_code(values)
    if value_code == 13:
        index = 0
        while index < len(values):
            result.append(Int(values[index]))
            index += 1
        end
        return result
    elif value_code == 14:
        index = 0
        while index < len(values):
            result.append(Float(values[index]))
            index += 1
        end
        return result
    elif value_code == 15:
        index = 0
        while index < len(values):
            result.append(Int(values[index]))
            index += 1
        end
        return result
    end
    for value in values:
        result.append(value)
    end
    return result
end

function __lsl_require_real(value):
    value_type = __lsl_type_code(value)
    if value_type != 0 and value_type != 6 and value_type != 9:
        Error(TypeError: "RealArray accepts only Int or Float values")
    end
    return value
end

function __lsl_require_string(value):
    if __lsl_type_code(value) != 1:
        Error(TypeError: "method requires a String receiver")
    end
    return value
end

function __lsl_require_string_value(value):
    if __lsl_type_code(value) != 1:
        Error(TypeError: "expected a String")
    end
    return value
end

function __lsl_require_list(value):
    if __lsl_type_code(value) != 2:
        Error(TypeError: "method requires a List receiver")
    end
    return value
end

function __lsl_require_dictionary(value):
    if __lsl_type_code(value) != 3:
        Error(TypeError: "method requires a Dictionary receiver")
    end
    return value
end

function __lsl_require_byte_sequence(value):
    value_type = __lsl_type_code(value)
    if value_type != 2 and value_type != 15:
        Error(TypeError: "operation requires a ByteArray or List")
    end
    return value
end

function __lsl_require_sequence(value):
    value_type = __lsl_type_code(value)
    if value_type != 1 and value_type != 2 and value_type != 7 and value_type != 8 and value_type != 13 and value_type != 14 and value_type != 15:
        Error(TypeError: "method requires an indexable sequence")
    end
    return value
end

function __lsl_dynamic_count(target, value):
    target_type = __lsl_type_code(target)
    if target_type == 1:
        return __lsl_count(target, value)
    elif target_type == 2 or target_type == 7 or target_type == 8:
        return __lsl_list_count(target, value)
    end
    Error(TypeError: "count requires a String, List, Tuple, or RealArray")
end

function __lsl_dynamic_index(target, value):
    target_type = __lsl_type_code(target)
    if target_type == 1:
        return __lsl_string_index(target, value)
    elif target_type == 2 or target_type == 7 or target_type == 8:
        return __lsl_list_index(target, value)
    end
    Error(TypeError: "index requires a String, List, Tuple, or RealArray")
end

function __lsl_dynamic_copy(target):
    target_type = __lsl_type_code(target)
    if target_type == 2:
        return __lsl_copy(target)
    elif target_type == 3:
        return __lsl_dict_copy(target)
    elif target_type == 8:
        return RealArray(__lsl_copy(target))
    end
    Error(TypeError: "copy requires a List, Dictionary, or RealArray")
end

function __lsl_dynamic_pop0(target):
    if __lsl_type_code(target) != 2:
        Error(TypeError: "pop() without an argument requires a List")
    end
    return __lsl_pop(target)
end

function __lsl_dynamic_pop1(target, key):
    target_type = __lsl_type_code(target)
    if target_type == 2:
        return __lsl_pop_at(target, __lsl_checked_index(key))
    elif target_type == 3:
        return __lsl_dict_pop(target, key)
    end
    Error(TypeError: "pop requires a List or Dictionary")
end

function __lsl_dynamic_pop2(target, key, default_value):
    if __lsl_type_code(target) != 3:
        Error(TypeError: "pop(key, default) requires a Dictionary")
    end
    return __lsl_dict_pop_default(target, key, default_value)
end

function __lsl_sequence_contains(target, value):
    for item in target:
        if item == value:
            return True
        end
    end
    return False
end

function __lsl_dynamic_contains(target, value):
    target_type = __lsl_type_code(target)
    if target_type == 1:
        return __lsl_find(target, __lsl_require_string_value(value)) >= 0
    elif target_type == 3:
        for key in target.keys():
            if key == value:
                return True
            end
        end
        return False
    elif target_type == 2 or target_type == 7 or target_type == 8 or target_type == 13 or target_type == 14 or target_type == 15:
        return __lsl_sequence_contains(target, value)
    end
    Error(TypeError: "right operand of in is not a collection")
end

function __lsl_real_array(values):
    values = __lsl_list(values)
    result = []
    for value in values:
        result.append(__lsl_require_real(value))
    end
    return result
end

function __lsl_sum_values(values, box_integer):
    values = __lsl_require_sequence(values)
    values_type = __lsl_type_code(values)
    if values_type == 13:
        integer_values = IntArray(values)
        integer_total = 0
        for integer_value in integer_values:
            integer_total += integer_value
        end
        if box_integer:
            return __lsl_box_int(integer_total)
        end
        return integer_total
    elif values_type == 14:
        return float_sum(FloatArray(values))
    elif values_type == 15:
        byte_values = ByteArray(values)
        byte_total = 0
        for byte_value in byte_values:
            byte_total += byte_value
        end
        if box_integer:
            return __lsl_box_int(byte_total)
        end
        return byte_total
    elif values_type == 1:
        Error(TypeError: "sum values must be numeric")
    end
    integer_result = 0
    float_result = 0.0
    floating = False
    for value in values:
        value_type = __lsl_type_code(value)
        if value_type == 6:
            if not floating:
                float_result = Float(integer_result)
                floating = True
            end
            float_result += Float(value)
        elif value_type == 9 or value_type == 4:
            if floating:
                float_result += Float(value)
            else:
                integer_result += Int(value)
            end
        else:
            Error(TypeError: "sum values must be numeric")
        end
    end
    if floating:
        return float_result
    end
    if box_integer:
        # The public result is Any. Box directly instead of probing the raw
        # result: an Int can have the same bits as a live heap address.
        return __lsl_box_int(integer_result)
    end
    return integer_result
end

function __lsl_sum(values):
    return __lsl_sum_values(values, False)
end

function __lsl_public_sum(values):
    return __lsl_sum_values(values, True)
end

function __lsl_float_accumulate(value, digit):
    # Bootstrap fallback. New codegens mutate the parser's private accumulator
    # Float in place, avoiding two fresh boxes for every decimal digit.
    return value * 10.0 + __lsl_float_from_int(__lsl_typed_int(digit))
end

function __lsl_parse_float(text):
    if len(text) > 4096:
        Error(ValueError: "Float String exceeds 4096 characters")
    end
    normalized = __lsl_lower(text)
    if normalized == "nan" or normalized == "+nan" or normalized == "-nan":
        return 0.0 / 0.0
    elif normalized == "inf" or normalized == "+inf" or normalized == "infinity" or normalized == "+infinity":
        return 1.0 / 0.0
    elif normalized == "-inf" or normalized == "-infinity":
        return -1.0 / 0.0
    end
    sign = 1.0
    index = 0
    if len(text) > 0 and text[0] == "-":
        sign = -1.0
        index = 1
    elif len(text) > 0 and text[0] == "+":
        index = 1
    end
    value = __lsl_float_from_int(0)
    fraction_scale = __lsl_float_from_int(1)
    after_dot = False
    exponent = 0
    exponent_negative = False
    in_exponent = False
    exponent_sign_allowed = False
    digits = 0
    exponent_digits = 0
    while index < len(text):
        character = text[index]
        code = ord(character)
        if code >= 48 and code <= 57:
            digit = code - 48
            if in_exponent:
                # Values beyond this point already underflow/overflow every
                # finite Float. Saturating avoids Int wrap and an unbounded
                # exponent-scaling loop on hostile decimal input.
                if exponent < 10000:
                    exponent = exponent * 10 + digit
                    if exponent > 10000:
                        exponent = 10000
                    end
                end
                exponent_digits += 1
                exponent_sign_allowed = False
            else:
                value = __lsl_float_accumulate(value, digit)
                digits += 1
                if after_dot:
                    fraction_scale = __lsl_float_accumulate(fraction_scale, 0)
                end
            end
        elif character == "." and not after_dot and not in_exponent:
            after_dot = True
        elif (character == "e" or character == "E") and not in_exponent and digits > 0:
            in_exponent = True
            exponent_sign_allowed = True
        elif in_exponent and exponent_sign_allowed and (character == "-" or character == "+"):
            if character == "-":
                exponent_negative = True
            end
            exponent_sign_allowed = False
        else:
            Error(ValueError: "invalid Float String")
        end
        index += 1
    end
    if digits == 0 or (in_exponent and exponent_digits == 0):
        Error(ValueError: "invalid Float String")
    end
    value /= fraction_scale
    # Scale by exact powers of ten (10^22 is the largest exact double)
    # in one multiply or divide per chunk. Per-digit scaling would round
    # on every step and break the formatter round-trip search, which
    # needs this conversion to be monotonic in the decimal digits.
    while exponent > 0:
        step = exponent
        if step > 22:
            step = 22
        end
        scale = __lsl_float_from_int(1)
        counter = 0
        while counter < step:
            scale = __lsl_float_accumulate(scale, 0)
            counter += 1
        end
        if exponent_negative:
            value /= scale
        else:
            value *= scale
        end
        exponent -= step
    end
    return value * sign
end

function __lsl_float_any(value):
    value_type = __lsl_type_code(value)
    if value_type == 6:
        return value
    elif value_type == 1:
        return __lsl_parse_float(value)
    elif value_type == 0:
        return __lsl_float_from_int(value)
    elif value_type == 9:
        return __lsl_float_from_int(__lsl_unbox_int(value))
    elif value_type == 4:
        return __lsl_float_from_int(__lsl_unbox_bool(value))
    end
    Error(TypeError: "Float expects Int, Bool, Float, or String")
end

function __lsl_float_candidate(significand, digit_count, exponent):
    digits = __lsl_int_to_string(significand)
    if exponent >= 0 and exponent < 16:
        integer_count = exponent + 1
        result = digits[0:integer_count] + "."
        if integer_count < digit_count:
            return result + digits[integer_count:digit_count]
        end
        return result + "0"
    elif exponent < 0 and exponent > -7:
        result = "0."
        for index in rang(-exponent - 1):
            result += "0"
        end
        return result + digits[0:digit_count]
    end
    result = digits[0]
    if digit_count == 1:
        result += ".0"
    else:
        result += "." + digits[1:digit_count]
    end
    if exponent >= 0:
        return result + "e+" + __lsl_int_to_string(exponent)
    end
    return result + "e-" + __lsl_int_to_string(-exponent)
end

function __lsl_float_candidate_bits(significand, digit_count, exponent):
    # Bootstrap fallback. New codegens recognize this helper as an intrinsic
    # and build/parse the candidate entirely in a native stack buffer.
    return __lsl_float_bits(__lsl_parse_float(__lsl_float_candidate(significand, digit_count, exponent)))
end

function __lsl_decimal_digits_match(value, digit_count):
    if digit_count == 1:
        return value >= 0 and value < 10
    end
    lower = 1
    for index in rang(digit_count - 1):
        lower *= 10
    end
    return value >= lower and value < lower * 10
end

function __lsl_render_float_digits(significand, digit_count, exponent, negative):
    digits = __lsl_int_to_string(significand)
    prefix = ""
    if negative:
        prefix = "-"
    end
    if exponent >= 16 or exponent <= -7:
        return prefix + __lsl_float_candidate(significand, digit_count, exponent)
    end
    result = prefix
    if exponent >= 0:
        index = 0
        while index <= exponent:
            if index < digit_count:
                result += digits[index]
            else:
                result += "0"
            end
            index += 1
        end
        result += "."
        if index >= digit_count:
            result += "0"
        else:
            result += digits[index:digit_count]
        end
        return result
    end
    result += "0."
    for index in rang(-exponent - 1):
        result += "0"
    end
    return result + digits[0:digit_count]
end

function __lsl_format_float(value):
    bits = __lsl_float_bits(value)
    if bits == 9218868437227405312:
        return "inf"
    elif bits == -4503599627370496:
        return "-inf"
    elif bits > 9218868437227405312 or (bits < 0 and bits > -4503599627370496):
        return "nan"
    end
    negative = value < 0.0 or (value == 0.0 and bits < 0)
    if negative:
        value = -value
    end
    if value == 0.0:
        if negative:
            return "-0.0"
        end
        return "0.0"
    end
    integer_value = Int(value)
    if integer_value >= 0 and __lsl_float_from_int(integer_value) == value:
        integer_text = __lsl_int_to_string(integer_value) + ".0"
        if negative:
            return "-" + integer_text
        end
        return integer_text
    end
    target_bits = __lsl_float_bits(value)

    exponent = 0
    significand = 0
    round_digit = 0
    if integer_value >= 0 and value >= 1.0:
        integer_digits = len(__lsl_int_to_string(integer_value))
        exponent = integer_digits - 1
        significand = integer_value
        fraction = value - __lsl_float_from_int(integer_value)
        generated = integer_digits
        while generated < 17:
            fraction *= 10.0
            digit = Int(fraction)
            if digit < 0:
                digit = 0
            elif digit > 9:
                digit = 9
            end
            significand = significand * 10 + digit
            fraction -= __lsl_float_from_int(digit)
            generated += 1
        end
        round_digit = Int(fraction * 10.0)
    else:
        scaled = value
        while scaled >= 10.0:
            scaled /= 10.0
            exponent += 1
        end
        while scaled < 1.0:
            scaled *= 10.0
            exponent -= 1
        end
        for index in rang(17):
            digit = Int(scaled)
            if digit < 0:
                digit = 0
            elif digit > 9:
                digit = 9
            end
            significand = significand * 10 + digit
            scaled = (scaled - __lsl_float_from_int(digit)) * 10.0
        end
        round_digit = Int(scaled)
    end
    if round_digit >= 5:
        significand += 1
    end
    if significand >= 100000000000000000:
        significand = significand // 10
        exponent += 1
    end

    # Repeated decimal scaling above can drift by a few ulps. Correct the final
    # 17-digit integer against the original IEEE bits before shortening it.
    # When one significand step jumps across the target the exact decimal is
    # unreachable through the parser; the closer bracketing side then wins
    # instead of failing the whole format.
    attempts = 0
    parsed_bits = __lsl_float_candidate_bits(significand, 17, exponent)
    while parsed_bits != target_bits and attempts < 300:
        previous_significand = significand
        previous_exponent = exponent
        previous_bits = parsed_bits
        if parsed_bits < target_bits:
            significand += 1
        else:
            significand -= 1
        end
        if significand >= 100000000000000000:
            significand = significand // 10
            exponent += 1
        elif significand < 10000000000000000:
            significand = significand * 10 + 9
            exponent -= 1
        end
        parsed_bits = __lsl_float_candidate_bits(significand, 17, exponent)
        attempts += 1
        if parsed_bits != target_bits:
            crossed = False
            if previous_bits < target_bits and parsed_bits > target_bits:
                low_bits = previous_bits
                low_significand = previous_significand
                low_exponent = previous_exponent
                high_bits = parsed_bits
                high_significand = significand
                high_exponent = exponent
                crossed = True
            elif previous_bits > target_bits and parsed_bits < target_bits:
                low_bits = parsed_bits
                low_significand = significand
                low_exponent = exponent
                high_bits = previous_bits
                high_significand = previous_significand
                high_exponent = previous_exponent
                crossed = True
            end
            if crossed:
                if target_bits - low_bits <= high_bits - target_bits:
                    significand = low_significand
                    exponent = low_exponent
                else:
                    significand = high_significand
                    exponent = high_exponent
                end
                break
            end
        end
    end

    digit_count = 17
    shortening = True
    while digit_count > 1 and shortening:
        next_count = digit_count - 1
        matched = False
        rounded = (significand + 5) // 10
        if __lsl_decimal_digits_match(rounded, next_count):
            if __lsl_float_candidate_bits(rounded, next_count, exponent) == target_bits:
                significand = rounded
                digit_count = next_count
                matched = True
            end
        end
        if not matched:
            lower = significand // 10
            if __lsl_decimal_digits_match(lower, next_count):
                if __lsl_float_candidate_bits(lower, next_count, exponent) == target_bits:
                    significand = lower
                    digit_count = next_count
                    matched = True
                end
            end
        end
        if not matched:
            shortening = False
        end
    end
    return __lsl_render_float_digits(significand, digit_count, exponent, negative)
end

function __lsl_parse_int(text):
    length = len(text)
    if length > 4096:
        Error(ValueError: "Int String exceeds 4096 characters")
    end
    index = 0
    sign = 1
    if length > 0 and text[0] == "-":
        sign = -1
        index = 1
    elif length > 0 and text[0] == "+":
        index = 1
    end
    if index >= length:
        Error(ValueError: "invalid Int String")
    end
    value = 0
    while index < length:
        code = ord(text[index])
        if code < 48 or code > 57:
            Error(ValueError: "invalid Int String")
        end
        value = value * 10 + (code - 48)
        index += 1
    end
    return value * sign
end

function __lsl_int_any(value):
    value_type = __lsl_type_code(value)
    if value_type == 0:
        return value
    elif value_type == 9:
        return __lsl_unbox_int(value)
    elif value_type == 1:
        return __lsl_parse_int(value)
    elif value_type == 6:
        return __lsl_float_to_int(value)
    elif value_type == 4:
        return __lsl_unbox_bool(value)
    end
    Error(TypeError: "Int expects Int, Float, String, or Bool")
end

function __lsl_int_to_string(number):
    if number == 0:
        return "0"
    end
    if number == -9223372036854775808:
        return "-9223372036854775808"
    end
    negative = False
    remaining = number
    if remaining < 0:
        negative = True
        remaining = -remaining
    end
    digits = ""
    while remaining > 0:
        digit = remaining % 10
        digits = chr(48 + digit) + digits
        remaining = remaining // 10
    end
    if negative:
        return "-" + digits
    end
    return digits
end

function __lsl_bit_operand(value):
    # Bitwise operators are Int-only. A raw Int passes straight through, a boxed
    # Int is unboxed and a Bool counts as 0/1 like Python. Anything else is a
    # typed failure, because reinterpreting a live pointer as Int bits would
    # silently corrupt the value instead of reporting the mistake.
    code = __lsl_type_code(value)
    if code == 9:
        return __lsl_unbox_int(value)
    end
    if code == 4:
        if __lsl_unbox_bool(value):
            return 1
        end
        return 0
    end
    if __lsl_is_heap(value):
        Error(TypeError: "bitwise operators require Int operands")
    end
    return __lsl_raw_int(value)
end

function __lsl_require_rang_step(value):
    if __lsl_type_code(value) == 9:
        return __lsl_unbox_int(value)
    end
    if __lsl_is_heap(value):
        Error(TypeError: "rang step must be an Int")
    end
    return __lsl_raw_int(value)
end

function __lsl_render_active(value, active):
    for item in active:
        if __lsl_raw_equal(item, value):
            return True
        end
    end
    return False
end

function __lsl_render_seen(value, quote, active, depth):
    if depth > 64:
        return "..."
    end
    if not __lsl_is_heap(value):
        return __lsl_int_to_string(value)
    end
    code = __lsl_type_code(value)
    if code == 0:
        return __lsl_int_to_string(value)
    elif code == 9:
        return __lsl_int_to_string(__lsl_unbox_int(value))
    elif code == 1:
        if quote:
            return "'" + value + "'"
        end
        return value
    elif code == 4:
        if __lsl_unbox_bool(value):
            return "True"
        end
        return "False"
    elif code == 5:
        return "None"
    elif code == 6:
        return __lsl_format_float(value)
    elif code == 10:
        return "<Function>"
    elif code == 11:
        return "<NativeLibrary>"
    elif code == 12:
        return "<NativeFunction>"
    elif code == 3:
        if __lsl_render_active(value, active):
            return "{...}"
        end
        active.append(value)
        result = ["{"]
        first = True
        for key in value.keys():
            if not first:
                result.append(", ")
            end
            result.append(__lsl_render_seen(key, True, active, depth + 1))
            result.append(": ")
            result.append(__lsl_render_seen(value[key], True, active, depth + 1))
            first = False
        end
        result.append("}")
        call __lsl_pop(active)
        return "".join(result)
    elif code == 13:
        result = ["IntArray(["]
        index = 0
        while index < len(value):
            if index > 0:
                result.append(", ")
            end
            result.append(__lsl_int_to_string(Int(value[index])))
            index += 1
        end
        result.append("])")
        return "".join(result)
    elif code == 14:
        result = ["FloatArray(["]
        index = 0
        while index < len(value):
            if index > 0:
                result.append(", ")
            end
            result.append(__lsl_format_float(Float(value[index])))
            index += 1
        end
        result.append("])")
        return "".join(result)
    elif code == 15:
        result = ["ByteArray(["]
        index = 0
        while index < len(value):
            if index > 0:
                result.append(", ")
            end
            result.append(__lsl_int_to_string(Int(value[index])))
            index += 1
        end
        result.append("])")
        return "".join(result)
    elif code != 2 and code != 7 and code != 8:
        return "<Object>"
    end
    open_bracket = "["
    close_bracket = "]"
    if code == 7:
        open_bracket = "("
        close_bracket = ")"
    elif code == 8:
        open_bracket = "!["
    end
    if __lsl_render_active(value, active):
        return open_bracket + "..." + close_bracket
    end
    active.append(value)
    result = [open_bracket]
    index = 0
    length = len(value)
    while index < length:
        if index > 0:
            result.append(", ")
        end
        result.append(__lsl_render_seen(value[index], True, active, depth + 1))
        index += 1
    end
    result.append(close_bracket)
    call __lsl_pop(active)
    return "".join(result)
end

function __lsl_render(value, quote):
    return __lsl_render_seen(value, quote, [], 0)
end

function __lsl_str_value(value):
    return __lsl_render(value, False)
end

function __lsl_type_name(value):
    code = __lsl_type_code(value)
    if code == 0 or code == 9:
        return "Int"
    elif code == 1:
        return "String"
    elif code == 2:
        return "List"
    elif code == 3:
        return "Dictionary"
    elif code == 4:
        return "Bool"
    elif code == 5:
        return "None"
    elif code == 6:
        return "Float"
    elif code == 7:
        return "Tuple"
    elif code == 8:
        return "RealArray"
    elif code == 10:
        return "Function"
    elif code == 13:
        return "IntArray"
    elif code == 14:
        return "FloatArray"
    elif code == 15:
        return "ByteArray"
    end
    return "Any"
end

function __lsl_list_concat(left, right):
    result = []
    for value in left:
        result.append(value)
    end
    for value in right:
        result.append(value)
    end
    return result
end

function __lsl_public_add(left, right):
    left_type = __lsl_type_code(left)
    right_type = __lsl_type_code(right)
    if left_type == 2 or right_type == 2:
        if left_type == 2 and right_type == 2:
            return __lsl_list_concat(left, right)
        end
        Error(TypeError: "numeric operands required")
    elif left_type == 1 or right_type == 1:
        if left_type == 1 and right_type == 1:
            return left + right
        end
        Error(TypeError: "numeric operands required")
    end
    left_numeric = left_type == 9 or left_type == 4 or left_type == 6
    right_numeric = right_type == 9 or right_type == 4 or right_type == 6
    if not left_numeric or not right_numeric:
        Error(TypeError: "numeric operands required")
    elif left_type == 6 or right_type == 6:
        return Float(left) + Float(right)
    end
    # This helper crosses the public Any ABI. Keep integer results tagged just
    # like the native dynamic arithmetic runtime does; returning the raw Int
    # would make a following dynamic operation interpret its bits as a pointer.
    return __lsl_box_int(Int(left) + Int(right))
end

function __lsl_public_multiply(left, right):
    left_type = __lsl_type_code(left)
    right_type = __lsl_type_code(right)
    left_integer = left_type == 9 or left_type == 4
    right_integer = right_type == 9 or right_type == 4
    if left_type == 1 or right_type == 1:
        if left_type == 1 and right_integer:
            return __lsl_str_repeat(left, Int(right))
        elif right_type == 1 and left_integer:
            return __lsl_str_repeat(right, Int(left))
        end
        Error(TypeError: "numeric operands required")
    end
    left_numeric = left_integer or left_type == 6
    right_numeric = right_integer or right_type == 6
    if not left_numeric or not right_numeric:
        Error(TypeError: "numeric operands required")
    elif left_type == 6 or right_type == 6:
        return Float(left) * Float(right)
    end
    return __lsl_box_int(Int(left) * Int(right))
end

function __lsl_float_floor(x):
    # floor of a Float, returned as Float. Int() truncates toward zero.
    truncated = Float(Int(x))
    if truncated > x:
        return truncated - 1.0
    end
    return truncated
end

function __lsl_ffloordiv(a, b):
    left = Float(a)
    right = Float(b)
    if right == 0.0:
        Error(ZeroDivisionError: "float floor division by zero")
    end
    return __lsl_float_floor(left / right)
end

function __lsl_fmod(a, b):
    left = Float(a)
    right = Float(b)
    if right == 0.0:
        Error(ZeroDivisionError: "float modulo by zero")
    end
    return left - __lsl_float_floor(left / right) * right
end

function __lsl_floordiv_dyn(a, b):
    # Both operands are Any (only reachable from user Any // Any). Boxed Int
    # remains on the exact signed Int path; boxed Float selects Float semantics.
    a_type = __lsl_type_code(a)
    b_type = __lsl_type_code(b)
    if a_type == 6 or b_type == 6:
        return __lsl_ffloordiv(a, b)
    end
    left = __lsl_raw_int(a)
    right = __lsl_raw_int(b)
    if a_type == 9 or a_type == 4:
        left = Int(a)
    end
    if b_type == 9 or b_type == 4:
        right = Int(b)
    end
    return left // right
end

function __lsl_mod_dyn(a, b):
    a_type = __lsl_type_code(a)
    b_type = __lsl_type_code(b)
    if a_type == 6 or b_type == 6:
        return __lsl_fmod(a, b)
    end
    left = __lsl_raw_int(a)
    right = __lsl_raw_int(b)
    if a_type == 9 or a_type == 4:
        left = Int(a)
    end
    if b_type == 9 or b_type == 4:
        right = Int(b)
    end
    return left % right
end

function __lsl_public_floordiv_dyn(a, b):
    a_type = __lsl_type_code(a)
    b_type = __lsl_type_code(b)
    if a_type == 6 or b_type == 6:
        return __lsl_ffloordiv(a, b)
    end
    return __lsl_box_int(Int(a) // Int(b))
end

function __lsl_public_mod_dyn(a, b):
    a_type = __lsl_type_code(a)
    b_type = __lsl_type_code(b)
    if a_type == 6 or b_type == 6:
        return __lsl_fmod(a, b)
    end
    return __lsl_box_int(Int(a) % Int(b))
end

function __lsl_slice3(target, start, has_start, stop, has_stop, step):
    # General strided slice with Python semantics. step != 0. Negative step
    # flips the default bounds. Returns String for String targets, else List
    # (codegen retags Tuple/RealArray).
    target = __lsl_require_sequence(target)
    if step == 0:
        Error(ValueError: "slice step cannot be zero")
    end
    length = len(target)
    if not has_start:
        if step > 0:
            start = 0
        else:
            start = length - 1
        end
    else:
        if start < 0:
            start += length
        end
        if step > 0:
            if start < 0:
                start = 0
            elif start > length:
                start = length
            end
        else:
            if start < 0:
                start = -1
            elif start > length - 1:
                start = length - 1
            end
        end
    end
    if not has_stop:
        if step > 0:
            stop = length
        else:
            stop = -1
        end
    else:
        if stop < 0:
            stop += length
        end
        if step > 0:
            if stop < 0:
                stop = 0
            elif stop > length:
                stop = length
            end
        else:
            if stop < 0:
                stop = -1
            elif stop > length - 1:
                stop = length - 1
            end
        end
    end
    target_type = __lsl_type_code(target)
    is_string = target_type == 1
    parts = []
    if target_type == 13:
        parts = IntArray()
    elif target_type == 14:
        parts = FloatArray()
    elif target_type == 15:
        parts = ByteArray()
    end
    index = start
    if step > 0:
        while index < stop:
            parts.append(target[index])
            index += step
        end
    else:
        while index > stop:
            parts.append(target[index])
            index += step
        end
    end
    if is_string:
        return "".join(parts)
    elif target_type == 7:
        return Tuple(parts)
    elif target_type == 8:
        return RealArray(parts)
    end
    return parts
end

function __lsl_str_repeat(text, count):
    checked_text = String(text)
    if count <= 0 or len(checked_text) == 0:
        return ""
    end
    byte_count = __lsl_text_byte_length(checked_text)
    if byte_count > 0 and count > 67108864 // byte_count:
        Error(ValueError: "repeated String exceeds 64 MiB")
    end
    total = byte_count * count
    result = __lsl_byte_zeros(total)
    target = 0
    repetition = 0
    while repetition < count:
        source = 0
        while source < byte_count:
            result[target] = __lsl_text_byte(checked_text, source)
            source += 1
            target += 1
        end
        repetition += 1
    end
    return __lsl_text_from_bytes(result, 0, total)
end

function __lsl_equal_seen(left, right, seen_left, seen_right, depth):
    if __lsl_raw_equal(left, right):
        return True
    end
    if depth > 64:
        Error(ValueError: "comparison nesting exceeds 64 levels")
    end
    left_code = __lsl_type_code(left)
    right_code = __lsl_type_code(right)
    if left_code != right_code:
        return False
    end
    if left_code == 2 or left_code == 7 or left_code == 8 or left_code == 3:
        seen_index = 0
        while seen_index < len(seen_left):
            if __lsl_raw_equal(seen_left[seen_index], left):
                return __lsl_raw_equal(seen_right[seen_index], right)
            end
            seen_index += 1
        end
        seen_left.append(left)
        seen_right.append(right)
    end
    if left_code == 2 or left_code == 7 or left_code == 8:
        length = len(left)
        if length != len(right):
            return False
        end
        index = 0
        while index < length:
            if not __lsl_equal_seen(left[index], right[index], seen_left, seen_right, depth + 1):
                return False
            end
            index += 1
        end
        return True
    elif left_code == 13:
        length = len(left)
        if length != len(right):
            return False
        end
        index = 0
        while index < length:
            if Int(left[index]) != Int(right[index]):
                return False
            end
            index += 1
        end
        return True
    elif left_code == 14:
        length = len(left)
        if length != len(right):
            return False
        end
        index = 0
        while index < length:
            left_value = Float(left[index])
            right_value = Float(right[index])
            if left_value != right_value:
                return False
            end
            index += 1
        end
        return True
    elif left_code == 15:
        length = len(left)
        if length != len(right):
            return False
        end
        index = 0
        while index < length:
            if Int(left[index]) != Int(right[index]):
                return False
            end
            index += 1
        end
        return True
    elif left_code == 3:
        if len(left) != len(right):
            return False
        end
        for key in left.keys():
            if not (key in right):
                return False
            end
            if not __lsl_equal_seen(left[key], right[key], seen_left, seen_right, depth + 1):
                return False
            end
        end
        return True
    end
    return __lsl_raw_equal(left, right)
end

function __lsl_equal(left, right):
    if __lsl_raw_equal(left, right):
        return True
    end
    left_code = __lsl_type_code(left)
    right_code = __lsl_type_code(right)
    if left_code != right_code:
        return False
    end
    if left_code == 2 or left_code == 7 or left_code == 8 or left_code == 13 or left_code == 14 or left_code == 15 or left_code == 3:
        return __lsl_equal_seen(left, right, [], [], 0)
    end
    return False
end

function __lsl_public_minmax_int_array(values, maximize):
    typed_values = IntArray(values)
    if len(typed_values) == 0:
        if maximize:
            Error(ValueError: "max of empty sequence")
        end
        Error(ValueError: "min of empty sequence")
    end
    result = typed_values[0]
    index = 1
    while index < len(typed_values):
        value = typed_values[index]
        if (maximize and value > result) or (not maximize and value < result):
            result = value
        end
        index += 1
    end
    return __lsl_box_int(result)
end

function __lsl_public_minmax_float_array(values, maximize):
    typed_values = FloatArray(values)
    if len(typed_values) == 0:
        if maximize:
            Error(ValueError: "max of empty sequence")
        end
        Error(ValueError: "min of empty sequence")
    end
    result = typed_values[0]
    index = 1
    while index < len(typed_values):
        value = typed_values[index]
        if (maximize and value > result) or (not maximize and value < result):
            result = value
        end
        index += 1
    end
    return result
end

function __lsl_public_minmax_byte_array(values, maximize):
    typed_values = ByteArray(values)
    if len(typed_values) == 0:
        if maximize:
            Error(ValueError: "max of empty sequence")
        end
        Error(ValueError: "min of empty sequence")
    end
    result = typed_values[0]
    index = 1
    while index < len(typed_values):
        value = typed_values[index]
        if (maximize and value > result) or (not maximize and value < result):
            result = value
        end
        index += 1
    end
    return __lsl_box_int(result)
end

function __lsl_min(values):
    values = __lsl_require_sequence(values)
    values_type = __lsl_type_code(values)
    if values_type == 13:
        return __lsl_public_minmax_int_array(values, False)
    elif values_type == 14:
        return __lsl_public_minmax_float_array(values, False)
    elif values_type == 15:
        return __lsl_public_minmax_byte_array(values, False)
    end
    first = True
    result = None
    for value in values:
        if first or __lsl_public_compare(value, result) < 0:
            result = value
        end
        first = False
    end
    if first:
        Error(ValueError: "min of empty sequence")
    end
    return result
end

function __lsl_max(values):
    values = __lsl_require_sequence(values)
    values_type = __lsl_type_code(values)
    if values_type == 13:
        return __lsl_public_minmax_int_array(values, True)
    elif values_type == 14:
        return __lsl_public_minmax_float_array(values, True)
    elif values_type == 15:
        return __lsl_public_minmax_byte_array(values, True)
    end
    first = True
    result = None
    for value in values:
        if first or __lsl_public_compare(value, result) > 0:
            result = value
        end
        first = False
    end
    if first:
        Error(ValueError: "max of empty sequence")
    end
    return result
end

function __lsl_delete_at(target, position):
    length = len(target)
    if position < 0:
        position += length
    end
    if position < 0 or position >= length:
        Error(IndexError: "del index out of range")
    end
    index = position
    while index + 1 < length:
        target[index] = target[index + 1]
        index += 1
    end
    call __lsl_pop_last(target)
end

function __lsl_insert(target, position, value):
    if position < 0:
        position += len(target)
    end
    if position < 0:
        position = 0
    elif position > len(target):
        position = len(target)
    end
    call target.append(None)
    index = len(target) - 1
    while index > position:
        target[index] = target[index - 1]
        index -= 1
    end
    target[position] = value
end

function __lsl_list_find(target, value):
    index = 0
    while index < len(target):
        if target[index] == value:
            return index
        end
        index += 1
    end
    return -1
end

function __lsl_list_index(target, value):
    position = __lsl_list_find(target, value)
    if position < 0:
        Error(ValueError: "value is not in collection")
    end
    return position
end

function __lsl_pop(target):
    if len(target) == 0:
        Error(IndexError: "pop from empty List")
    end
    return __lsl_pop_last(target)
end

function __lsl_pop_at(target, position):
    length = len(target)
    if position < 0:
        position += length
    end
    if position < 0 or position >= length:
        Error(IndexError: "pop index out of range")
    end
    value = target[position]
    call __lsl_delete_at(target, position)
    return value
end

function __lsl_list_count(target, value):
    result = 0
    for item in target:
        if item == value:
            result += 1
        end
    end
    return result
end

function __lsl_remove(target, value):
    position = __lsl_list_find(target, value)
    if position < 0:
        Error(ValueError: "value is not in List")
    end
    call __lsl_delete_at(target, position)
end

function __lsl_reverse(target):
    left = 0
    right = len(target) - 1
    while left < right:
        temporary = target[left]
        target[left] = target[right]
        target[right] = temporary
        left += 1
        right -= 1
    end
end

function __lsl_sort(target):
    length = len(target)
    if length < 2:
        return
    end
    source = target[0:length]
    destination = target
    width = 1
    while width < length:
        left = 0
        while left < length:
            middle = min(left + width, length)
            stop = min(left + width + width, length)
            first = left
            second = middle
            output = left
            while output < stop:
                if first < middle and (second >= stop or __lsl_public_compare(source[first], source[second]) <= 0):
                    destination[output] = source[first]
                    first += 1
                else:
                    destination[output] = source[second]
                    second += 1
                end
                output += 1
            end
            left += width + width
        end
        temporary = source
        source = destination
        destination = temporary
        width += width
    end
    if not __lsl_raw_equal(source, target):
        index = 0
        while index < length:
            target[index] = source[index]
            index += 1
        end
    end
end

function __lsl_public_compare(left, right):
    left_type = __lsl_type_code(left)
    right_type = __lsl_type_code(right)
    if left_type == 1 or right_type == 1:
        if left_type != 1 or right_type != 1:
            Error(TypeError: "sort values must have compatible types")
        end
        limit = min(len(left), len(right))
        index = 0
        while index < limit:
            left_code = ord(left[index])
            right_code = ord(right[index])
            if left_code < right_code:
                return -1
            elif left_code > right_code:
                return 1
            end
            index += 1
        end
        if len(left) < len(right):
            return -1
        elif len(left) > len(right):
            return 1
        end
        return 0
    end
    left_numeric = left_type == 9 or left_type == 4 or left_type == 6
    right_numeric = right_type == 9 or right_type == 4 or right_type == 6
    if not left_numeric or not right_numeric:
        Error(TypeError: "sort values must be numeric or String")
    end
    if left_type == 6 or right_type == 6:
        left_float = Float(left)
        right_float = Float(right)
        if left_float < right_float:
            return -1
        elif left_float > right_float:
            return 1
        end
        return 0
    end
    left_int = Int(left)
    right_int = Int(right)
    if left_int < right_int:
        return -1
    elif left_int > right_int:
        return 1
    end
    return 0
end

function __lsl_copy(target):
    return target[0:len(target)]
end

function __lsl_dict_get(target, key, default_value):
    if key in target:
        return target[key]
    end
    return default_value
end

function __lsl_setdefault(target, key, default_value):
    if key not in target:
        target[key] = default_value
    end
    return target[key]
end

function __lsl_update(target, values):
    values = __lsl_require_dictionary(values)
    for key in values.keys():
        target[key] = values[key]
    end
end

function __lsl_dictionary(values):
    if __lsl_type_code(values) == 3:
        return __lsl_dict_copy(values)
    end
    values = __lsl_list(values)
    result = {}
    for entry in values:
        entry = __lsl_list(entry)
        if len(entry) != 2:
            Error(ValueError: "Dictionary entries must contain two values")
        end
        result[entry[0]] = entry[1]
    end
    return result
end

function __lsl_dict_values(target):
    result = []
    for key in target.keys():
        result.append(target[key])
    end
    return result
end

function __lsl_dict_items(target):
    result = []
    for key in target.keys():
        result.append((key, target[key]))
    end
    return result
end

function __lsl_dict_copy(target):
    result = {}
    call result.update(target)
    return result
end

function __lsl_dict_clear(target):
    keys = target.keys()
    for key in keys:
        del(target[key])
    end
end

function __lsl_dict_pop(target, key):
    value = target[key]
    del(target[key])
    return value
end

function __lsl_dict_pop_default(target, key, default_value):
    if key not in target:
        return default_value
    end
    return __lsl_dict_pop(target, key)
end

function __lsl_replace(text, old_value, new_value):
    checked_text = String(text)
    checked_old = String(old_value)
    checked_new = String(new_value)
    old_length = len(checked_old)
    pieces = []
    output_bytes = 0
    if old_length == 0:
        new_bytes = __lsl_text_byte_length(checked_new)
        text_bytes = __lsl_text_byte_length(checked_text)
        if new_bytes > 0 and len(checked_text) + 1 > (67108864 - min(text_bytes, 67108864)) // new_bytes:
            Error(ValueError: "replaced String exceeds 64 MiB")
        end
        pieces.append(checked_new)
        for character in checked_text:
            pieces.append(character)
            pieces.append(checked_new)
        end
        return "".join(pieces)
    end
    if len(checked_text) > 100000000 // old_length:
        Error(ValueError: "String replace exceeds the safe work limit")
    end
    index = 0
    while index < len(checked_text):
        matches = False
        if index + old_length <= len(checked_text):
            matches = True
            offset = 0
            while offset < old_length:
                if checked_text[index + offset] != checked_old[offset]:
                    matches = False
                    break
                end
                offset += 1
            end
        end
        if matches:
            piece = checked_new
            index += old_length
        else:
            piece = checked_text[index]
            index += 1
        end
        output_bytes += __lsl_text_byte_length(String(piece))
        if output_bytes > 67108864:
            Error(ValueError: "replaced String exceeds 64 MiB")
        end
        pieces.append(piece)
    end
    return "".join(pieces)
end

function __lsl_count(text, needle):
    text = __lsl_require_string(text)
    needle = __lsl_require_string_value(needle)
    count = 0
    offset = 0
    while offset <= len(text) - len(needle):
        found = __lsl_find_offset(text, needle, offset)
        if found < 0:
            break
        end
        count += 1
        step = len(needle)
        if step < 1:
            step = 1
        end
        offset = found + step
    end
    return count
end

function __lsl_find_offset(text, needle, offset):
    if len(needle) > 0 and len(text) - min(max(offset, 0), len(text)) > 100000000 // len(needle):
        Error(ValueError: "substring search exceeds the safe work limit")
    end
    limit = len(text) - len(needle)
    start = offset
    while start <= limit:
        matches = True
        index = 0
        while index < len(needle):
            if text[start + index] != needle[index]:
                matches = False
                break
            end
            index += 1
        end
        if matches:
            return start
        end
        start += 1
    end
    return -1
end
