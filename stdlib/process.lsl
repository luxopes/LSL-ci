# Structured process helpers built on the syscall runtime.

function capture_result(executable, arguments):
    output = capture(executable, arguments)
    status = capture_status()
    return {"stdout": output, "status": status, "ok": status == 0}
end

function check(executable, arguments):
    result = capture_result(executable, arguments)
    if not result["ok"]:
        Error(ProcessError: "process exited with status " + String(result["status"]))
    end
    return result["stdout"]
end
