# Windows: správa balíčků, služeb, uživatelů a připojení (apt, systemctl,
# useradd, mount) je pro Debian a LuxOS. Na Windows hlásí chybu.



function validate_package(package):
    Error(OSError: "system: package, service and account management is not available on Windows")
end

function validate_tool(tool, name):
    Error(OSError: "system: package, service and account management is not available on Windows")
end

function apt_arguments(action, package):
    Error(OSError: "system: package, service and account management is not available on Windows")
end

function package_action_with(action, package, lux_command, apt_command):
    Error(OSError: "system: package, service and account management is not available on Windows")
end

function detected_lux():
    Error(OSError: "system: package, service and account management is not available on Windows")
end

function detected_apt():
    Error(OSError: "system: package, service and account management is not available on Windows")
end

function install_with(package, lux_command, apt_command):
    Error(OSError: "system: package, service and account management is not available on Windows")
end

function update_with(package, lux_command, apt_command):
    Error(OSError: "system: package, service and account management is not available on Windows")
end

function remove_with(package, lux_command, apt_command):
    Error(OSError: "system: package, service and account management is not available on Windows")
end

function install(package):
    Error(OSError: "system: package, service and account management is not available on Windows")
end

function update(package):
    Error(OSError: "system: package, service and account management is not available on Windows")
end

function remove(package):
    Error(OSError: "system: package, service and account management is not available on Windows")
end

function required_tool(name):
    Error(OSError: "system: package, service and account management is not available on Windows")
end

function run_checked(program, arguments, operation):
    Error(OSError: "system: package, service and account management is not available on Windows")
end

function capture_checked(program, arguments, operation):
    Error(OSError: "system: package, service and account management is not available on Windows")
end

function validate_name(value, label):
    Error(OSError: "system: package, service and account management is not available on Windows")
end

function validate_account_name(value, label):
    Error(OSError: "system: package, service and account management is not available on Windows")
end

function validate_account_list(values, label):
    Error(OSError: "system: package, service and account management is not available on Windows")
end

function validate_string_list(values, label):
    Error(OSError: "system: package, service and account management is not available on Windows")
end

function validate_mode(mode):
    Error(OSError: "system: package, service and account management is not available on Windows")
end

function validate_absolute_path(path, label, allow_root):
    Error(OSError: "system: package, service and account management is not available on Windows")
end

function path_directory(path):
    Error(OSError: "system: package, service and account management is not available on Windows")
end

function path_name(path):
    Error(OSError: "system: package, service and account management is not available on Windows")
end

function refresh_with(apt_command):
    Error(OSError: "system: package, service and account management is not available on Windows")
end

function refresh():
    Error(OSError: "system: package, service and account management is not available on Windows")
end

function service_action_with(action, name, systemctl_command):
    Error(OSError: "system: package, service and account management is not available on Windows")
end

function enable_service_with(name, systemctl_command):
    Error(OSError: "system: package, service and account management is not available on Windows")
end

function disable_service_with(name, systemctl_command):
    Error(OSError: "system: package, service and account management is not available on Windows")
end

function restart_service_with(name, systemctl_command):
    Error(OSError: "system: package, service and account management is not available on Windows")
end

function service_active_with(name, systemctl_command):
    Error(OSError: "system: package, service and account management is not available on Windows")
end

function enable_service(name):
    Error(OSError: "system: package, service and account management is not available on Windows")
end

function disable_service(name):
    Error(OSError: "system: package, service and account management is not available on Windows")
end

function restart_service(name):
    Error(OSError: "system: package, service and account management is not available on Windows")
end

function service_active(name):
    Error(OSError: "system: package, service and account management is not available on Windows")
end

function set_hostname_with(name, hostnamectl_command):
    Error(OSError: "system: package, service and account management is not available on Windows")
end

function set_timezone_with(zone, timedatectl_command):
    Error(OSError: "system: package, service and account management is not available on Windows")
end

function set_locale_with(locale, localectl_command):
    Error(OSError: "system: package, service and account management is not available on Windows")
end

function set_hostname(name):
    Error(OSError: "system: package, service and account management is not available on Windows")
end

