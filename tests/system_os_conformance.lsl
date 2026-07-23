load system

apt = "/tmp/lsl-system-command-apt"
systemctl = "/tmp/lsl-system-command-systemctl"
account = "/tmp/lsl-system-command-account"
file_tool = "/tmp/lsl-system-command-file-tool"
mount_tool = "/tmp/lsl-system-command-mount-tool"
lux = "/tmp/lsl-system-command-lux"

print system.refresh_with(apt)
call system.enable_service_with("ssh.service", systemctl)
call system.disable_service_with("old.service", systemctl)
call system.restart_service_with("web.service", systemctl)
print system.service_active_with("active.service", systemctl)
print system.service_active_with("inactive.service", systemctl)
call system.set_hostname_with("luxos", systemctl)
call system.set_timezone_with("Europe/Prague", systemctl)
call system.set_locale_with("C.UTF-8", systemctl)

print system.ensure_group_with("existing", account, account)
print system.ensure_group_with("developers", account, account)
call system.remove_group_with("oldgroup", account)
print system.ensure_user_with("existing", "/bin/luxsh", ["adm", "sudo"], account, account, account)
print system.ensure_user_with("ada", "/bin/luxsh", ["developers"], account, account, account)
call system.remove_user_with("olduser", account)

target = "/tmp/lsl-system-managed-file"
temporary = "/tmp/lsl-system-managed-temp"
call system.remove_file(target)
call system.remove_file(temporary)
tools = {"mkdir": file_tool, "mktemp": file_tool, "chmod": file_tool, "chown": file_tool, "mv": file_tool}
call system.write_file_with(target, "first\n", "0640", None, None, tools)
print readfile(target) == "first\n"
call system.write_file_with(target, "owned\n", "0600", "root", "root", tools)
print readfile(target) == "owned\n"
call system.ensure_directory_with("/tmp/lsl-system-directory", "0750", file_tool, file_tool)
call system.remove_file(target)
print not exists(target)

print system.ensure_mount_with("/dev/vdb1", "/tmp/lsl-system-mount", "ext4", ["rw", "noatime"], mount_tool, mount_tool, mount_tool)
print system.ensure_mount_with("/dev/vdb1", "/tmp/lsl-system-active-mount", "ext4", [], mount_tool, mount_tool, mount_tool)
call system.unmount_with("/tmp/lsl-system-mount", mount_tool)

call system.check_system_with("/etc/luxos/system.lsl", lux)
call system.apply_system_with("/etc/luxos/system.lsl", False, lux)
call system.apply_system_with("/etc/luxos/system.lsl", True, lux)
print system.lux_status_with(lux).strip()
print system.generations_with(lux).strip()
call system.rollback_with("test-generation", False, lux)
call system.rollback_with("test-generation", True, lux)

try:
    call system.enable_service_with("bad service", systemctl)
else:
    print last_error()
end
try:
    call system.enable_service_with("fail.service", systemctl)
else:
    print "service-failure", "status 5" in last_error()
end
try:
    call system.service_active_with("error.service", systemctl)
else:
    print "service-query-failure", "status 4" in last_error()
end
try:
    call system.ensure_group_with("BadGroup", account, account)
else:
    print last_error()
end
try:
    call system.write_file_with("relative", "x", "0644", None, None, tools)
else:
    print last_error()
end
try:
    call system.ensure_mount_with("/dev/vdb1", "/tmp/x", "ext4", "rw", mount_tool, mount_tool, mount_tool)
else:
    print last_error()
end
try:
    call system.ensure_directory_with("/", "0755", file_tool, file_tool)
else:
    print last_error()
end
try:
    call system.write_file_with("/tmp/bad-mode", "x", "0999", None, None, tools)
else:
    print last_error()
end
