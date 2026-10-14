# Windows: izolace procesu (jmenné prostory Linuxu, seccomp) zatím chybí.
# available() a is_active() vrací False, spuštění hlásí chybu.



function system_tool(primary, fallback, label):
    Error(SandboxError: "process sandbox is not available on Windows")
end

function available():
    return False
end

function is_active():
    return False
end

function profile():
    Error(SandboxError: "process sandbox is not available on Windows")
end

function input_path(index):
    Error(SandboxError: "process sandbox is not available on Windows")
end

function output_path(index):
    Error(SandboxError: "process sandbox is not available on Windows")
end

function canonical_path(path, label):
    Error(SandboxError: "process sandbox is not available on Windows")
end

function checked_capabilities(policy, name):
    Error(SandboxError: "process sandbox is not available on Windows")
end

function checked_arguments(arguments):
    Error(SandboxError: "process sandbox is not available on Windows")
end

function checked_policy(value):
    Error(SandboxError: "process sandbox is not available on Windows")
end

function command(executable, arguments, policy):
    Error(SandboxError: "process sandbox is not available on Windows")
end

function run(executable, arguments, policy):
    Error(SandboxError: "process sandbox is not available on Windows")
end
