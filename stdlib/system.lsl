# Imperative LuxOS/Debian package helpers. Commands use argv, never a shell.

load os

function validate_package(package):
    if type(package) != "String":
        Error(TypeError: "package name must be a String")
    elif package.strip() == "":
        Error(ValueError: "package name cannot be empty")
    elif len(package) > 255:
        Error(ValueError: "package name is longer than 255 characters")
    elif package.startswith("-"):
        Error(ValueError: "package name cannot start with '-'")
    elif chr(0) in package:
        Error(ValueError: "package name cannot contain NUL")
    end
    for character in package:
        code = ord(character)
        if not ((code >= 48 and code <= 57) or (code >= 65 and code <= 90) or (code >= 97 and code <= 122) or character in "+-._:@"):
            Error(ValueError: "package name contains an invalid character")
        end
    end
end

function validate_tool(tool, name):
    if tool != None and type(tool) != "String":
        Error(TypeError: name + " command must be a String or None")
    elif tool != None and tool == "":
        Error(ValueError: name + " command cannot be empty")
    elif tool != None and __lsl_text_byte_length(String(tool)) > 4095:
        Error(ValueError: name + " command is too long")
    elif tool != None and chr(0) in tool:
        Error(ValueError: name + " command cannot contain NUL")
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
        lux_status = os.run_argv_clean(lux_command, [action, package])
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
    apt_status = os.run_argv_clean(apt_command, apt_arguments(action, package))
    if apt_status != 0:
        Error(PackageError: "apt " + action + " failed for " + package + " with status " + String(apt_status))
    end
    return "apt"
end

function detected_lux():
    return os.which_trusted("lux")
end

function detected_apt():
    command = os.which_trusted("apt")
    if command == None:
        command = os.which_trusted("apt-get")
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

function required_tool(name):
    command = os.which_trusted(name)
    if command == None:
        Error(SystemError: "required command is not available: " + name)
    end
    return command
end

function run_checked(program, arguments, operation):
    call validate_tool(program, operation)
    if program == None:
        Error(SystemError: "required command is not available: " + operation)
    end
    status = os.run_argv_clean(program, arguments)
    if status != 0:
        Error(SystemError: operation + " failed with status " + String(status))
    end
end

function capture_checked(program, arguments, operation):
    call validate_tool(program, operation)
    if program == None:
        Error(SystemError: "required command is not available: " + operation)
    end
    output = os.capture_argv_clean(program, arguments)
    status = capture_status()
    if status != 0:
        Error(SystemError: operation + " failed with status " + String(status) + ": " + String(capture_stderr()))
    end
    return output
end

function validate_name(value, label):
    if type(value) != "String" or value == "":
        Error(ValueError: label + " must be a non-empty String")
    elif value.startswith("-"):
        Error(ValueError: label + " cannot start with '-'")
    elif len(value) > 1024:
        Error(ValueError: label + " is too long")
    elif chr(0) in value:
        Error(ValueError: label + " cannot contain NUL")
    end
    for character in value:
        code = ord(character)
        if code <= 32 or code == 127:
            Error(ValueError: label + " cannot contain whitespace or control characters")
        end
    end
end

function validate_account_name(value, label):
    call validate_name(value, label)
    if len(value) > 32:
        Error(ValueError: label + " is longer than 32 characters")
    end
    index = 0
    while index < len(value):
        code = ord(value[index])
        valid = (code >= 97 and code <= 122) or value[index] == "_"
        if index > 0 and code >= 48 and code <= 57:
            valid = True
        elif index > 0 and value[index] == "-":
            valid = True
        end
        if not valid:
            Error(ValueError: label + " contains an invalid character")
        end
        index += 1
    end
end

function validate_account_list(values, label):
    if type(values) != "List":
        Error(TypeError: label + " must be a List")
    end
    for value in values:
        call validate_account_name(value, label + " item")
    end
end

function validate_string_list(values, label):
    if type(values) != "List":
        Error(TypeError: label + " must be a List")
    end
    for value in values:
        call validate_name(value, label + " item")
    end
end

function validate_mode(mode):
    if type(mode) != "String" or len(mode) < 3 or len(mode) > 4:
        Error(ValueError: "file mode must contain three or four octal digits")
    end
    for character in mode:
        if character not in "01234567":
            Error(ValueError: "file mode must contain three or four octal digits")
        end
    end
end

