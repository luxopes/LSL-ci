# lsl: internal-abi
# Build-time runtime provider. This is not a source compiler backend.
load runtime_linux_x86_64 as runtime
load assembler_x86_64 as assembler
load x86_64
load heap_runtime_linux_x86_64 as heap_runtime
# Rutiny z modulů compiler/runtime/*.lir (seznam MODULES) se v x86 negenerují;
# tools/qbe/runtime_object.py je přeloží LuxIR a přilinkuje.
for module_name in readfile("compiler/runtime/MODULES").split(chr(10)):
    if module_name != "":
        for line in readfile("compiler/runtime/" + module_name).split(chr(10)):
            if line.startswith("export function rt_runtime_"):
                call heap_runtime.provided_by_luxir(line[len("export function rt_"):line.find("(")])
            end
        end
    end
end
output = assembler.builder()
call runtime.emit_all(output)
call runtime.emit_lazy(output,True,True)
call assembler.label(output,"qbe_runtime_start")
call runtime.emit_entry(output,0,524288,65535)
call writebytes(arg(1)+".bin",output["code"])
lines = []
for name in output["labels"]:
    lines.append(String(output["labels"][name])+" "+name+chr(10))
end
call writefile(arg(1)+".labels","".join(lines))
lines = []
for fixup in output["fixups"]:
    lines.append(String(fixup[0])+" "+fixup[1]+chr(10))
end
call writefile(arg(1)+".fixups","".join(lines))
