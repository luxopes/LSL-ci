load abi_x86_64
load assembler_x86_64 as assembler
load backend_x86_64
load bytes
load compiler_backend
load frontend
load host
load image_writer
load pipeline
load object_code
load relocations_x86_64 as relocations
load runtime
load target
load update_install

selected = target.resolve(host.target_name())
for name in ["linux-x86_64", "windows-x86_64", "macos-x86_64"]:
    description = target.describe(name)
    check(abi_x86_64.matches(description), "OS changed the private x86_64 calling convention")
    check(description["modules"]["_fd_platform"] == "_fd_" + description["os"] + "_x86_64", "file provider is not selected by target")
    if name != selected["name"]:
        rejected = False
        try:
            call target.resolve(name)
        else:
            rejected = "not implemented" in last_error()
        end
        # Windows i macOS mají runtime v LSL přes LuxIR.
        check(not rejected, "a supported target is not available")
        rejected = False
        try:
            call runtime.select(description)
        else:
            rejected = True
        end
        check(rejected, "Linux runtime accepted another OS")
    end
end

stdlib_source = readfile("compiler/pure/dynamic_stdlib.lsl")
# Frontend zvládne tentýž zdroj s metadaty každého OS bez instrukcí či image.
for name in ["windows-x86_64", "macos-x86_64"]:
    description = target.describe(name)
    unit = frontend.prepare("portable.lsl", "print 42\n", stdlib_source, 1, False, description["platform_module"])
    check(unit["validation_version"] == 1 and unit["platform_module"] == description["platform_module"], "frontend requires a Linux image")
end
unit = frontend.prepare("object-probe.lsl", "print \"separate image\"\n", stdlib_source, 1, False, selected["platform_module"])
program = compiler_backend.emit(unit, selected)
check(program["object_version"] == 1 and program["architecture"] == "x86_64" and len(program["relocations"]) > 0, "backend did not produce an object")
original = ByteArray()
call bytes.extend_bytes(original, program["code"])
image = image_writer.write(program, selected)
check(program["code"] == original and image == image_writer.write(program, selected), "image writer mutated the object")
pipeline_image = pipeline.compile_mode("object-probe.lsl", "print \"separate image\"\n", stdlib_source, 1, False)
work = update_install.private_work("/tmp")
call writebytes(work + "/pipeline-probe", pipeline_image)
check(capture(work + "/pipeline-probe", []) == "separate image\n" and capture_status() == 0, "production pipeline behavior differs from explicit object materialization")
call writebytes(work + "/probe", image)
check(capture(work + "/probe", []) == "separate image\n" and capture_status() == 0, "relocated executable failed")
for field in ["architecture", "name", "abi", "runtime", "image_format"]:
    wrong = Dictionary(selected)
    wrong[field] = "wrong"
    rejected = False
    try:
        call image_writer.write(program, wrong)
    else:
        rejected = True
    end
    check(rejected, "image writer accepted inconsistent " + field)
end

# Relativní adresování funguje i pro oddělené sekce a záporné displacement.
code = __lsl_byte_zeros(8)
reference = relocations.data_reference(1, 5, 2)
small = object_code.program("x86_64", code, __lsl_byte_zeros(3), 0, [reference], {})
call relocations.apply(small, code, {"code": 4096, "data": 8192})
check(code[1] == 253 and code[2] == 15 and code[3] == 0 and code[4] == 0, "noncontiguous section relocation differs")
call relocations.apply(small, code, {"code": 8192, "data": 4096})
check(code[1] == 253 and code[2] == 239 and code[3] == 255 and code[4] == 255, "negative section relocation differs")
for displacement in [-2147483648, 2147483647]:
    call relocations.patch_relative32(code, 0, 0, displacement)
end
for displacement in [-2147483649, 2147483648]:
    rejected = False
    try:
        call relocations.patch_relative32(code, 0, 0, displacement)
    else:
        rejected = "signed 32-bit" in last_error()
    end
    check(rejected, "relative relocation silently truncated")
end
for patch in [-1, 5]:
    rejected = False
    try:
        call relocations.patch_relative32(code, patch, 0, 0)
    else:
        rejected = True
    end
    check(rejected, "relative patch escaped code")
end
rejected = False
try:
    call relocations.apply(small, code, {"code": 0})
else:
    rejected = "section is missing" in last_error()
end
check(rejected, "missing relocation section was accepted")
for field in ["offset", "base", "target_offset", "target_section"]:
    wrong = Dictionary(reference)
    wrong[field] = 100
    rejected = False
    try:
        call object_code.program("x86_64", code, __lsl_byte_zeros(3), 0, [wrong], {})
    else:
        rejected = True
    end
    check(rejected, "invalid object relocation " + field + " was accepted")
end
builder = assembler.builder()
call assembler.relative(builder, [233], "missing")
rejected = False
try:
    call assembler.finish(builder)
else:
    rejected = True
end
check(rejected, "assembler accepted an undefined label")
# Import zůstane nevyřešený v objektu; ELF ho musí odmítnout před zápisem.
external = assembler.builder()
name = assembler.import_symbol(external, "example-library", "example-function")
check(name == assembler.import_symbol(external, "example-library", "example-function") and len(external["imports"]) == 1, "duplicate import was created")
call assembler.export_symbol(external, "entry")
call assembler.external_relative(external, [255, 21], name)
external_program = object_code.program("x86_64", assembler.finish(external), ByteArray(), 0, external["image_relocations"], program["metadata"], external["symbols"], external["imports"])
rejected = False
try:
    call image_writer.write(external_program, selected)
else:
    rejected = "external imports" in last_error()
end
check(rejected, "static ELF silently accepted an external import")
rejected = False
try:
    call object_code.program("x86_64", external["code"], ByteArray(), 0, external["image_relocations"], {}, {}, [])
else:
    rejected = "undeclared symbol" in last_error()
end
check(rejected, "object accepted an undeclared external symbol")
call update_install.cleanup_scratch(work)
print "portable target metadata, objects, image selection and bounded relocations passed"
