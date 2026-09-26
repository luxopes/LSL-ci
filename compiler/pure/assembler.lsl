# Tiny label/fixup assembler data structure implemented in LSL. It emits bytes;
# it never invokes an assembler executable.
#
# The code buffer is a ByteArray: it stores raw bytes instead of one boxed Int
# per byte, so the collector never has to traverse the emitted program and
# appending is a plain store. Instruction encoders still hand over short
# List[Int] values; emit copies them in a typed loop.

load bytes

function builder():
    return {"code": ByteArray(), "labels": {}, "fixups": []}
end

function position(value):
    return len(ByteArray(value["code"]))
end

function emit(value, data):
    if len(data) == 4 and data[1] == 131 and data[3] == 0 and (data[0] == 72 or data[0] == 73) and (data[2] & 248) == 248:
        # Peephole: cmp r64, 0 -> test r64, r64. Identical flags for every
        # jcc/setcc and one byte shorter. (Store-to-load elimination and
        # jump-to-next removal were measured 8-10% slower on perft and the
        # self-host build on this target, so they are deliberately absent.)
        register = data[2] & 7
        rex = 72
        if data[0] == 73:
            rex = 77
        end
        data = [rex, 133, 192 + register * 8 + register]
    end
    call bytes.extend(value["code"], data)
end

function label(value, name):
    if name in value["labels"]:
        Error(AssemblerError: "duplicate label")
    end
    labels = value["labels"]
    labels[name] = position(value)
end

function relative(value, opcode, name):
    code = ByteArray(value["code"])
    call bytes.extend(code, opcode)
    patch = len(code)
    call code.append(0)
    call code.append(0)
    call code.append(0)
    call code.append(0)
    value["fixups"].append([patch, name])
end

function finish(value):
    code = ByteArray(value["code"])
    for fixup in value["fixups"]:
        if fixup[1] not in value["labels"]:
            Error(AssemblerError: "unknown label")
        end
        target = value["labels"][fixup[1]]
        displacement = target - (fixup[0] + 4)
        call bytes.patch_little(code, fixup[0], displacement, 4)
    end
    return code
end
