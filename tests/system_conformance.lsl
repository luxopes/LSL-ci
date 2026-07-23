load system

manager = "/tmp/lsl-system-package-server"
print system.install_with("lux-editor", manager, manager)
print system.install_with("lux-solo", manager, None)
print system.install_with("git", manager, manager)
print system.update_with("lux-editor", manager, manager)
print system.update_with("curl", manager, manager)
print system.remove_with("lux-editor", manager, manager)
print system.remove_with("nano", manager, manager)

try:
    call system.install_with("apt-fail", manager, manager)
else:
    print "apt-failure", "status 43" in last_error()
end
try:
    call system.install_with("missing", manager, None)
else:
    print "lux-failure", "status 42" in last_error(), "apt is unavailable" in last_error()
end
try:
    call system.install_with("git", None, None)
else:
    print "manager-failure", "no Lux or apt" in last_error()
end
try:
    call system.install_with("-option", manager, manager)
else:
    print last_error()
end
try:
    call system.install_with(" ", manager, manager)
else:
    print last_error()
end
try:
    call system.install_with("bad name", manager, manager)
else:
    print last_error()
end
try:
    call system.install_with(7, manager, manager)
else:
    print last_error()
end
