# lsl: internal-abi
load linker
load target

work = arg(1)
path = work + "/budget_utf8_probe.lsl"
owner = work + "/owner.lsl"
source = "# ž🙂" + chr(10) + "value = 1" + chr(10)
call writefile(path, source)
source_bytes = __lsl_text_byte_length(source)
print source_bytes > len(source)
providers = target.modules_for_platform("_platform_linux_x86_64")

counter = IntArray()
call counter.append(16777216 - source_bytes)
metadata = [counter, providers]
call linker.collect_module("budget_utf8_probe", owner, {}, [], metadata, True, "", None)
print counter[0] == 16777216

counter = IntArray()
call counter.append(16777216 - source_bytes + 1)
metadata = [counter, providers]
rejected = False
try:
    call linker.collect_module("budget_utf8_probe", owner, {}, [], metadata, True, "", None)
else:
    rejected = String(last_error()).find("linked source exceeds the 16 MiB compiler limit: " + path) >= 0
end
print rejected, counter[0] == 16777216 - source_bytes + 1
call unlink(path)