function validate_absolute_path(path, label, allow_root):
    if type(path) != "String" or len(path) == 0 or __lsl_text_byte_length(String(path)) > 4095 or not path.startswith("/"):
        Error(ValueError: label + " must be an absolute path")
    elif not allow_root and path == "/":
        Error(ValueError: label + " cannot be /")
    elif chr(0) in path:
        Error(ValueError: label + " cannot contain NUL")
    end
    for character in path:
        code = ord(character)
        if code < 32 or code == 127:
            Error(ValueError: label + " cannot contain control characters")
        end
    end
    for part in path.split("/"):
        if part == "..":
            Error(ValueError: label + " cannot contain ..")
        end
    end
end

function path_directory(path):
    index = len(path) - 1
    while index > 0 and path[index] != "/":
        index -= 1
    end
    if index == 0:
        return "/"
    end
    return path[0:index]
end

function path_name(path):
    index = len(path) - 1
    while index >= 0 and path[index] != "/":
        index -= 1
    end
    return path[index + 1:len(path)]
end

function refresh_with(apt_command):
    call run_checked(apt_command, ["update"], "apt repository refresh")
    return "apt"
end

function refresh():
    return refresh_with(detected_apt())
end

function service_action_with(action, name, systemctl_command):
    if action != "enable" and action != "disable" and action != "restart":
        Error(ValueError: "unsupported service action: " + action)
    end
    call validate_name(name, "service name")
    if action == "enable":
        arguments = ["enable", "--now", name]
    elif action == "disable":
        arguments = ["disable", "--now", name]
    else:
        arguments = ["restart", name]
    end
    call run_checked(systemctl_command, arguments, "systemctl " + action + " " + name)
end

function enable_service_with(name, systemctl_command):
    call service_action_with("enable", name, systemctl_command)
end

function disable_service_with(name, systemctl_command):
    call service_action_with("disable", name, systemctl_command)
end

function restart_service_with(name, systemctl_command):
    call service_action_with("restart", name, systemctl_command)
end

function service_active_with(name, systemctl_command):
    call validate_name(name, "service name")
    call validate_tool(systemctl_command, "systemctl")
    if systemctl_command == None:
        Error(SystemError: "required command is not available: systemctl")
    end
    status = os.run_argv_clean(systemctl_command, ["is-active", "--quiet", name])
    if status == 0:
        return True
    elif status == 3:
        return False
    end
    Error(SystemError: "systemctl is-active failed with status " + String(status))
end

function enable_service(name):
    call enable_service_with(name, required_tool("systemctl"))
end

function disable_service(name):
    call disable_service_with(name, required_tool("systemctl"))
end

function restart_service(name):
    call restart_service_with(name, required_tool("systemctl"))
end

function service_active(name):
    return service_active_with(name, required_tool("systemctl"))
end

function set_hostname_with(name, hostnamectl_command):
    call validate_name(name, "hostname")
    call run_checked(hostnamectl_command, ["set-hostname", name], "set hostname")
end

function set_timezone_with(zone, timedatectl_command):
    call validate_name(zone, "timezone")
    call run_checked(timedatectl_command, ["set-timezone", zone], "set timezone")
end

function set_locale_with(locale, localectl_command):
    call validate_name(locale, "locale")
    call run_checked(localectl_command, ["set-locale", "LANG=" + locale], "set locale")
end

function set_hostname(name):
    call set_hostname_with(name, required_tool("hostnamectl"))
end

function set_timezone(zone):
    call set_timezone_with(zone, required_tool("timedatectl"))
end

function set_locale(locale):
    call set_locale_with(locale, required_tool("localectl"))
end

function group_exists_with(name, getent_command):
    call validate_account_name(name, "group name")
    call validate_tool(getent_command, "getent")
    if getent_command == None:
        Error(SystemError: "required command is not available: getent")
    end
    call os.capture_argv_clean(getent_command, ["group", name])
    status = capture_status()
    if status == 0:
        return True
    elif status == 2:
        return False
    end
    Error(SystemError: "group lookup failed with status " + String(status))
end

function ensure_group_with(name, getent_command, groupadd_command):
    if group_exists_with(name, getent_command):
        return False
    end
    call run_checked(groupadd_command, ["--", name], "create group " + name)
    return True
end

function remove_group_with(name, groupdel_command):
    call validate_account_name(name, "group name")
    call run_checked(groupdel_command, ["--", name], "remove group " + name)
end

function ensure_group(name):
    return ensure_group_with(name, required_tool("getent"), required_tool("groupadd"))
end

function remove_group(name):
    call remove_group_with(name, required_tool("groupdel"))
end

