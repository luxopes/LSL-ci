# Pluginy s časovým limitem na každém systému (Linux: coreutils timeout,
# Windows a macOS: limit v runtime). Program spouští sám sebe jako plugin.
load plugin
load time

if arg(1) == "sleep":
    call time.sleep(30)
    print "woke"
    exit(0)
end
if arg(1) == "echo":
    print "plugin " + input("")
    exit(0)
end
out = plugin.capture_with_timeout(executable_path(), ["echo"], "hello\n", 20)
print out.strip(), capture_status()
start = time.monotonic()
out = plugin.capture_with_timeout(executable_path(), ["sleep"], "", 1)
elapsed = time.monotonic() - start
print "timeout", capture_status(), out == "", elapsed < 15
