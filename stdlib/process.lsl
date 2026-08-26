# Structured process helpers built on the syscall runtime.

function capture_result(executable, arguments):
    output = capture(executable, arguments)
    status = capture_status()
    return {"stdout": output, "stderr": capture_stderr(), "status": status, "ok": status == 0}
end

function capture_input_result(executable, arguments, input_text):
    output = capture_input(executable, arguments, input_text)
    status = capture_status()
    return {"stdout": output, "stderr": capture_stderr(), "status": status, "ok": status == 0}
end

function capture_input_stream_result(executable, arguments, input_text, on_chunk):
    output = capture_input_stream(executable, arguments, input_text, on_chunk)
    status = capture_status()
    return {"stdout": output, "stderr": capture_stderr(), "status": status, "ok": status == 0}
end

function check(executable, arguments):
    result = capture_result(executable, arguments)
    if not result["ok"]:
        Error(ProcessError: "process exited with status " + String(result["status"]))
    end
    return result["stdout"]
end

function check_input(executable, arguments, input_text):
    result = capture_input_result(executable, arguments, input_text)
    if not result["ok"]:
        Error(ProcessError: "process exited with status " + String(result["status"]))
    end
    return result["stdout"]
end

function check_input_stream(executable, arguments, input_text, on_chunk):
    result = capture_input_stream_result(executable, arguments, input_text, on_chunk)
    if not result["ok"]:
        Error(ProcessError: "process exited with status " + String(result["status"]))
    end
    return result["stdout"]
end
