# Buffered stdin (regular files) and stdout (files, pipes, non-terminal
# devices) must be invisible to programs: same bytes, same order, unread
# input handed to children, everything flushed before stderr, fork and exit.
load process

server = arg(1) + "/stdio-buffer-server"
work = arg(1) + "/stdio-buffer"
call mkdir(work)
lines = ""
for index in rang(1, 6):
    lines += "line" + String(index) + chr(10)
end
call writefile(work + "/input.txt", lines)

function shell(command):
    return run("/bin/sh", ["-c", command])
end

# Regular-file stdin: buffered, with lseek hand-back before the child runs.
print "file", shell(server + " handoff < " + work + "/input.txt > " + work + "/file.out")
print readfile(work + "/file.out").replace(chr(10), "|")
# Pipe stdin: byte reads, identical result.
print "pipe", shell("cat " + work + "/input.txt | " + server + " handoff > " + work + "/pipe.out")
print readfile(work + "/pipe.out").replace(chr(10), "|")
# Both streams into one file: stderr diagnostics after earlier prints.
print "error", shell(server + " error > " + work + "/error.out 2>&1")
print readfile(work + "/error.out").replace(chr(10), "|")
print "exit", shell(server + " exit > " + work + "/exit.out")
print readfile(work + "/exit.out").replace(chr(10), "|")
print "stderr", shell(server + " stderr > " + work + "/stderr.out 2>&1")
print readfile(work + "/stderr.out").replace(chr(10), "|")
print "prompt", shell("printf 'Lux\\n' | " + server + " prompt > " + work + "/prompt.out")
print readfile(work + "/prompt.out").replace(chr(10), "|")
# More than one buffer of output through a pipe and into a file.
big = capture(server, ["big"])
big_lines = big.split(chr(10))
print "big", len(big), len(big_lines), big_lines[0], big_lines[29999], big_lines[30000] == ""
print "big-file", shell(server + " big > " + work + "/big.out")
print readfile(work + "/big.out") == big
# /dev/null is a character device but not a terminal.
print "null", shell(server + " big > /dev/null")

# split and Int(String) now use native byte helpers; keep their edges.
print "a b c".split(" "), "a  b".split(" "), "".split(" "), "abc".split(" ")
print "a".split(""), " a ".split(" "), "ab--cd--".split("--"), "--".split("--")
print "a-b--c".split("--"), "žluť ouš".split(" "), "žluťoučký".split("ť"), "aaa".split("aa")
print Int("42"), Int("-7"), Int("+3"), Int("0"), Int("007"), Int("-0")
print Int("9223372036854775807"), Int("9223372036854775808"), Int("99999999999999999999")
for bad in ["4x", "", "ž", "-", "+", " 1", "1 ", "--1", "1.0"]:
    try:
        value = Int(bad)
        print "unexpected", bad, value
    else:
        print "err", bad, last_error()
    end
end
# Many fresh allocations cross the allocator's 1 MiB reserve boundary.
keep = []
for index in rang(60000):
    call keep.append([index, String(index)])
end
total = 0
for item in keep:
    total += item[0] + len(item[1])
end
print "alloc", len(keep), total

# Přímé operace nad stdin musí navazovat na logickou pozici input().
print "mixed", shell(server + " mixed < " + work + "/input.txt > " + work + "/mixed.out")
print readfile(work + "/mixed.out").replace(chr(10), "|")
call writefile(work + "/redirect.txt", "other" + chr(10))
print "redirect", shell(server + " redirect " + work + "/redirect.txt < " + work + "/input.txt > " + work + "/redirect.out")
print readfile(work + "/redirect.out").replace(chr(10), "|")
print "reopen", shell(server + " reopen " + work + "/redirect.txt < " + work + "/input.txt > " + work + "/reopen.out")
print readfile(work + "/reopen.out").replace(chr(10), "|")
