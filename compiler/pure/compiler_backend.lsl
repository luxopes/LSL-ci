# Výběr instrukčního backendu před materializací systémového obrazu.

load backend_x86_64

function emit(unit, target, entry_source=""):
    if target["backend"] == "x86_64":
        return backend_x86_64.generate_object(unit, target, entry_source)
    end
    Error(CompileError: "instruction backend is not implemented: " + String(target["backend"]))
end
