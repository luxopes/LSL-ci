# Pure-LSL installer. No shell, cp, libc, or foreign build tool.

function copy(source, destination):
    call writefile(destination, readfile(source))
end

prefix = arg(1)
if prefix == None:
    prefix = "/usr/local"
end

call mkdir(prefix)
call mkdir(prefix + "/bin")
call mkdir(prefix + "/lib")
call mkdir(prefix + "/lib/lsl")
call mkdir(prefix + "/lib/lsl/compiler")
call mkdir(prefix + "/lib/lsl/compiler/pure")
call mkdir(prefix + "/lib/lsl/stdlib")

call copy("compiler/pure/lsl-cli", prefix + "/bin/lsl")
call copy("compiler/pure/lslc-direct", prefix + "/bin/lslc")
call copy("compiler/pure/lsl-configure", prefix + "/bin/lsl-configure")
call copy("tests/lsl-test", prefix + "/bin/lsl-test")
call copy("compiler/pure/lsl-install", prefix + "/bin/lsl-install")

sources = [
    "assembler.lsl",
    "bytes.lsl",
    "cli.lsl",
    "codegen.lsl",
    "diagnostics.lsl",
    "dynamic_stdlib.lsl",
    "elf_image.lsl",
    "heap_runtime.lsl",
    "install.lsl",
    "io_runtime.lsl",
    "lexer.lsl",
    "linker.lsl",
    "lslc_direct.lsl",
    "native_runtime.lsl",
    "native_plugin_runtime.lsl",
    "parser.lsl",
    "process_runtime.lsl",
    "x86_64.lsl"
]
for name in sources:
    call copy("compiler/pure/" + name, prefix + "/lib/lsl/compiler/pure/" + name)
end

standard_modules = ["ai.lsl", "config.lsl", "configure.lsl", "env.lsl", "http.lsl", "json.lsl", "lux.lsl", "native.lsl", "plugin.lsl", "process.lsl", "tensor.lsl"]
for name in standard_modules:
    call copy("stdlib/" + name, prefix + "/lib/lsl/stdlib/" + name)
end

print "installed pure LSL into", prefix
