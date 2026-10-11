# lsl: internal-abi
load qbe_port.qbe_memory as mem
load qbe_port.qbe_stdio as stdio

function require(value, message):
    if not value:
        Error(TestFailure: message)
    end
end

format = mem.literal("v=%d u=%u x=%#x s=%-5s c=%c %%")
word = mem.cstr("ok")
rendered = mem.malloc(512)
count = stdio.snprintf(rendered, 128, format, [ -7, 42, 48879, word, 65 ])
call require(mem.text(rendered) == "v=-7 u=42 x=0xbeef s=ok    c=A %", "printf conversions")
call require(count == len(mem.text(rendered)), "snprintf count")
call stdio.snprintf(rendered, 128, format, [ -9, 17, 255, word, 66 ])
call require(mem.text(rendered) == "v=-9 u=17 x=0xff s=ok    c=B %", "cached format renders changing arguments")
call stdio.snprintf(rendered, 128, mem.literal("%08d"), [ -42 ])
call require(mem.text(rendered) == "-0000042", "numeric width formatting")
call stdio.snprintf(rendered, 128, mem.literal("[%*.*s]"), [ 6, 3, mem.cstr("hello") ])
call require(mem.text(rendered) == "[   hel]", "cached format dynamic width and precision")
snprintf_plan = mem.literal("%+05d")
call stdio.snprintf(rendered, 16, snprintf_plan, [7])
call require(stdio.snprintf(0, 0, snprintf_plan, [7]) == 5,
    "cached snprintf size-zero measurement")
call require(stdio.snprintf(rendered, 1, snprintf_plan, [7]) == 5 and
    mem.text(rendered) == "", "cached snprintf size-one truncation")
call require(stdio.snprintf(rendered, 5, snprintf_plan, [7]) == 5 and
    mem.text(rendered) == "+000", "cached snprintf truncation")
call require(stdio.snprintf(rendered, 6, snprintf_plan, [7]) == 5 and
    mem.text(rendered) == "+0007", "cached snprintf exact fit")
word_snprintf_format = mem.literal("[%*.*s]")
word_snprintf_args = mem.malloc(3 * 8)
call mem.store(word_snprintf_args + 0, 8, 6)
call mem.store(word_snprintf_args + 8, 8, 3)
call mem.store(word_snprintf_args + 16, 8, mem.cstr("hello"))
# Prime the immutable plan; subsequent native-word calls must avoid List
# construction for measurement and full-fit direct writes.
call stdio.snprintf(rendered, 32, word_snprintf_format, [6, 3, mem.cstr("hello")])
call require(stdio.snprintf_words(0, 0, word_snprintf_format,
    word_snprintf_args, 3) == 8, "word snprintf size-zero measurement")
call require(stdio.vsnprintf_words(rendered, 9, word_snprintf_format,
    word_snprintf_args, 3) == 8 and mem.text(rendered) == "[   hel]",
    "word vsnprintf exact fit with star width and precision")
call require(stdio.snprintf_words(rendered, 5, word_snprintf_format,
    word_snprintf_args, 3) == 8 and mem.text(rendered) == "[   ",
    "word snprintf truncation fallback")
call require(stdio.snprintf_words(rendered, 1, word_snprintf_format,
    word_snprintf_args, 3) == 8 and mem.text(rendered) == "",
    "word snprintf size-one fallback")
call stdio.snprintf(rendered, 128, mem.literal("%.6f"), [ 1.25 ])
call require(mem.text(rendered) == "1.250000", "default float formatting")
float_slot = mem.malloc(8)
call mem.store_float(float_slot, 2.5, False)
call stdio.snprintf(rendered, 128, mem.literal("%.6f"), [ mem.load_float(float_slot, False) ])
call require(mem.text(rendered) == "2.500000", "memory-loaded float formatting")
call stdio.snprintf(rendered, 128, mem.literal("%.2f %.2f"), [ 1.125, 1.375 ])
call require(mem.text(rendered) == "1.12 1.38", "decimal tie rounding")
call stdio.snprintf(rendered, 128, mem.literal("%.6f"), [ -0.0 ])
call require(mem.text(rendered) == "-0.000000", "negative zero formatting")
call stdio.snprintf(rendered, 128, mem.literal("%.6f"), [ 5e-324 ])
call require(mem.text(rendered) == "0.000000", "subnormal formatting")
call stdio.snprintf(rendered, 512, mem.literal("%f %F"), [ __lsl_parse_float("inf"), __lsl_parse_float("-nan") ])
call require(mem.text(rendered) == "inf -NAN", "infinity and NaN formatting")
call stdio.snprintf(rendered, 512, mem.literal("%.6f"), [ 1e300 ])
call require(mem.text(rendered) == "1000000000000000052504760255204420248704468581108159154915854115511802457988908195786371375080447864043704443832883878176942523235360430575644792184786706982848387200926575803737830233794788090059368953234970799945081119038967640880074652742780142494579258788820056842838115669472196386865459400540160.000000", "full-range large finite float formatting")
call stdio.snprintf(rendered, 128, mem.literal("[%*.*s] %+010lld %llu %#o"),
    [ 6, 3, mem.cstr("hello"), -42, 4294967296, 9 ])
