# Kompatibilní vstup pro existující interní uživatele codegenu.
# Produkční překlad používá pipeline; x86_64 emission je v samostatném backendu.

load backend_x86_64
load semantic
load runtime
load host
load image_writer
load target
load validation

function generate_mode(path, source, program, internal_abi, entry_source=""):
    unit = validation.prepare(semantic.analyze(path, source, program, internal_abi))
    selected = target.resolve(host.target_name())
    unit["platform_module"] = selected["platform_module"]
    return image_writer.write(backend_x86_64.generate_object(unit, selected, entry_source), selected)
end

function generate(path, source, program):
    return generate_mode(path, source, program, False)
end

function emit_statements(generator, statements, break_label, continue_label, return_label):
    if "runtime" not in generator:
        generator["runtime"] = runtime.select(target.resolve(host.target_name()))
    end
    call backend_x86_64.emit_statements(generator, statements, break_label, continue_label, return_label)
end

function expression_may_allocate(generator, syntax):
    return backend_x86_64.expression_may_allocate(generator, syntax)
end
