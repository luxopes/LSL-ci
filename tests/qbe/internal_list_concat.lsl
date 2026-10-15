# lsl: internal-abi
# Vnitřní kód (moduly překladače) sčítá hodnoty typu Any rychlou cestou
# add_any_raw; dva seznamy (nebo n-tice) se musí spojit, ne slepit jako text.
TABLE = {"a": ["/usr/bin/ld", "/bin/ld", ["--no-relax"]], "b": ["x", "y", []]}

function flavor(name):
    if name.startswith("w"):
        return ["-flavor", "gnu", "-m", "i386pep"]
    end
    return 5
end

function target_flags(name):
    if name.startswith("w"):
        return TABLE["b"][2]
    end
    return TABLE["a"][2]
end

for name in ["windows", "wasm"]:
    both = flavor(name) + target_flags(name)
    print type(both), both
end
print flavor("w") + target_flags("linux")
