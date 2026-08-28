load package

name = arg(1)
home = arg(2)
server = arg(3)
helper = arg(4)
lsl = arg(5)
call package.install(name, home, server, helper, helper, helper, helper, lsl)
destination = home + "/.local/lib/lsl/stdlib/" + name + ".lsl"
expected = "function registry_answer():" + chr(10) + "    return 42" + chr(10) + "end" + chr(10)
if readfile(destination) != expected:
    Error(TestFailure: "installed library source differs")
end
provenance = package.origin(name, home)
if provenance["name"] != name or provenance["origin"] != server or provenance["source"] != server + "/" + name + ".lsl" or provenance["sha256"] != "c34ee3495502162dcd7281e7c22dade9d59321397fecf344e7098f638208ea87":
    Error(TestFailure: "installed library provenance differs")
end
verified = package.verified_origin(name, home, helper)
if verified["sha256"] != provenance["sha256"]:
    Error(TestFailure: "installed library provenance verification differs")
end
call writefile(destination, expected + "# modified" + chr(10))
tamper_rejected = False
try:
    call package.verified_origin(name, home, helper)
else:
    tamper_rejected = last_error().find("differs from recorded provenance") >= 0
end
if not tamper_rejected:
    Error(TestFailure: "modified installed library retained verified provenance")
end
call writefile(destination, expected)

lock_path = home + "/.local/lib/lsl/stdlib/." + name + ".lock"
lock_target = home + "/lock-target"
call unlink(lock_path)
call writefile(lock_target, "unchanged")
if run_clean("/bin/ln", ["-s", lock_target, lock_path]) != 0:
    Error(TestFailure: "cannot create package lock symlink fixture")
end
lock_symlink_rejected = False
try:
    call package.verified_origin(name, home, helper)
else:
    lock_symlink_rejected = last_error().find("cannot open package lock") >= 0
end
if not lock_symlink_rejected:
    Error(TestFailure: "package lock followed a symbolic link")
end
staging_path = home + "/.local/lib/lsl/stdlib/." + name + ".install-" + String(__lsl_syscall(39, 0, 0, 0, 0)) + "-0"
install_lock_rejected = False
try:
    call package.install(name, home, server, helper, helper, helper, helper, lsl)
else:
    install_lock_rejected = last_error().find("cannot open package lock") >= 0
end
if not install_lock_rejected or exists(staging_path):
    Error(TestFailure: "failed package lock left staging data behind")
end
call unlink(lock_path)
call unlink(lock_target)
print "package-install-ok"
