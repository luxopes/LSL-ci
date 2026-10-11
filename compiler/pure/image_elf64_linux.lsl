# Formát obrazu a layout sekcí pro současný Linux port.

load bytes
load elf_image
load object_code
load relocations_x86_64

function write(program, target):
    call object_code.validate(program)
    if target["os"] != "linux" or target["architecture"] != program["architecture"] or target["image_format"] != "elf64-linux" or target["elf_machine"] != 62 or target["segment_alignment"] != 4096:
        Error(CompileError: "incompatible Linux ELF target descriptor")
    end
    if len(program["imports"]) != 0:
        Error(CompileError: "static Linux ELF does not support external imports")
    end
    # Relokace nepozmění objekt, aby mohl být opakovaně materializován.
    code = ByteArray()
    call bytes.extend_bytes(code, program["code"])
    addresses = {"code": 0, "data": len(code)}
    call relocations_x86_64.apply(program, code, addresses)
    return elf_image.image_entry(code, program["data"], program["entry_offset"], target["elf_machine"], target["segment_alignment"])
end
