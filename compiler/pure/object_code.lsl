# Společný výsledek CPU emise. Obraz určuje virtuální adresy sekcí až poté.

function program(architecture, code, data, entry_offset, relocations, metadata, symbols=None, imports=None):
    if symbols == None:
        symbols = {}
    end
    if imports == None:
        imports = []
    end
    result = {"object_version": 1, "architecture": architecture, "code": code, "data": data, "entry_offset": entry_offset, "relocations": relocations, "metadata": metadata, "symbols": symbols, "imports": imports}
    call validate(result)
    return result
end

function validate(program):
    if program.get("object_version", 0) != 1:
        Error(CompileError: "unsupported compiler object version")
    end
    if type(program["code"]) != "ByteArray" or type(program["data"]) != "ByteArray":
        Error(CompileError: "compiler object sections must be byte arrays")
    end
    if program["entry_offset"] < 0 or program["entry_offset"] >= len(program["code"]):
        Error(CompileError: "compiler object entry is outside code")
    end
    if type(program["relocations"]) != "List" or type(program["metadata"]) != "Dictionary" or type(program["symbols"]) != "Dictionary" or type(program["imports"]) != "List":
        Error(CompileError: "invalid compiler object tables")
    end
    declared = {}
    for item in program["imports"]:
        symbol = item["symbol"]
        if type(symbol) != "String" or len(symbol) == 0 or symbol in declared or symbol in program["symbols"] or type(item["library"]) != "String" or type(item["name"]) != "String":
            Error(CompileError: "invalid or duplicate compiler object import")
        end
        declared[symbol] = True
    end
    for name in program["symbols"]:
        symbol = program["symbols"][name]
        section = symbol["section"]
        if (section != "code" and section != "data") or symbol["offset"] < 0 or symbol["offset"] > len(program[section]):
            Error(CompileError: "compiler object symbol is outside its section")
        end
    end
    for relocation in program["relocations"]:
        if relocation["section"] != "code" or relocation["offset"] < 0 or relocation["offset"] > len(program["code"]) - relocation.get("width", 4):
            Error(CompileError: "compiler object relocation is outside code")
        end
        if relocation.get("width", 4) < 1 or type(relocation["kind"]) != "String" or relocation["base"] < 0 or relocation["base"] > len(program["code"]):
            Error(CompileError: "invalid compiler object relocation kind, width or base")
        end
        if "symbol" in relocation:
            if relocation["symbol"] not in declared and relocation["symbol"] not in program["symbols"]:
                Error(CompileError: "compiler object relocation refers to an undeclared symbol")
            end
            continue
        end
        section = relocation["target_section"]
        if section != "code" and section != "data":
            Error(CompileError: "compiler object relocation refers to an unknown section")
        end
        limit = len(program[section])
        if relocation["target_offset"] < 0 or relocation["target_offset"] > limit:
            Error(CompileError: "compiler object relocation target is outside its section")
        end
    end
end
