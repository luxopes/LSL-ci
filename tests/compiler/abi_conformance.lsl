load backend_x86_64
load frontend
load image_writer
load target
load update_install

work = update_install.private_work("/tmp")
stdlib_source = readfile("compiler/pure/dynamic_stdlib.lsl")
# Devátý argument je na zásobníku; defaults/keywords, metody a callbacky sdílí kontrakt.
source = "function wide(a, b, c, d, e, f, g, h, i=9):\n    return a + b + c + d + e + f + g + h + i\nend\nfunction identity(value):\n    return value\nend\ncallback = identity\nclass Base:\n    function init(self, a, b, c, d, e, f, g):\n        self.value = a + b + c + d + e + f + g\n    end\n    function read(self):\n        return self.value\n    end\nend\nprint wide(1, 2, 3, 4, 5, 6, 7, 8)\nprint wide(i=10, h=8, g=7, f=6, e=5, d=4, c=3, b=2, a=1)\nobject = Base(1, 2, 3, 4, 5, 6, 7)\nprint object.read()\nvalues = [callback(42), callback(True), callback(None)]\ncall gc()\nprint type(values[0]), values[0], type(values[1]), values[1], type(values[2]), values[2]\ntry:\n    call wide(1)\nelse:\n    print \"caught arguments\"\nend\ntry:\n    print -\"text\"\nelse:\n    print \"caught operand\"\nend\n"
unit = frontend.prepare("abi-probe.lsl", source, stdlib_source, 1, False)
image = image_writer.write(backend_x86_64.generate_object(unit, target.resolve("linux-x86_64")), target.resolve("linux-x86_64"))
executable = work + "/probe"
call writebytes(executable, image)
output = capture(executable, [])
check(capture_status() == 0, "ABI probe failed: " + capture_stderr())
check(output == "45\n46\n28\nInt 42 Bool True None None\ncaught arguments\ncaught operand\n", "ABI boundaries changed: " + output)

# Připravené chyby se nesmí ztratit v optimalizovaném unchecked IntArray store.
unchecked = "# lsl: unchecked-intarray\nitems = IntArray()\ncall items.append(7)\nindex = 0\nbad = \"wrong\"\ntry:\n    items[index] = bad\nelse:\n    print \"caught unchecked\"\nend\nprint items[0]\ntry:\n    items[0] += \"wrong\"\nelse:\n    print \"caught augmented\"\nend\nprint items[0]\n"
unchecked_unit = frontend.prepare("abi-unchecked.lsl", unchecked, stdlib_source, 0, False)
call writebytes(executable, image_writer.write(backend_x86_64.generate_object(unchecked_unit, target.resolve("linux-x86_64")), target.resolve("linux-x86_64")))
output = capture(executable, [])
check(capture_status() == 0 and output == "caught unchecked\n7\ncaught augmented\n7\n", "optimized store lost a prepared error: " + output + capture_stderr())

# Backend nesmí přijmout nekoherentní popis ABI ani nevalidovaný frontend.
selected = target.resolve("linux-x86_64")
selected["pointer_bytes"] = 4
rejected = False
try:
    call backend_x86_64.generate_object(unit, selected)
else:
    rejected = "incompatible x86_64 ABI" in last_error()
end
check(rejected, "backend accepted the wrong pointer ABI")
unvalidated = Dictionary(unit)
del(unvalidated["validation_version"])
rejected = False
try:
    call backend_x86_64.generate_object(unvalidated, target.resolve("linux-x86_64"))
else:
    rejected = "validated frontend" in last_error()
end
check(rejected, "backend accepted an unvalidated program")
call update_install.cleanup_scratch(work)
print "ABI stack arguments, methods, boxing, errors, GC and target contract passed"
