# Společný vstup překladu: frontend -> výběr backendu -> obraz programu.

load frontend
load host
load qbe_toolchain
load target

function compile_mode(path, source, stdlib_source, safety_mode, internal_abi, entry_source="", target_name="", backend_path=""):
    if target_name == "":
        target_name = host.target_name()
    end
    selected = target.resolve(target_name)
    unit = frontend.prepare(path, source, stdlib_source, safety_mode, internal_abi, selected["platform_module"])
    return qbe_toolchain.image(unit, selected, entry_source, backend_path)
end
