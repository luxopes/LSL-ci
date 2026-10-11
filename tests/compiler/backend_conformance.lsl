load backend_x86_64
load elf_image
load frontend
load image_writer
load pipeline
load target
load update_install

work = update_install.private_work("/tmp")
stdlib_source = readfile("compiler/pure/dynamic_stdlib.lsl")
source = "function add(left, right):\n    return left + right\nend\nanswer = add(19, 23)\nprint answer\n"
unit = frontend.prepare("backend-probe.lsl", source, stdlib_source, 1, False)
bindings = Dictionary(unit["function_scopes"]["add"]["variables"])
image = image_writer.write(backend_x86_64.generate_object(unit, target.resolve("linux-x86_64")), target.resolve("linux-x86_64"))
check(unit["function_scopes"]["add"]["variables"] == bindings, "backend overwrote frontend binding IDs")
check(image[16] == 3 and image[18] == 62 and image[19] == 0, "backend emitted the wrong ELF target")
executable = work + "/probe"
call writebytes(executable, image)
output = capture(executable, [])
check(capture_status() == 0 and output == "42\n", "analyzed program did not execute correctly")

rejected = False
try:
    call pipeline.compile_mode("bad-target.lsl", "print 1\n", stdlib_source, 1, False, "", "linux-aarch64")
else:
    rejected = "unsupported compilation target" in last_error()
end
check(rejected, "unknown target silently used the x86_64 backend")
rejected = False
try:
    call backend_x86_64.generate_object(unit, {"name": "linux-aarch64"})
else:
    rejected = "cannot emit target" in last_error()
end
check(rejected, "backend accepted a different architecture")

# ELF writer může zapsat cílová metadata bez vazby na x86 instrukce.
header = elf_image.header(0, 0, 0, 183, 65536)
check(header[18] == 183 and header[19] == 0, "ELF writer ignored the machine ID")
check(header[112] == 0 and header[113] == 0 and header[114] == 1, "ELF writer ignored segment alignment")
call update_install.cleanup_scratch(work)
print "backend execution, frontend isolation, target rejection and ELF metadata passed"
