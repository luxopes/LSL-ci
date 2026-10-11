# Výběr formátu obrazu je oddělený od CPU backendu a runtime.

load image_elf64_linux
load object_code

function write(program, target):
    call object_code.validate(program)
    if program["architecture"] != target["architecture"]:
        Error(CompileError: "object architecture does not match image target")
    end
    if program["metadata"].get("target", "") != target["name"]:
        Error(CompileError: "object target does not match image target")
    end
    for field in ["abi", "runtime"]:
        if program["metadata"].get(field, "") != target[field]:
            Error(CompileError: "object " + field + " does not match image target")
        end
    end
    if target["image_format"] == "elf64-linux":
        return image_elf64_linux.write(program, target)
    end
    Error(CompileError: "image writer is not implemented: " + String(target["image_format"]))
end
