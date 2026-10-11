# lsl: internal-abi
load qbe_port.qbe_memory as mem
load qbe_port.qbe_stdio as stdio

function read_byte(file):
    value = stdio.getc_ready(file)
    if value == -2:
        value = stdio.getc(file)
    end
    return value
end

path_a = "/tmp/lsl_qbe_input_cache_a"
path_b = "/tmp/lsl_qbe_input_cache_b"
text_a = ("Aé" + chr(0) + "Z") * 80
text_b = ("Bž" + chr(0) + "Y") * 80
call writefile(path_a, text_a)
call writefile(path_b, text_b)
a = stdio.fopen(mem.cstr(path_a), mem.literal("r"))
b = stdio.fopen(mem.cstr(path_b), mem.literal("r"))
check(a >= 4 and b >= 4, "open cached inputs")
for index in rang(__lsl_text_byte_length(text_a)):
    expected = __lsl_text_byte(text_a, index)
    check(read_byte(a) == expected, "cached bytes retain UTF8 and embedded NUL")
    if index % 17 == 0:
        check(stdio.ungetc(255, a) == 255, "push high byte")
        call gc()
        check(read_byte(a) == 255, "cached unread byte survives GC")
    end
    if index % 2 == 0:
        check(read_byte(b) == __lsl_text_byte(text_b, index), "switch cached inputs")
    else:
        check(stdio.getc(b) == __lsl_text_byte(text_b, index), "mix ordinary and cached readers")
    end
end
check(stdio.feof(a) == 0 and stdio.feof(b) == 0, "EOF set on read, not last byte")
check(read_byte(a) == -1 and stdio.feof(a) == 1, "cached EOF")
check(stdio.ungetc(42, a) == 42 and stdio.feof(a) == 0, "ungetc clears EOF")
check(read_byte(a) == 42 and read_byte(a) == -1, "unread at EOF")
check(read_byte(b) == -1 and stdio.feof(b) == 1, "second stream EOF")
check(read_byte(2) == -1, "output handle is not input")
check(stdio.fclose(a) == 0 and stdio.fclose(b) == 0, "close cached inputs")
check(read_byte(a) == -1, "closed input cache invalidated")
print "PASS QBE input cache"
