load _platform as platform
load assembler
load backend_x86_64
load fd
load frontend
load runtime
load target
load unixsock
load update_install

selected = target.resolve("linux-x86_64")
check(runtime.select(selected) == platform.RUNTIME, "target runtime selection differs from library platform")
for field in ["runtime", "platform_module", "os", "architecture"]:
    wrong = Dictionary(selected)
    wrong[field] = "unsupported"
    rejected = False
    try:
        call runtime.select(wrong)
    else:
        rejected = True
    end
    check(rejected, "mixed target runtime descriptor was accepted")
end
output = assembler.builder()
rejected = False
try:
    call runtime.emit_all("unsupported", output)
else:
    rejected = True
end
check(rejected and len(output["code"]) == 0, "runtime rejection emitted partial machine code")

stdlib_source = readfile("compiler/pure/dynamic_stdlib.lsl")
unit = frontend.prepare("platform-probe.lsl", "load _platform as kernel\nprint kernel.NAME\n", stdlib_source, 1, False, selected["platform_module"])
concrete = False
for statement in unit["program"]:
    path = statement.get("path", "")
    check(not path.endswith("/_platform.lsl"), "frontend linked the bootstrap facade instead of the target module")
    if path.endswith("/_platform_linux_x86_64.lsl"):
        concrete = True
    end
end
check(concrete, "frontend did not link the target platform module")
unit["platform_module"] = "unsupported"
rejected = False
try:
    call backend_x86_64.generate_object(unit, selected)
else:
    rejected = "platform does not match" in last_error()
end
check(rejected, "backend accepted library metadata from another platform")

# Kernel skutečně přečte iovec/msghdr/cmsghdr a přenese živý descriptor.
pair = __lsl_byte_zeros(2 * platform.INT_BYTES)
check(__lsl_syscall(platform.SYS_SOCKETPAIR, platform.AF_UNIX, platform.SOCK_STREAM + platform.SOCK_CLOEXEC, 0, unixsock.u_address(pair)) == 0, "socketpair failed")
left = unixsock.u_get32(pair, 0)
right = unixsock.u_get32(pair, platform.INT_BYTES)
memory = unixsock.memfd("lsl-platform-probe", 4)
check(memory >= 0, "memfd creation failed")
content = ByteArray()
for value in [11, 22, 33, 44]:
    content.append(Int(value))
end
call fd.write(memory, content, 4)
call fd.seek(memory, 0)
payload = ByteArray()
for value in [65, 66, 67]:
    payload.append(Int(value))
end
check(unixsock.send_fd(left, payload, 3, memory) == 3, "SCM_RIGHTS send failed")
call fd.close(memory)
call gc()
received = __lsl_byte_zeros(4)
handles = []
check(unixsock.recv_fds(right, received, 4, handles) == 3, "SCM_RIGHTS receive failed")
check(len(handles) == 1 and received[0] == 65 and received[2] == 67, "control message or payload layout differs")
check(fd.read(handles[0], received, 4) == 4 and received == content, "received descriptor lost its backing file")
call fd.close(handles[0])
check(unixsock.send_from(right, payload, 1, 2) == 2, "offset socket write failed")
handles = []
check(unixsock.recv_fds(left, received, 4, handles) == 2 and len(handles) == 0 and received[0] == 66 and received[1] == 67, "offset socket payload differs")
call fd.close(left)
call fd.close(right)

# Dvě knihovny sestaví tentýž sockaddr_un pro reálný filesystem socket.
work = update_install.private_work("/tmp")
path = work + "/socket"
listener = unixsock.listen_unix(path, 1)
check(listener >= 0, "unix listener failed")
client = fd.connect_unix(path)
peer = unixsock.accept_unix(listener)
check(peer >= 0, "unix accept failed")
check(unixsock.send_bytes(client, payload, 3) == 3, "unix connection write failed")
check(fd.read(peer, received, 4) == 3 and received[0] == 65 and received[2] == 67, "unix connection address or read differs")
call fd.close(client)
call fd.close(peer)
call fd.close(listener)
call update_install.cleanup_scratch(work)
print "target runtime selection, platform linking, unix sockets and SCM_RIGHTS passed"