call require(mem.text(rendered) == "[   hel] -000000042 4294967296 011", "star width, precision and 64-bit integer formatting")
call stdio.snprintf(rendered, 128, mem.literal("é:%d"), [7])
call require(mem.text(rendered) == "é:7" and __lsl_text_byte_length(mem.text(rendered)) == 4, "UTF-8 format literal span")
call require(stdio.snprintf(rendered, 5, mem.literal("é:%d"), [7]) == 4 and
    mem.text(rendered) == "é:7", "cached snprintf counts UTF-8 output bytes")
call stdio.snprintf(rendered, 128, mem.literal("%5.2s"), [mem.cstr("éx")])
call require(mem.text(rendered) == "   é", "string width and precision use UTF-8 bytes")
call stdio.snprintf(rendered, 128, mem.literal("%u %llu %#llx %#llo"), [ -1, -1, -1, -1 ])
call require(mem.text(rendered) == "4294967295 18446744073709551615 0xffffffffffffffff 01777777777777777777777", "unsigned 32-bit and 64-bit formatting")

small = mem.malloc(5)
count = stdio.snprintf(small, 5, mem.literal("abcdef"), [])
call require(count == 6 and mem.text(small) == "abcd", "snprintf truncation and terminator")
call require(stdio.snprintf(0, 0, mem.literal("%d %#x"), [0, 0]) == 3, "zero-size snprintf")
call stdio.snprintf(rendered, 128, mem.literal("%d %#x"), [0, 0])
call require(mem.text(rendered) == "0 0", "zero integer formatting")

dynamic_format = mem.malloc(16)
call mem.memcpy(dynamic_format, mem.cstr("%d"), 3)
call stdio.snprintf(rendered, 128, dynamic_format, [255])
call require(mem.text(rendered) == "255", "dynamic format initial contents")
call mem.store(dynamic_format, 1, 37)
call mem.store(dynamic_format + 1, 1, 120)
call mem.store(dynamic_format + 2, 1, 0)
call stdio.snprintf(rendered, 128, dynamic_format, [255])
call require(mem.text(rendered) == "ff", "dynamic format mutation at same address")
reused_format = dynamic_format
call mem.free(dynamic_format)
dynamic_format = mem.malloc(16)
call require(dynamic_format == reused_format, "malloc reuses freed format address")
call mem.memcpy(dynamic_format, mem.cstr("%s"), 3)
call stdio.snprintf(rendered, 128, dynamic_format, [word])
call require(mem.text(rendered) == "ok", "dynamic format after malloc address reuse")
call mem.free(dynamic_format)

path = "/tmp/lsl_qbe_stdio_conformance.txt"
call writefile(path, "")
file = stdio.fopen(mem.cstr(path), mem.cstr("w"))
call require(file >= 4, "fopen for output")
call require(stdio.fputs(mem.cstr("abc"), file) == 3, "fputs count")
call require(stdio.fputc(10, file) == 10, "fputc return value")
call require(stdio.fflush(file) == 0, "fflush")
call require(readfile(path) == "abc" + chr(10), "flushed file contents")
call require(stdio.fclose(file) == 0, "fclose output")

# Translated C can pass integer and pointer varargs through a caller-owned
# native word buffer without allocating a managed List for each fprintf.
word_args = mem.malloc(5 * 8)
call mem.store(word_args + 0, 8, 6)
call mem.store(word_args + 8, 8, 3)
call mem.store(word_args + 16, 8, mem.cstr("hello"))
call mem.store(word_args + 24, 8, 42)
call mem.store(word_args + 32, 8, -1)
file = stdio.fopen(mem.cstr(path), mem.cstr("w"))
word_format = mem.literal("[%*.*s]|%+06d|%u")
word_count = stdio.fprintf_words(file, word_format, word_args, 5)
call require(word_count == len("[   hel]|+00042|4294967295"),
    "native word fprintf count with star width and precision")
