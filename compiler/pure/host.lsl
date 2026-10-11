# Veřejné API; operace hostitele poskytuje modul vybraný cílem.

load _compiler_host_platform as implementation


function dirname(path):
    return implementation.dirname(path)
end

function resource_path(path):
    return implementation.resource_path(path)
end

function tool_path(repository_path, installed_name):
    return implementation.tool_path(repository_path, installed_name)
end

function required_system_tool(primary, fallback, label):
    return implementation.required_system_tool(primary, fallback, label)
end

function user_home():
    return implementation.user_home()
end

function scratch_program_path():
    return implementation.scratch_program_path()
end

function cleanup_program(path):
    return implementation.cleanup_program(path)
end

function module_path(name, owner_path, home, builtin):
    return implementation.module_path(name, owner_path, home, builtin)
end

function target_name():
    return implementation.target_name()
end

function home():
    return implementation.home()
end

function tool(name):
    return implementation.tool(name)
end

function null_device():
    return implementation.null_device()
end

function run_config(evaluator):
    return implementation.run_config(evaluator)
end

function interactive_tool():
    return implementation.interactive_tool()
end

function prompt_enter(command):
    return implementation.prompt_enter(command)
end

function prompt_leave(command, saved):
    return implementation.prompt_leave(command, saved)
end
