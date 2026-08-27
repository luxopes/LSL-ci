load package

home = arg(1)
server = arg(2)
helper = arg(3)
lsl = arg(4)
config = arg(5)

call package.install("registry_probe", home, server, helper, helper, helper, helper, lsl)
call package.update("registry_probe", home, server, helper, helper, helper, helper, lsl)
call package.install_config(config, home, server, helper, helper, helper, helper, lsl)

for name in ["registry_probe", "config_probe", "second_probe"]:
    destination = home + "/.local/lib/lsl/stdlib/" + name + ".lsl"
    if not exists(destination):
        Error(TestFailure: "package operation did not create " + name)
    end
    provenance = package.origin(name, home)
    if provenance["name"] != name or provenance["origin"] != server:
        Error(TestFailure: "package operation did not preserve origin for " + name)
    end
end
print "package-update-config-ok"
