load sandbox

print sandbox.is_active(), sandbox.profile()
print exists("/etc/passwd")
print readfile(sandbox.input_path(0)).strip()
print arg(1)
call writefile(sandbox.output_path(0) + "/sandbox-result.txt", "sandbox-write" + chr(10))
print exists(sandbox.output_path(0) + "/sandbox-result.txt")
