load process

result = process.capture_result(arg(1) + "/capture-result-server", [])
print result["stdout"].strip(), result["stderr"].strip(), result["status"], result["ok"]
caught = ""
try:
    call process.check(arg(1) + "/capture-result-server", [])
else:
    caught = last_error()
end
print caught