call require(stdio.fclose(file) == 0, "close native word output")
call require(readfile(path) == "[   hel]|+00042|4294967295",
    "native word fprintf formats pointers, signs, and unsigned values")

# Nonliteral and unsupported formats reconstruct the ordinary List only for
# the compatibility renderer, preserving mutable-format semantics.
dynamic_format = mem.malloc(16)
call mem.memcpy(dynamic_format, mem.cstr("%x"), 3)
call mem.store(dynamic_format, 1, 37)
call mem.store(dynamic_format + 1, 1, 120)
call mem.store(dynamic_format + 2, 1, 0)
call mem.store(word_args, 8, 48879)
call require(stdio.snprintf_words(rendered, 32, dynamic_format,
    word_args, 1) == 4 and mem.text(rendered) == "beef",
    "word snprintf falls back for mutable format")
call require(stdio.vsnprintf_words(rendered, 32, mem.literal("%#x"),
    word_args, 1) == 6 and mem.text(rendered) == "0xbeef",
    "word vsnprintf falls back for unsupported directive")
file = stdio.fopen(mem.cstr(path), mem.cstr("w"))
call require(stdio.fprintf_words(file, dynamic_format, word_args, 1) == 4,
    "native word fprintf falls back for dynamic formats")
call require(stdio.fprintf_words(file, mem.literal("|%#x"), word_args, 1) == 7,
    "native word fprintf falls back for unsupported cached directives")
call require(stdio.fclose(file) == 0, "close native word fallback output")
call require(readfile(path) == "beef|0xbeef", "native word fallback output remains exact")
call mem.free(dynamic_format)

call writefile(path, "old contents")
file = stdio.fopen(mem.cstr(path), mem.cstr("w"))
call require(file >= 4, "fopen truncating output descriptor")
call require(stdio.fputs(mem.cstr("before:"), file) == 7, "string output before raw file chunk")
call require(stdio.fprintf(file, mem.literal("%+05d:"), [7]) == 6, "raw formatter on file stream")
call require(stdio.fputs(mem.cstr("é"), file) == 2, "UTF-8 string between raw chunks")
call require(stdio.fprintf(file, mem.literal("%x"), [48879]) == 4, "second raw file chunk")
call require(stdio.fflush(file) == 0, "flush mixed file output")
call require(readfile(path) == "before:+0007:ébeef", "mixed raw and String file chunks preserve order")
call require(stdio.fprintf(file, mem.literal("/%s/%d"), [mem.cstr("tail"), -12]) == 9, "write after fflush keeps descriptor open")
call require(stdio.fclose(file) == 0, "fclose flushes and closes descriptor")
call require(readfile(path) == "before:+0007:ébeef/tail/-12", "fclose flushes final raw bytes")
file = stdio.fopen(mem.cstr(path), mem.cstr("a"))
call require(file >= 4, "fopen append descriptor")
call require(stdio.fprintf(file, mem.literal("|%u|"), [42]) == 4, "raw output in append mode")
call require(stdio.fflush(file) == 0, "flush append descriptor")
call require(stdio.fclose(file) == 0, "close append descriptor")
call require(readfile(path) == "before:+0007:ébeef/tail/-12|42|", "append mode retains existing file bytes")
call require(stdio.fopen(mem.cstr("/no/such/qbe_port_directory/output"), mem.cstr("w")) == 0, "fopen failure returns null handle")

file = stdio.fopen(mem.cstr(path), mem.cstr("w"))
call require(file >= 4, "fopen for repeated raw file writes")
file_format = mem.literal("%+08d/0x%x/%u\n")
file_scratch = mem.malloc(128)
file_expected_parts = []
for value in rang(3000):
    value += 1
    call stdio.fprintf(file, file_format, [value, value, value])
    call stdio.snprintf(file_scratch, 128, file_format, [value, value, value])
    file_expected_parts.append(mem.text(file_scratch))
    if value % 257 == 0:
        call stdio.fflush(file)
    end
