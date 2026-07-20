# Tiny label/fixup assembler data structure implemented in LSL. It emits bytes;
# it never invokes an assembler executable.

load bytes

function builder():
    return {"code": [], "labels": {}, "fixups": []}
end

function position(value):
    return len(value["code"])
end

function emit(value, data):
    value["code"].extend(data)
end

function label(value, name):
    if name in value["labels"]:
        Error(AssemblerError: "duplicate label")
    end
    labels = value["labels"]
    labels[name] = position(value)
end

function relative(value, opcode, name):
    value["code"].extend(opcode)
    patch = position(value)
    value["code"].extend([0, 0, 0, 0])
    value["fixups"].append([patch, name])
end

function finish(value):
    for fixup in value["fixups"]:
        if fixup[1] not in value["labels"]:
            Error(AssemblerError: "unknown label")
        end
        target = value["labels"][fixup[1]]
        displacement = target - (fixup[0] + 4)
        call bytes.patch_little(value["code"], fixup[0], displacement, 4)
    end
    return value["code"]
end
