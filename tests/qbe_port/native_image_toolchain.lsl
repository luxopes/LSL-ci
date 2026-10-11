# lsl: internal-abi
load frontend
load qbe_toolchain
load target
source = readfile(arg(1))
unit = frontend.prepare(arg(1), source, readfile("compiler/pure/dynamic_stdlib.lsl"), 1, False)
result = qbe_toolchain.image(unit, target.resolve("linux-x86_64"), arg(4), arg(3))
call writebytes(arg(2), result)
