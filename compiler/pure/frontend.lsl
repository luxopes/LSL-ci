# Frontend připravuje společný analyzovaný program nezávisle na cílovém CPU.

load host
load target
load linker
load parser
load semantic
load validation

function prepare(path, source, stdlib_source, safety_mode, internal_abi, platform_module=""):
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
    if safety_mode != 0:
        if String(source).find("# lsl: unchecked-intarray") >= 0:
            Error(CompileError: "unchecked-intarray requires lsl compile --unsafe")
        end
    end
    program.extend(linker.link_mode_options(path, source, safety_mode, internal_abi, platform_module))
    # Trust core sbírá odpad na hranicích fází, mimo raw konstrukční helpery.
    call gc()
    unit = validation.prepare(semantic.analyze(path, source, program, internal_abi))
    unit["platform_module"] = platform_module
    return unit
end
