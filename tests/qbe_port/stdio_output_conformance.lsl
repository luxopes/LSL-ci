# lsl: internal-abi
load qbe_port.qbe_memory as mem
load qbe_port.qbe_stdio as stdio
load qbe_port.qbe_libc as libc

format = mem.literal("%+08d/0x%x/%u\n")
for value in rang(10000):
    value += 1
    call stdio.fprintf(2, format, [value, value, value])
end
call stdio.fprintf(2, mem.literal("|%*.*s|%-8.3s|%d|\n"),
    [ 7, 2, mem.cstr("éx"), mem.cstr("abcdef"), -42 ])
call stdio.fprintf(2, mem.literal("%u|%X|%d|%.0d|%08.3d\n"),
    [ -1, 48879, -42, 0, 5 ])
call stdio.fprintf(2, mem.literal("|%*.*s|%-8.3s|%c|%+08d|%.5d|%u|%X|%o|\n"),
    [ 7, 2, mem.cstr("éx"), mem.cstr("abcdef"), 233, -42, -7, -1, 511, 511 ])
call libc.c_exit(0)
