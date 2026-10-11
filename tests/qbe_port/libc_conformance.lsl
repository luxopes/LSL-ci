# lsl: internal-abi
load qbe_port.qbe_memory as mem
load qbe_port.qbe_libc as libc

function require(value, message):
    if not value:
        Error(TestFailure: message)
    end
end

call require(libc.c_isalpha(65) == 1 and libc.c_isalpha(122) == 1, "ASCII alphabetic")
call require(libc.c_isalpha(0) == 0 and libc.c_isalpha(233) == 0, "ctype zero and high byte")
call require(libc.c_isdigit(57) == 1 and libc.c_isdigit(58) == 0, "ASCII digits")
call require(libc.c_isspace(10) == 1 and libc.c_isblank(10) == 0 and libc.c_isblank(9) == 1, "ASCII whitespace")
call require(libc.c_isxdigit(70) == 1 and libc.c_isxdigit(71) == 0, "hexadecimal digits")
call require(libc.c_toupper(122) == 90 and libc.c_tolower(65) == 97 and libc.c_toupper(33) == 33, "case conversion")

# Exhaust the ASCII byte domain and the adjacent invalid values. The module's
# established behavior maps every non-EOF out-of-range input to EOF semantics.
for input_byte in rang(-2, 301):
    byte = input_byte
    if byte < 0 or byte > 255:
        byte = -1
    end
    expected_alpha = (Int(byte >= 65) & Int(byte <= 90)) | (Int(byte >= 97) & Int(byte <= 122))
    expected_digit = Int(byte >= 48) & Int(byte <= 57)
    expected_alnum = expected_alpha | expected_digit
    expected_blank = Int(byte == 32) | Int(byte == 9)
    expected_space = expected_blank | (Int(byte >= 10) & Int(byte <= 13))
    expected_cntrl = (Int(byte >= 0) & Int(byte < 32)) | Int(byte == 127)
    expected_print = Int(byte >= 32) & Int(byte <= 126)
    expected_graph = Int(byte >= 33) & Int(byte <= 126)
    expected_lower = Int(byte >= 97) & Int(byte <= 122)
    expected_upper = Int(byte >= 65) & Int(byte <= 90)
    expected_xdigit = expected_digit | (Int(byte >= 65) & Int(byte <= 70)) | (Int(byte >= 97) & Int(byte <= 102))
    expected_punct = (Int(byte >= 33) & Int(byte <= 47)) | (Int(byte >= 58) & Int(byte <= 64)) | (Int(byte >= 91) & Int(byte <= 96)) | (Int(byte >= 123) & Int(byte <= 126))
    call require(libc.c_isalpha(input_byte) == expected_alpha, "ctype isalpha byte range")
    call require(libc.c_isdigit(input_byte) == expected_digit, "ctype isdigit byte range")
    call require(libc.c_isalnum(input_byte) == expected_alnum, "ctype isalnum byte range")
    call require(libc.c_isblank(input_byte) == expected_blank, "ctype isblank byte range")
    call require(libc.c_isspace(input_byte) == expected_space, "ctype isspace byte range")
    call require(libc.c_iscntrl(input_byte) == expected_cntrl, "ctype iscntrl byte range")
    call require(libc.c_isprint(input_byte) == expected_print, "ctype isprint byte range")
    call require(libc.c_isgraph(input_byte) == expected_graph, "ctype isgraph byte range")
    call require(libc.c_islower(input_byte) == expected_lower, "ctype islower byte range")
    call require(libc.c_isupper(input_byte) == expected_upper, "ctype isupper byte range")
    call require(libc.c_isxdigit(input_byte) == expected_xdigit, "ctype isxdigit byte range")
    call require(libc.c_ispunct(input_byte) == expected_punct, "ctype ispunct byte range")
end

end_pointer = mem.malloc(8)
number = mem.cstr("  -0x2a tail")
call require(libc.c_strtol(number, end_pointer, 0) == -42, "base-detected signed integer")
call require(mem.load(end_pointer, 8) == number + 7, "integer end pointer")

number = mem.cstr("077xyz")
call require(libc.c_strtoul(number, end_pointer, 0) == 63, "octal unsigned integer")
call require(mem.load(end_pointer, 8) == number + 3, "octal end pointer")

number = mem.cstr("18446744073709551615!")
call require(libc.c_strtoull(number, end_pointer, 10) == -1, "unsigned 64-bit wrap")
call require(mem.load(end_pointer, 8) == number + 20, "unsigned 64-bit end pointer")

number = mem.cstr("9223372036854775808!")
call require(libc.c_strtoll(number, end_pointer, 10) == 9223372036854775807, "signed overflow saturation")
call require(mem.load(end_pointer, 8) == number + 19, "overflow end pointer")

number = mem.cstr("no digits")
call require(libc.c_strtol(number, end_pointer, 10) == 0 and mem.load(end_pointer, 8) == number, "no conversion end pointer")

number = mem.cstr(" -12.5e2 rest")
float_value = libc.c_strtod(number, end_pointer)
call require(abs(float_value + 1250.0) < 1e-9, "decimal floating conversion")
call require(mem.load(end_pointer, 8) == number + 8, "decimal float end pointer")

float_value = libc.c_strtod(mem.cstr("0.125"), end_pointer)
call require(abs(float_value - 0.125) < 1e-12, "zero-valued digit conversion")

number = mem.cstr("0x1.8p+1!")
float_value = libc.c_strtod(number, end_pointer)
call require(abs(float_value - 3.0) < 1e-9, "hexadecimal floating conversion")
call require(mem.load(end_pointer, 8) == number + 8, "hex float end pointer")

float_value = libc.c_strtof(mem.cstr("1.1"), end_pointer)
call require(abs(float_value - 1.100000023841858) < 1e-12, "single precision floating conversion")

float_value = libc.c_strtod(mem.cstr("-INFINITY!"), end_pointer)
call require(float_value < -1e300 and mem.load(end_pointer, 8) == mem.cstr("-INFINITY!") + 9, "infinity conversion")
float_value = libc.c_strtod(mem.cstr("NaN(payload)"), end_pointer)
call require(String(float_value).lower() == "nan" and mem.load(end_pointer, 8) == mem.cstr("NaN(payload)") + 12, "NaN conversion")

print "QBE libc passed"