end
call require(stdio.fclose(file) == 0, "fclose repeated raw file writes")
call require(readfile(path) == "".join(file_expected_parts), "raw file chunks remain exact across flush boundaries")

utf8 = mem.cstr("é")
utf8_buffer = mem.malloc(4)
call require(stdio.snprintf(utf8_buffer, 4, mem.literal("%s"), [utf8]) == 2, "snprintf UTF-8 byte count")
call require(mem.text(utf8_buffer) == "é", "snprintf UTF-8 bytes")
call require(stdio.snprintf(utf8_buffer, 2, mem.literal("%s"), [utf8]) == 2, "snprintf truncated UTF-8 byte count")
call require(mem.load(utf8_buffer, 1) == 195 and mem.load(utf8_buffer + 1, 1) == 0, "snprintf truncates by byte")
call require(stdio.sprintf(utf8_buffer, mem.cstr("%s"), [utf8]) == 2, "sprintf UTF-8 byte count")
call require(mem.text(utf8_buffer) == "é", "sprintf UTF-8 bytes")

expected_output = "é" + ("q" * 10000)
call writefile(path, "")
file = stdio.fopen(mem.cstr(path), mem.cstr("w"))
call require(stdio.fputs(mem.cstr(expected_output), file) == 10002, "fputs UTF-8 byte count")
call require(readfile(path) == expected_output, "large output flushes at bounded threshold")
call require(stdio.fclose(file) == 0, "fclose buffered output")

call writefile(path, "")
file = stdio.fopen(mem.cstr(path), mem.cstr("w"))
for i in rang(10000):
    result = stdio.fputc(120, file)
    if result != 120:
        call require(False, "fputc return value in buffered loop")
    end
end
call require(stdio.fflush(file) == 0, "flush buffered fputc loop")
call require(readfile(path) == "x" * 10000, "fputc writes exact bytes across buffer flushes")
call require(stdio.fclose(file) == 0, "close buffered fputc output")

# Make a small cached-format write straddle the stream-buffer boundary. The
# first render attempt must leave the existing prefix untouched on capacity
# miss, then retry after flushing and preserve later fputs/fputc ordering.
call writefile(path, "")
file = stdio.fopen(mem.cstr(path), mem.cstr("w"))
for i in rang(8188):
    call stdio.fputc(97, file)
end
call require(stdio.fprintf(file, mem.literal("%+05d"), [7]) == 5,
    "cached format retries at buffer boundary")
call require(stdio.fputs(mem.cstr("é"), file) == 2,
    "UTF-8 fputs after cached format")
call require(stdio.fputc(122, file) == 122, "fputc after UTF-8 output")
call require(stdio.fprintf(file, mem.literal("|%#x|"), [255]) == 6,
    "alternate form falls back without losing output")
call require(stdio.fclose(file) == 0, "close mixed boundary output")
call require(readfile(path) == ("a" * 8188) + "+0007éz|0xff|",
    "mixed fputc/fprintf/fputs boundary bytes are exact")

# A single expansion larger than the stream buffer must fail measurement
# without writes, then take the allocating compatibility path exactly once.
large_piece = "b" * 9000
large_format = mem.literal("%s")
large_string = mem.cstr(large_piece)
large_rendered = mem.malloc(9001)
call stdio.snprintf(rendered, 128, large_format, [large_string])
call require(stdio.snprintf(large_rendered, 9001, large_format, [large_string]) == 9000 and
    mem.text(large_rendered) == large_piece, "cached snprintf renders beyond 8192 bytes")
call writefile(path, "")
file = stdio.fopen(mem.cstr(path), mem.cstr("w"))
call stdio.fputc(112, file)
call require(stdio.fprintf(file, mem.literal("%s"), [mem.cstr(large_piece)]) == 9000,
    "oversized cached expansion falls back")
call stdio.fputs(mem.cstr("tail"), file)
call require(stdio.fclose(file) == 0, "close oversized cached expansion")
call require(readfile(path) == "p" + large_piece + "tail",
    "oversized fallback preserves prefix and suffix")

call writefile(path, "abc" + chr(10))
file = stdio.fopen(mem.cstr(path), mem.cstr("r"))
call require(stdio.getc(file) == ord("a"), "getc first byte")
call gc()
call require(stdio.getc(file) == ord("b"), "cached input backing bytes stay alive across GC")
call require(stdio.ungetc(ord("b"), file) == ord("b"), "ungetc")
call require(stdio.fgetc(file) == ord("b"), "fgetc pushed byte")
call require(stdio.getc(file) == ord("c"), "getc stream position")
call require(stdio.getc(file) == 10, "getc newline")
call require(stdio.getc(file) == -1 and stdio.feof(file) == 1, "EOF state")
call require(stdio.fclose(file) == 0, "fclose input")

