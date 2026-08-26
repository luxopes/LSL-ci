load os

quote = chr(34)
slash = chr(92)
server = arg(1) + "/os-command-server"
command = server + " " + quote + "hello world" + quote + " plain" + slash + " value " + quote + quote
print os.capture(command).strip()
print os.capture(server + " pipe|literal >file").strip()
print os.capture([server, "list value", "tail"]).strip()
print os.which("ls") != None
failed = os.capture_result(server + " fail")
print failed["status"], failed["ok"], "OSServerError" in failed["stderr"]
print os.run(server + " direct")
print os.check(server + " checked").strip()
try:
    call os.check(server + " fail")
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
