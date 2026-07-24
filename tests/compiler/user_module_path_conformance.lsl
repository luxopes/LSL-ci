load linker

home = "/tmp/lsl-user-module-home"
call mkdir(home)
call mkdir(home + "/.local")
call mkdir(home + "/.local/lib")
call mkdir(home + "/.local/lib/lsl")
call mkdir(home + "/.local/lib/lsl/stdlib")
user_path = home + "/.local/lib/lsl/stdlib/user_registry_probe.lsl"
call writefile(user_path, "function answer():" + chr(10) + "    return 42" + chr(10) + "end" + chr(10))
if linker.module_path_with_home("user_registry_probe", "tests/compiler/probe.lsl", home) != user_path:
    Error(TestFailure: "user module path was not selected")
end
call writefile(home + "/.local/lib/lsl/stdlib/time.lsl", "invalid")
if linker.module_path_with_home("time", "tests/compiler/probe.lsl", home) != "stdlib/time.lsl":
    Error(TestFailure: "user module shadowed a built-in module")
end
print "user-module-path-ok"
