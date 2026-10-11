# Veřejné API; operace hostitele poskytuje modul vybraný cílem.

load _sandbox_linux_x86_64 as implementation


function system_tool(primary, fallback, label):
    return implementation.system_tool(primary, fallback, label)
end

function available():
    return implementation.available()
end

function is_active():
    return implementation.is_active()
end

function profile():
    return implementation.profile()
end

function input_path(index):
    return implementation.input_path(index)
end

function output_path(index):
    return implementation.output_path(index)
end

function canonical_path(path, label):
    return implementation.canonical_path(path, label)
end

function checked_capabilities(policy, name):
    return implementation.checked_capabilities(policy, name)
end

function checked_arguments(arguments):
    return implementation.checked_arguments(arguments)
end

function checked_policy(value):
    return implementation.checked_policy(value)
end

function command(executable, arguments, policy):
    return implementation.command(executable, arguments, policy)
end

function run(executable, arguments, policy):
    return implementation.run(executable, arguments, policy)
end