call writefile(path, "AéZ")
file = stdio.fopen(mem.cstr(path), mem.cstr("r"))
call require(stdio.getc(file) == 65, "UTF-8 stream first byte")
call require(stdio.getc(file) == 195 and stdio.getc(file) == 169, "UTF-8 stream exposes raw bytes")
call require(stdio.getc(file) == 90 and stdio.getc(file) == -1, "UTF-8 stream final byte")
call require(stdio.fclose(file) == 0, "fclose UTF-8 input")

large_count = 65536
call writefile(path, "x" * large_count)
file = stdio.fopen(mem.cstr(path), mem.cstr("r"))
seen = 0
while stdio.getc(file) >= 0:
    seen += 1
end
call require(seen == large_count, "large buffered getc byte count")
call require(stdio.fclose(file) == 0, "fclose large input")

other_path = "/tmp/lsl_qbe_stdio_conformance_other.txt"
call writefile(path, "abc")
call writefile(other_path, "XYZ")
first_file = stdio.fopen(mem.cstr(path), mem.cstr("r"))
second_file = stdio.fopen(mem.cstr(other_path), mem.cstr("r"))
call require(stdio.getc(first_file) == ord("a"), "first cached stream starts")
call require(stdio.getc(second_file) == ord("X"), "switch to second cached stream")
call require(stdio.getc(first_file) == ord("b"), "switch back restores first position")
call require(stdio.ungetc(ord("!"), first_file) == ord("!"), "cached ungetc")
call require(stdio.getc(second_file) == ord("Y"), "second cached position persists")
call require(stdio.getc(first_file) == ord("!"), "ungetc persists through stream switch")
call require(stdio.getc(first_file) == ord("c"), "first cached position continues")
call require(stdio.getc(first_file) == -1 and stdio.feof(first_file) == 1, "cached EOF state")
call require(stdio.getc(second_file) == ord("Z"), "switch after EOF")
call require(stdio.feof(first_file) == 1, "EOF state persists through stream switch")
call require(stdio.fclose(first_file) == 0, "fclose first cached stream")
call require(stdio.fclose(second_file) == 0, "fclose second cached stream")

call writefile(path, "_1.25 _0x1.8p+1")
file = stdio.fopen(mem.cstr(path), mem.cstr("r"))
single = mem.malloc(4)
double = mem.malloc(8)
call require(stdio.fscanf(file, mem.cstr("_%f"), [single]) == 1, "fscanf float")
call require(abs(mem.load_float(single, True) - 1.25) < 1e-6, "fscanf float storage")
call require(stdio.getc(file) == 32, "scanf leaves whitespace for lexer")
call require(stdio.getc(file) == ord("_") and stdio.ungetc(ord("_"), file) == ord("_"), "prepare next typed float token")
call require(stdio.fscanf(file, mem.cstr("_%lf"), [double]) == 1, "fscanf double")
call require(abs(mem.load_float(double, False) - 3.0) < 1e-12, "fscanf double storage")
call require(stdio.fclose(file) == 0, "fclose scanned stream")
call writefile(path, "s_2.2),")
file = stdio.fopen(mem.cstr(path), mem.cstr("r"))
call require(stdio.getc(file) == ord("s"), "typed float prefix")
call require(stdio.fscanf(file, mem.cstr("_%lf"), [double]) == 1, "fscanf float before punctuation")
call require(stdio.getc(file) == ord(")") and stdio.getc(file) == ord(","), "fscanf preserves closing punctuation")
call require(stdio.fclose(file) == 0, "fclose punctuation scan")
call writefile(path, "_0.125")
file = stdio.fopen(mem.cstr(path), mem.cstr("r"))
call require(stdio.fscanf(file, mem.cstr("_%lf"), [double]) == 1, "fscanf zero-valued digit")
call require(abs(mem.load_float(double, False) - 0.125) < 1e-12, "fscanf zero-valued digit conversion")
call require(stdio.fclose(file) == 0, "fclose zero scan")
call unlink(path)

print "QBE stdio passed"
