# WebAssembly (WASI): izolace procesu potřebuje procesy, které WASI nemá.

function system_tool(primary, fallback, label):
    Error(SandboxError: "process sandbox is not available in WebAssembly (WASI)")
end

function available():
    return False
end

function is_active():
    return False
end

function profile():
    return None
end

function input_path(index):
    Error(SandboxError: "process sandbox is not available in WebAssembly (WASI)")
end

function output_path(index):
    Error(SandboxError: "process sandbox is not available in WebAssembly (WASI)")
end

function canonical_path(path, label):
    Error(SandboxError: "process sandbox is not available in WebAssembly (WASI)")
end

function checked_capabilities(policy, name):
    Error(SandboxError: "process sandbox is not available in WebAssembly (WASI)")
end

function checked_arguments(arguments):
    Error(SandboxError: "process sandbox is not available in WebAssembly (WASI)")
end

function checked_policy(value):
    Error(SandboxError: "process sandbox is not available in WebAssembly (WASI)")
end

function command(executable, arguments, policy):
    Error(SandboxError: "process sandbox is not available in WebAssembly (WASI)")
end

function run(executable, arguments, policy):
    Error(SandboxError: "process sandbox is not available in WebAssembly (WASI)")
end