function user_exists_with(name, id_command):
    call validate_account_name(name, "user name")
    call validate_tool(id_command, "id")
    if id_command == None:
        Error(SystemError: "required command is not available: id")
    end
    call os.capture_argv_clean(id_command, ["-u", name])
    status = capture_status()
    if status == 0:
        return True
    elif status == 1:
        return False
    end
    Error(SystemError: "user lookup failed with status " + String(status))
end

function ensure_user_with(name, shell, groups, id_command, useradd_command, usermod_command):
    call validate_account_name(name, "user name")
    call validate_absolute_path(shell, "user shell", False)
    call validate_account_list(groups, "user groups")
    group_text = ",".join(groups)
    if user_exists_with(name, id_command):
        arguments = ["--shell", shell]
        if len(groups) > 0:
            arguments.extend(["--append", "--groups", group_text])
        end
        arguments.append(name)
        call run_checked(usermod_command, arguments, "update user " + name)
        return False
    end
    arguments = ["--create-home", "--shell", shell]
    if len(groups) > 0:
        arguments.extend(["--groups", group_text])
    end
    arguments.append(name)
    call run_checked(useradd_command, arguments, "create user " + name)
    return True
end

function remove_user_with(name, userdel_command):
    call validate_account_name(name, "user name")
    call run_checked(userdel_command, ["--remove", "--", name], "remove user " + name)
end

function ensure_user(name, shell, groups):
    return ensure_user_with(name, shell, groups, required_tool("id"), required_tool("useradd"), required_tool("usermod"))
end

function remove_user(name):
    call remove_user_with(name, required_tool("userdel"))
end

function validate_file_tools(tools):
    if type(tools) != "Dictionary":
        Error(TypeError: "file tools must be a Dictionary")
    end
    for name in ["mkdir", "mktemp", "chmod", "chown", "mv"]:
        if name not in tools:
            Error(ValueError: "file tools are missing " + name)
        end
        call validate_tool(tools[name], name)
        if tools[name] == None:
            Error(ValueError: "file tool cannot be None: " + name)
        end
    end
end

function detected_file_tools():
    return {
        "mkdir": required_tool("mkdir"),
        "mktemp": required_tool("mktemp"),
        "chmod": required_tool("chmod"),
        "chown": required_tool("chown"),
        "mv": required_tool("mv")
    }
end

function write_file_with(path, content, mode, owner, group, tools):
    call validate_absolute_path(path, "file path", False)
    if type(content) != "String":
        Error(TypeError: "file content must be a String")
    end
    if path.endswith("/"):
        Error(ValueError: "file path cannot end with /")
    end
    call validate_mode(mode)
    if owner != None:
        call validate_account_name(owner, "file owner")
        call validate_account_name(group, "file group")
    elif group != None:
        Error(ValueError: "file group requires an owner")
    end
    call validate_file_tools(tools)
    directory = path_directory(path)
    call run_checked(tools["mkdir"], ["-p", "--", directory], "create parent directory " + directory)
    template = directory + "/." + path_name(path) + ".lux.XXXXXX"
    temporary_directory = capture_checked(tools["mktemp"], ["-d", template], "create private temporary directory").strip()
    call validate_absolute_path(temporary_directory, "temporary directory", False)
    expected_prefix = directory + "/." + path_name(path) + ".lux."
    suffix = ""
    if temporary_directory.startswith(expected_prefix):
        suffix = temporary_directory[len(expected_prefix):len(temporary_directory)]
    end
    if suffix == "" or "/" in suffix or not exists(temporary_directory):
        Error(SystemError: "mktemp returned a path outside the requested directory")
    end
    # The file is created inside a mode-0700 directory. Reopening a pathname
    # returned by plain mktemp left a window in which another user could swap
    # the inode between creation and writefile().
    temporary = temporary_directory + "/content"
    if exists(temporary):
        call rmdir(temporary_directory)
        Error(SystemError: "private temporary directory is not empty")
    end
    call writefile(temporary, content)
    status = os.run_argv_clean(tools["chmod"], [mode, "--", temporary])
    if status != 0:
        call unlink(temporary)
        call rmdir(temporary_directory)
        Error(SystemError: "chmod temporary file failed with status " + String(status))
    end
    if owner != None:
        status = os.run_argv_clean(tools["chown"], [owner + ":" + group, "--", temporary])
        if status != 0:
            call unlink(temporary)
            call rmdir(temporary_directory)
            Error(SystemError: "chown temporary file failed with status " + String(status))
        end
    end
    status = os.run_argv_clean(tools["mv"], ["-f", "--", temporary, path])
    if status != 0:
        call unlink(temporary)
        call rmdir(temporary_directory)
        Error(SystemError: "atomic file rename failed with status " + String(status))
    end
    if rmdir(temporary_directory) != 0:
        Error(SystemError: "cannot remove private temporary directory")
    end
