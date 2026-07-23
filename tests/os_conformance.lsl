load os

quote = chr(34)
slash = chr(92)
command = "/tmp/lsl-os-command-server " + quote + "hello world" + quote + " plain" + slash + " value " + quote + quote
print os.capture(command).strip()
print os.capture("/tmp/lsl-os-command-server pipe|literal >file").strip()
print os.capture(["/tmp/lsl-os-command-server", "list value", "tail"]).strip()
print os.which("ls") != None
failed = os.capture_result("/tmp/lsl-os-command-server fail")
print failed["status"], failed["ok"], "OSServerError" in failed["stderr"]
print os.run("/tmp/lsl-os-command-server direct")
print os.check("/tmp/lsl-os-command-server checked").strip()
try:
    call os.check("/tmp/lsl-os-command-server fail")
else:
    print "check", "status 1" in last_error()
end
print os.which("lsl-command-that-does-not-exist-95851") == None
print os.run("lsl-command-that-does-not-exist-95851")
try:
    call os.capture("echo " + quote + "unterminated")
else:
    print last_error()
end