function set_timezone(zone):
    Error(OSError: "system: package, service and account management is not available on Windows")
end

function set_locale(locale):
    Error(OSError: "system: package, service and account management is not available on Windows")
end

function group_exists_with(name, getent_command):
    Error(OSError: "system: package, service and account management is not available on Windows")
end

function ensure_group_with(name, getent_command, groupadd_command):
    Error(OSError: "system: package, service and account management is not available on Windows")
end

function remove_group_with(name, groupdel_command):
    Error(OSError: "system: package, service and account management is not available on Windows")
end

function ensure_group(name):
    Error(OSError: "system: package, service and account management is not available on Windows")
end

function remove_group(name):
    Error(OSError: "system: package, service and account management is not available on Windows")
end

function user_exists_with(name, id_command):
    Error(OSError: "system: package, service and account management is not available on Windows")
end

function ensure_user_with(name, shell, groups, id_command, useradd_command, usermod_command):
    Error(OSError: "system: package, service and account management is not available on Windows")
end

function remove_user_with(name, userdel_command):
    Error(OSError: "system: package, service and account management is not available on Windows")
end

function ensure_user(name, shell, groups):
    Error(OSError: "system: package, service and account management is not available on Windows")
end

function remove_user(name):
    Error(OSError: "system: package, service and account management is not available on Windows")
end

function validate_file_tools(tools):
    Error(OSError: "system: package, service and account management is not available on Windows")
end

function detected_file_tools():
    Error(OSError: "system: package, service and account management is not available on Windows")
end

function write_file_with(path, content, mode, owner, group, tools):
    Error(OSError: "system: package, service and account management is not available on Windows")
end

function write_file(path, content, mode):
    Error(OSError: "system: package, service and account management is not available on Windows")
end

function write_owned_file(path, content, mode, owner, group):
    Error(OSError: "system: package, service and account management is not available on Windows")
end

function ensure_directory_with(path, mode, mkdir_command, chmod_command):
    Error(OSError: "system: package, service and account management is not available on Windows")
end

function ensure_directory(path, mode):
    Error(OSError: "system: package, service and account management is not available on Windows")
end

function remove_file(path):
    Error(OSError: "system: package, service and account management is not available on Windows")
end

function validate_mount_options(options):
    Error(OSError: "system: package, service and account management is not available on Windows")
end

function ensure_mount_with(device, target, filesystem, options, mountpoint_command, mkdir_command, mount_command):
    Error(OSError: "system: package, service and account management is not available on Windows")
end

function unmount_with(target, umount_command):
    Error(OSError: "system: package, service and account management is not available on Windows")
end

function ensure_mount(device, target, filesystem, options):
    Error(OSError: "system: package, service and account management is not available on Windows")
end

function unmount(target):
    Error(OSError: "system: package, service and account management is not available on Windows")
end

function lux_command():
    Error(OSError: "system: package, service and account management is not available on Windows")
end

function check_system_with(config_path, lux_command_path):
    Error(OSError: "system: package, service and account management is not available on Windows")
end

function apply_system_with(config_path, dry_run, lux_command_path):
    Error(OSError: "system: package, service and account management is not available on Windows")
end

function lux_status_with(lux_command_path):
    Error(OSError: "system: package, service and account management is not available on Windows")
end

function generations_with(lux_command_path):
    Error(OSError: "system: package, service and account management is not available on Windows")
end

function rollback_with(generation, dry_run, lux_command_path):
    Error(OSError: "system: package, service and account management is not available on Windows")
end

function check_system(config_path):
    Error(OSError: "system: package, service and account management is not available on Windows")
end

function apply_system(config_path):
    Error(OSError: "system: package, service and account management is not available on Windows")
end

function dry_run_system(config_path):
    Error(OSError: "system: package, service and account management is not available on Windows")
end

function lux_status():
    Error(OSError: "system: package, service and account management is not available on Windows")
end

function generations():
    Error(OSError: "system: package, service and account management is not available on Windows")
end

function rollback(generation):
    Error(OSError: "system: package, service and account management is not available on Windows")
end

function rollback_dry(generation):
    Error(OSError: "system: package, service and account management is not available on Windows")
end