end

function write_file(path, content, mode):
    call write_file_with(path, content, mode, None, None, detected_file_tools())
end

function write_owned_file(path, content, mode, owner, group):
    call write_file_with(path, content, mode, owner, group, detected_file_tools())
end

function ensure_directory_with(path, mode, mkdir_command, chmod_command):
    call validate_absolute_path(path, "directory path", False)
    call validate_mode(mode)
    call run_checked(mkdir_command, ["-p", "--", path], "create directory " + path)
    call run_checked(chmod_command, [mode, "--", path], "chmod directory " + path)
end

function ensure_directory(path, mode):
    call ensure_directory_with(path, mode, required_tool("mkdir"), required_tool("chmod"))
end

function remove_file(path):
    call validate_absolute_path(path, "file path", False)
    if path.endswith("/"):
        Error(ValueError: "file path cannot end with /")
    end
    if exists(path):
        call unlink(path)
    end
end

function validate_mount_options(options):
    call validate_string_list(options, "mount options")
end

function ensure_mount_with(device, target, filesystem, options, mountpoint_command, mkdir_command, mount_command):
    call validate_name(device, "mount device")
    call validate_absolute_path(target, "mount target", False)
    call validate_name(filesystem, "mount filesystem")
    call validate_mount_options(options)
    call validate_tool(mountpoint_command, "mountpoint")
    if mountpoint_command == None:
        Error(SystemError: "required command is not available: mountpoint")
    end
    status = os.run_argv_clean(mountpoint_command, ["-q", "--", target])
    if status == 0:
        return False
    elif status != 1:
        Error(SystemError: "mountpoint check failed with status " + String(status))
    end
    call run_checked(mkdir_command, ["-p", "--", target], "create mount target " + target)
    arguments = ["-t", filesystem]
    if len(options) > 0:
        arguments.extend(["-o", ",".join(options)])
    end
    arguments.extend(["--", device, target])
    call run_checked(mount_command, arguments, "mount " + target)
    return True
end

function unmount_with(target, umount_command):
    call validate_absolute_path(target, "mount target", False)
    call run_checked(umount_command, ["--", target], "unmount " + target)
end

function ensure_mount(device, target, filesystem, options):
    return ensure_mount_with(device, target, filesystem, options, required_tool("mountpoint"), required_tool("mkdir"), required_tool("mount"))
end

function unmount(target):
    call unmount_with(target, required_tool("umount"))
end

function lux_command():
    command = detected_lux()
    if command == None:
        Error(SystemError: "LuxOS command is not available: lux")
    end
    return command
end

function check_system_with(config_path, lux_command_path):
    call validate_absolute_path(config_path, "system config", False)
    call run_checked(lux_command_path, ["check", "-c", config_path], "lux check")
end

function apply_system_with(config_path, dry_run, lux_command_path):
    call validate_absolute_path(config_path, "system config", False)
    if type(dry_run) != "Bool":
        Error(TypeError: "dry_run must be Bool")
    end
    arguments = ["apply", "-c", config_path]
    if dry_run:
        arguments.append("--dry-run")
    end
    call run_checked(lux_command_path, arguments, "lux apply")
end

function lux_status_with(lux_command_path):
    return capture_checked(lux_command_path, ["status"], "lux status")
end

function generations_with(lux_command_path):
    return capture_checked(lux_command_path, ["generations"], "lux generations")
end

function rollback_with(generation, dry_run, lux_command_path):
    call validate_name(generation, "generation")
    if type(dry_run) != "Bool":
        Error(TypeError: "dry_run must be Bool")
    end
    arguments = ["rollback", generation]
    if dry_run:
        arguments.append("--dry-run")
    end
    call run_checked(lux_command_path, arguments, "lux rollback " + generation)
end

function check_system(config_path):
    call check_system_with(config_path, lux_command())
end

function apply_system(config_path):
    call apply_system_with(config_path, False, lux_command())
end

function dry_run_system(config_path):
    call apply_system_with(config_path, True, lux_command())
end

function lux_status():
    return lux_status_with(lux_command())
end

function generations():
    return generations_with(lux_command())
end

function rollback(generation):
    call rollback_with(generation, False, lux_command())
end

function rollback_dry(generation):
    call rollback_with(generation, True, lux_command())
end
