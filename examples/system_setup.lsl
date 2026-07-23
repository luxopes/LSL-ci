# Normal LSL program. Running it changes the host and requires root privileges.
load system

call system.set_hostname("luxos")
call system.set_timezone("Europe/Prague")
call system.set_locale("C.UTF-8")
call system.refresh()
for package in ["git", "curl", "ca-certificates", "openssh-server"]:
    backend = system.install(package)
    print package, "installed by", backend
end

call system.ensure_group("developers")
call system.ensure_user("lux", "/usr/local/bin/luxsh", ["developers", "sudo"])
call system.write_file("/etc/motd", "Welcome to LuxOS\n", "0644")
call system.enable_service("ssh.service")
