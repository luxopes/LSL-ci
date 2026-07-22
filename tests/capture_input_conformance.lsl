load process

body = "x"
for unused in rang(17):
    body += body
end
body = body[0:100000]
input_text = body + chr(10) + "second" + chr(10)
result = process.capture_input_result("/tmp/lsl-input-server", [], input_text)
print result["stdout"].strip()
print result["status"], result["ok"], result["stderr"] == ""

missing = process.capture_input_result("/tmp/lsl-capture-input-missing", [], "ignored")
print missing["status"], missing["ok"], missing["stdout"] == "", missing["stderr"] == ""
