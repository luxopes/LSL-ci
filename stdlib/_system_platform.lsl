# Veřejné API; operace hostitele poskytuje modul vybraný cílem.

load _system_linux_x86_64 as implementation


function validate_package(package):
    return implementation.validate_package(package)
end

function validate_tool(tool, name):
    return implementation.validate_tool(tool, name)
end

function apt_arguments(action, package):
    return implementation.apt_arguments(action, package)
end

function package_action_with(action, package, lux_command, apt_command):
    return implementation.package_action_with(action, package, lux_command, apt_command)
end

function detected_lux():
    return implementation.detected_lux()
end

function detected_apt():
    return implementation.detected_apt()
end

function install_with(package, lux_command, apt_command):
    return implementation.install_with(package, lux_command, apt_command)
end

function update_with(package, lux_command, apt_command):
    return implementation.update_with(package, lux_command, apt_command)
end

function remove_with(package, lux_command, apt_command):
    return implementation.remove_with(package, lux_command, apt_command)
end

function install(package):
    return implementation.install(package)
end

function update(package):
    return implementation.update(package)
end

function remove(package):
    return implementation.remove(package)
end

function required_tool(name):
    return implementation.required_tool(name)
end

function run_checked(program, arguments, operation):
    return implementation.run_checked(program, arguments, operation)
end

function capture_checked(program, arguments, operation):
    return implementation.capture_checked(program, arguments, operation)
end

function validate_name(value, label):
    return implementation.validate_name(value, label)
end

function validate_account_name(value, label):
    return implementation.validate_account_name(value, label)
end

function validate_account_list(values, label):
    return implementation.validate_account_list(values, label)
end

function validate_string_list(values, label):
    return implementation.validate_string_list(values, label)
end

function validate_mode(mode):
    return implementation.validate_mode(mode)
end

function validate_absolute_path(path, label, allow_root):
    return implementation.validate_absolute_path(path, label, allow_root)
end

function path_directory(path):
    return implementation.path_directory(path)
end

function path_name(path):
    return implementation.path_name(path)
end

function refresh_with(apt_command):
    return implementation.refresh_with(apt_command)
end

function refresh():
    return implementation.refresh()
end

function service_action_with(action, name, systemctl_command):
    return implementation.service_action_with(action, name, systemctl_command)
end

function enable_service_with(name, systemctl_command):
    return implementation.enable_service_with(name, systemctl_command)
end

function disable_service_with(name, systemctl_command):
    return implementation.disable_service_with(name, systemctl_command)
end

function restart_service_with(name, systemctl_command):
    return implementation.restart_service_with(name, systemctl_command)
end

function service_active_with(name, systemctl_command):
    return implementation.service_active_with(name, systemctl_command)
end

function enable_service(name):
    return implementation.enable_service(name)
end

function disable_service(name):
    return implementation.disable_service(name)
end

function restart_service(name):
    return implementation.restart_service(name)
end

function service_active(name):
    return implementation.service_active(name)
end

function set_hostname_with(name, hostnamectl_command):
    return implementation.set_hostname_with(name, hostnamectl_command)
end

function set_timezone_with(zone, timedatectl_command):
    return implementation.set_timezone_with(zone, timedatectl_command)
end

function set_locale_with(locale, localectl_command):
    return implementation.set_locale_with(locale, localectl_command)
end

function set_hostname(name):
    return implementation.set_hostname(name)
end

function set_timezone(zone):
    return implementation.set_timezone(zone)
end

function set_locale(locale):
    return implementation.set_locale(locale)
end

function group_exists_with(name, getent_command):
    return implementation.group_exists_with(name, getent_command)
end

function ensure_group_with(name, getent_command, groupadd_command):
    return implementation.ensure_group_with(name, getent_command, groupadd_command)
end

function remove_group_with(name, groupdel_command):
    return implementation.remove_group_with(name, groupdel_command)
end

function ensure_group(name):
    return implementation.ensure_group(name)
end

function remove_group(name):
    return implementation.remove_group(name)
end

function user_exists_with(name, id_command):
    return implementation.user_exists_with(name, id_command)
end

function ensure_user_with(name, shell, groups, id_command, useradd_command, usermod_command):
    return implementation.ensure_user_with(name, shell, groups, id_command, useradd_command, usermod_command)
end

function remove_user_with(name, userdel_command):
    return implementation.remove_user_with(name, userdel_command)
end

function ensure_user(name, shell, groups):
    return implementation.ensure_user(name, shell, groups)
end

function remove_user(name):
    return implementation.remove_user(name)
end

function validate_file_tools(tools):
    return implementation.validate_file_tools(tools)
end

function detected_file_tools():
    return implementation.detected_file_tools()
end

function write_file_with(path, content, mode, owner, group, tools):
    return implementation.write_file_with(path, content, mode, owner, group, tools)
end

function write_file(path, content, mode):
    return implementation.write_file(path, content, mode)
end

function write_owned_file(path, content, mode, owner, group):
    return implementation.write_owned_file(path, content, mode, owner, group)
end

function ensure_directory_with(path, mode, mkdir_command, chmod_command):
    return implementation.ensure_directory_with(path, mode, mkdir_command, chmod_command)
end

function ensure_directory(path, mode):
    return implementation.ensure_directory(path, mode)
end

function remove_file(path):
    return implementation.remove_file(path)
end

function validate_mount_options(options):
    return implementation.validate_mount_options(options)
end

function ensure_mount_with(device, target, filesystem, options, mountpoint_command, mkdir_command, mount_command):
    return implementation.ensure_mount_with(device, target, filesystem, options, mountpoint_command, mkdir_command, mount_command)
end

function unmount_with(target, umount_command):
    return implementation.unmount_with(target, umount_command)
end

function ensure_mount(device, target, filesystem, options):
    return implementation.ensure_mount(device, target, filesystem, options)
end

function unmount(target):
    return implementation.unmount(target)
end

function lux_command():
    return implementation.lux_command()
end

function check_system_with(config_path, lux_command_path):
    return implementation.check_system_with(config_path, lux_command_path)
end

function apply_system_with(config_path, dry_run, lux_command_path):
    return implementation.apply_system_with(config_path, dry_run, lux_command_path)
end

function lux_status_with(lux_command_path):
    return implementation.lux_status_with(lux_command_path)
end

function generations_with(lux_command_path):
    return implementation.generations_with(lux_command_path)
end

function rollback_with(generation, dry_run, lux_command_path):
    return implementation.rollback_with(generation, dry_run, lux_command_path)
end

function check_system(config_path):
    return implementation.check_system(config_path)
end

function apply_system(config_path):
    return implementation.apply_system(config_path)
end

function dry_run_system(config_path):
    return implementation.dry_run_system(config_path)
end

function lux_status():
    return implementation.lux_status()
end

function generations():
    return implementation.generations()
end

function rollback(generation):
    return implementation.rollback(generation)
end

function rollback_dry(generation):
    return implementation.rollback_dry(generation)
end
