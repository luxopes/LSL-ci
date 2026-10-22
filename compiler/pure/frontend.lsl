# Frontend připravuje společný analyzovaný program nezávisle na cílovém CPU.

load host
load target
load linker
load parser
load semantic
load validation

function prepare(path, source, stdlib_source, safety_mode, internal_abi, platform_module="", lazy_library=False):
    if platform_module == "":
        platform_module = target.resolve(host.target_name())["platform_module"]
    end
    if safety_mode < 0 or safety_mode > 2:
        Error(CompileError: "unknown compilation safety mode")
    end
    if internal_abi and safety_mode != 0:
        Error(CompileError: "internal ABI requires compiler trust mode")
    end
    stdlib_name = "compiler/pure/dynamic_stdlib.lsl"
    program = parser.parse(stdlib_name, stdlib_source)
    call linker.annotate_statements(program, stdlib_name)
    call linker.mark_internal_abi(program, True)
    # lazy_library: funkce dynamické knihovny se analyzují a validují až při
    # prvním použití generátorem LuxIR (qbe_emit); malý program jich většinu
    # nepotřebuje. Ostatní konzumenti jednotky dostanou úplnou analýzu.
    library_functions = {}
    if lazy_library:
        for statement in program:
            if statement["kind"] == "function":
                library_functions[statement["name"]] = True
            end
        end
    end
    if safety_mode != 0:
        if String(source).find("# lsl: unchecked-intarray") >= 0:
            Error(CompileError: "unchecked-intarray requires lsl compile --unsafe")
        end
    end
    program.extend(linker.link_mode_options(path, source, safety_mode, internal_abi, platform_module))
    # Bez explicitního gc(): automatický GC stačí. Měřeno 11. 10. 2026:
    # malý program o ~10 ms rychleji, velký zdroj o ~1,5 % rychleji a se
    # stejnou nebo nižší paměťovou špičkou.
    unit = validation.prepare(semantic.analyze(path, source, program, internal_abi, library_functions))
    unit["platform_module"] = platform_module
    # Knihovny systému z hlaviček `# lsl: link` (cíl linux-x86_64-gnu).
    unit["libraries"] = List(linker.linked_libraries)
    return unit
end
