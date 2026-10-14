# Bare metal: správa systému potřebuje procesy, které bez OS nejsou.

load _system_linux_x86_64 as shared

function validate_package(package):
    return shared.validate_package(package)
end

function validate_tool(tool, name):
    return shared.validate_tool(tool, name)
end

function apt_arguments(action, package):
    return shared.apt_arguments(action, package)
end

function package_action_with(action, package, lux_command, apt_command):
    return shared.package_action_with(action, package, lux_command, apt_command)
end

function detected_lux():
    return shared.detected_lux()
end

function detected_apt():
    return shared.detected_apt()
end

function install_with(package, lux_command, apt_command):
    return shared.install_with(package, lux_command, apt_command)
end

function update_with(package, lux_command, apt_command):
    return shared.update_with(package, lux_command, apt_command)
end

function remove_with(package, lux_command, apt_command):
    return shared.remove_with(package, lux_command, apt_command)
end

function install(package):
    return shared.install(package)
end

function update(package):
    return shared.update(package)
end

function remove(package):
    return shared.remove(package)
end

function required_tool(name):
    return shared.required_tool(name)
end

function run_checked(program, arguments, operation):
    return shared.run_checked(program, arguments, operation)
end

function capture_checked(program, arguments, operation):
    return shared.capture_checked(program, arguments, operation)
end

function validate_name(value, label):
    return shared.validate_name(value, label)
end

function validate_account_name(value, label):
    return shared.validate_account_name(value, label)
end

function validate_account_list(values, label):
    return shared.validate_account_list(values, label)
end

function validate_string_list(values, label):
    return shared.validate_string_list(values, label)
end

function validate_mode(mode):
    return shared.validate_mode(mode)
end

function validate_absolute_path(path, label, allow_root):
    return shared.validate_absolute_path(path, label, allow_root)
end

function path_directory(path):
    return shared.path_directory(path)
end

function path_name(path):
    return shared.path_name(path)
end

function refresh_with(apt_command):
    return shared.refresh_with(apt_command)
end

function refresh():
    return shared.refresh()
end

function service_action_with(action, name, systemctl_command):
    return shared.service_action_with(action, name, systemctl_command)
end

function enable_service_with(name, systemctl_command):
    return shared.enable_service_with(name, systemctl_command)
end

function disable_service_with(name, systemctl_command):
    return shared.disable_service_with(name, systemctl_command)
end

function restart_service_with(name, systemctl_command):
    return shared.restart_service_with(name, systemctl_command)
end

function service_active_with(name, systemctl_command):
    return shared.service_active_with(name, systemctl_command)
end

function enable_service(name):
    return shared.enable_service(name)
end

function disable_service(name):
    return shared.disable_service(name)
end

function restart_service(name):
    return shared.restart_service(name)
end

function service_active(name):
    return shared.service_active(name)
end

function set_hostname_with(name, hostnamectl_command):
    return shared.set_hostname_with(name, hostnamectl_command)
end

function set_timezone_with(zone, timedatectl_command):
    return shared.set_timezone_with(zone, timedatectl_command)
end

function set_locale_with(locale, localectl_command):
    return shared.set_locale_with(locale, localectl_command)
end

function set_hostname(name):
    return shared.set_hostname(name)
end

function set_timezone(zone):
    return shared.set_timezone(zone)
end

function set_locale(locale):
    return shared.set_locale(locale)
end

function group_exists_with(name, getent_command):
    return shared.group_exists_with(name, getent_command)
end

function ensure_group_with(name, getent_command, groupadd_command):
    return shared.ensure_group_with(name, getent_command, groupadd_command)
end

function remove_group_with(name, groupdel_command):
    return shared.remove_group_with(name, groupdel_command)
end

function ensure_group(name):
    return shared.ensure_group(name)
end

function remove_group(name):
    return shared.remove_group(name)
end

function user_exists_with(name, id_command):
    return shared.user_exists_with(name, id_command)
end

function ensure_user_with(name, shell, groups, id_command, useradd_command, usermod_command):
    return shared.ensure_user_with(name, shell, groups, id_command, useradd_command, usermod_command)
end

function remove_user_with(name, userdel_command):
    return shared.remove_user_with(name, userdel_command)
end

function ensure_user(name, shell, groups):
    return shared.ensure_user(name, shell, groups)
end

function remove_user(name):
    return shared.remove_user(name)
end

function validate_file_tools(tools):
    return shared.validate_file_tools(tools)
end

function detected_file_tools():
    return shared.detected_file_tools()
end

function write_file_with(path, content, mode, owner, group, tools):
    return shared.write_file_with(path, content, mode, owner, group, tools)
end

function write_file(path, content, mode):
    return shared.write_file(path, content, mode)
end

function write_owned_file(path, content, mode, owner, group):
    return shared.write_owned_file(path, content, mode, owner, group)
end

function ensure_directory_with(path, mode, mkdir_command, chmod_command):
    return shared.ensure_directory_with(path, mode, mkdir_command, chmod_command)
end

function ensure_directory(path, mode):
    return shared.ensure_directory(path, mode)
end

function remove_file(path):
    return shared.remove_file(path)
end

function validate_mount_options(options):
    return shared.validate_mount_options(options)
end

function ensure_mount_with(device, target, filesystem, options, mountpoint_command, mkdir_command, mount_command):
    return shared.ensure_mount_with(device, target, filesystem, options, mountpoint_command, mkdir_command, mount_command)
end

function unmount_with(target, umount_command):
    return shared.unmount_with(target, umount_command)
end

function ensure_mount(device, target, filesystem, options):
    return shared.ensure_mount(device, target, filesystem, options)
end

function unmount(target):
    return shared.unmount(target)
end

function lux_command():
    return shared.lux_command()
end

function check_system_with(config_path, lux_command_path):
    return shared.check_system_with(config_path, lux_command_path)
end

function apply_system_with(config_path, dry_run, lux_command_path):
    return shared.apply_system_with(config_path, dry_run, lux_command_path)
end

function lux_status_with(lux_command_path):
    return shared.lux_status_with(lux_command_path)
end

function generations_with(lux_command_path):
    return shared.generations_with(lux_command_path)
end

function rollback_with(generation, dry_run, lux_command_path):
    return shared.rollback_with(generation, dry_run, lux_command_path)
end

function check_system(config_path):
    return shared.check_system(config_path)
end

function apply_system(config_path):
    return shared.apply_system(config_path)
end

function dry_run_system(config_path):
    return shared.dry_run_system(config_path)
end

function lux_status():
    return shared.lux_status()
end

function generations():
    return shared.generations()
end

function rollback(generation):
    return shared.rollback(generation)
end

function rollback_dry(generation):
    return shared.rollback_dry(generation)
end
