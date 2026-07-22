load process

result = process.capture_input_result("/tmp/lsl-input-bare-server", [], "Lux" + chr(10))
print result["stdout"].replace(chr(10), "|")
print result["status"], result["ok"], result["stderr"] == ""
