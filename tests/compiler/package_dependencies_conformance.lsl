load package
load update_install

function require(value, message):
    if not value:
        Error(TestFailure: message)
    end
end

cli = arg(1)
work = update_install.private_work("/tmp")
home = work + "/home"
call mkdir(home)
sources = work + "/registry"
call mkdir(sources)
fixtures = {
    "parent": "# lsl: requires leaf" + chr(10) + "load leaf" + chr(10) + "function answer():" + chr(10) + "    return leaf.answer()" + chr(10) + "end" + chr(10),
    "leaf": "function answer():" + chr(10) + "    return 42" + chr(10) + "end" + chr(10),
    "cycle_a": "# lsl: requires cycle_b" + chr(10),
    "cycle_b": "# lsl: requires cycle_a" + chr(10),
    "tamper": "# lsl: requires forbidden" + chr(10)
}
for name in fixtures.keys():
    call writefile(sources + "/" + name + ".lsl", fixtures[name])
    hash = capture_clean("/usr/bin/sha256sum", [sources + "/" + name + ".lsl"])[0:64]
    call writefile(sources + "/" + name + ".sha256", hash + chr(10))
end
call writefile(sources + "/tamper.sha256", "0" * 64 + chr(10))
helper = "url = arg(arg_count() - 1)" + chr(10) + "name = url.split(\"/\")[-1]" + chr(10) + "print readfile(\"" + sources + "/\" + name).strip()" + chr(10)
call writefile(work + "/fetch.lsl", helper)
call require(run(cli, ["compile", work + "/fetch.lsl", work + "/fetch"]) == 0, "compile dependency transport")
call package.install("parent", home, "http://127.0.0.1/registry", work + "/fetch", "/usr/bin/sha256sum", "/usr/bin/mv", "/usr/bin/chmod", cli)
for name in ["parent", "leaf"]:
    call require(package.verified_origin(name, home, "/usr/bin/sha256sum")["name"] == name, "dependency provenance")
end
call writefile(work + "/main.lsl", "load parent" + chr(10) + "print parent.answer()" + chr(10))
output = capture_clean("/usr/bin/env", ["-i", "HOME=" + home, cli, work + "/main.lsl"])
call require(capture_status() == 0 and output == "42" + chr(10), "installed transitive import")
for name in ["cycle_a", "tamper"]:
    caught = False
    try:
        call package.install(name, home, "http://127.0.0.1/registry", work + "/fetch", "/usr/bin/sha256sum", "/usr/bin/mv", "/usr/bin/chmod", cli)
    else:
        caught = True
    end
    call require(caught, "invalid dependency graph accepted")
    call require(not exists(package.user_path(home) + "/" + name + ".lsl"), "failed root published")
end
call require(not exists(package.user_path(home) + "/forbidden.lsl"), "unverified dependency installed")
for source in ["# lsl: requires ../bad", "# lsl: requires leaf leaf", "# lsl: requires "]:
    caught = False
    try:
        call package.dependencies(source)
    else:
        caught = True
    end
    call require(caught, "unsafe dependency header accepted")
end
call update_install.cleanup_scratch(work)
print "verified dependencies, imports, cycles and tampering passed"
