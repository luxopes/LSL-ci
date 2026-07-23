# Imperative LuxOS/Debian package helpers. Commands use argv, never a shell.

load os

function validate_package(package):
    if type(package) != "String":
        Error(TypeError: "package name must be a String")
    elif package.strip() == "":
        Error(ValueError: "package name cannot be empty")
    elif package.startswith("-"):
        Error(ValueError: "package name cannot start with '-'")
    end
    for character in package:
        if character in " \t\r\n":
            Error(ValueError: "package name cannot contain whitespace")
        end
    end
end

function validate_tool(tool, name):
    if tool != None and type(tool) != "String":
        Error(TypeError: name + " command must be a String or None")
    elif tool != None and tool == "":
        Error(ValueError: name + " command cannot be empty")
    end
end

function apt_arguments(action, package):
    if action == "install":
        return ["install", "-y", "--", package]
    elif action == "update":
        return ["install", "-y", "--only-upgrade", "--", package]
    end
    return ["remove", "-y", "--", package]
end

function package_action_with(action, package, lux_command, apt_command):
    if action != "install" and action != "update" and action != "remove":
        Error(ValueError: "unsupported package action: " + action)
    end
    call validate_package(package)
    call validate_tool(lux_command, "lux")
    call validate_tool(apt_command, "apt")
    lux_status = -1
    if lux_command != None:
        lux_status = os.run_argv(lux_command, [action, package])
        if lux_status == 0:
            return "lux"
        end
    end
    if apt_command == None:
        if lux_command != None:
            Error(PackageError: "lux " + action + " failed for " + package + " with status " + String(lux_status) + " and apt is unavailable")
        end
        Error(PackageError: "no Lux or apt package manager found")
    end
    apt_status = os.run_argv(apt_command, apt_arguments(action, package))
    if apt_status != 0:
        Error(PackageError: "apt " + action + " failed for " + package + " with status " + String(apt_status))
    end
    return "apt"
end

function detected_lux():
    return os.which("lux")
end

function detected_apt():
    command = os.which("apt")
    if command == None:
        command = os.which("apt-get")
    end
    return command
end

function install_with(package, lux_command, apt_command):
    return package_action_with("install", package, lux_command, apt_command)
end

function update_with(package, lux_command, apt_command):
    return package_action_with("update", package, lux_command, apt_command)
end

function remove_with(package, lux_command, apt_command):
    return package_action_with("remove", package, lux_command, apt_command)
end

function install(package):
    return install_with(package, detected_lux(), detected_apt())
end

function update(package):
    return update_with(package, detected_lux(), detected_apt())
end

function remove(package):
    return remove_with(package, detected_lux(), detected_apt())
end
