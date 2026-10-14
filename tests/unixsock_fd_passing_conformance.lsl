# Socket Unixu s předáním deskriptoru (SCM_RIGHTS) na Linuxu i macOS:
# server, klient, zpráva s koncem roury a čtení přes přijatý deskriptor.
load unixsock
load fd
load env
load random

directory = env.get("TMPDIR", "/tmp")
if directory.endswith("/"):
    directory = directory[0:len(directory) - 1]
end
path = directory + "/lsl-us-" + String(random.randint(100000000, 999999999))
server = unixsock.listen_unix(path, 4)
client = fd.connect_unix(path)
peer = -11
while peer < 0:
    peer = unixsock.accept_unix(server)
end
ends = unixsock.pipe_nonblock()
secret = ByteArray()
for character in "secret":
    secret.append(ord(character))
end
call fd.write(ends[1], secret, len(secret))
payload = ByteArray()
for character in "hello":
    payload.append(ord(character))
end
sent = unixsock.send_fd(client, payload, len(payload), ends[0])
received = __lsl_byte_zeros(16)
fds = []
count = -11
while count == -11:
    count = unixsock.recv_fds(peer, received, 16, fds)
end
data = __lsl_byte_zeros(16)
got = -11
while got == -11:
    got = fd.read(fds[0], data, 16)
end
print sent, count, len(fds), __lsl_text_from_bytes(received, 0, count), __lsl_text_from_bytes(data, 0, got)
shared = unixsock.memfd("lsl-test", 4096)
print shared >= 0
for handle in [shared, fds[0], ends[0], ends[1], peer, client, server]:
    call unixsock.close_fd(handle)
end
call unlink(path)
