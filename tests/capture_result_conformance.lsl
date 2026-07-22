load process

result = process.capture_result("/tmp/lsl-capture-result-server", [])
print result["stdout"].strip(), result["stderr"].strip(), result["status"], result["ok"]
caught = ""
try:
    call process.check("/tmp/lsl-capture-result-server", [])
else:
    caught = last_error()
end
print caught
