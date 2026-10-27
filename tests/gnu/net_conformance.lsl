# Sokety modulu net na loopbacku: TCP (IPv4, IPv6, časový limit, konec
# spojení), UDP, multicast a napojení na hlavní smyčku GLib.
load net
load glib

listener = net.tcp_listen("127.0.0.1", 0)
port = net.local_address(listener)[1]
print "listen port > 0:", port > 0
client = net.tcp_connect("127.0.0.1", port, 2000)
accepted = net.accept(listener, 2000)
print "accepted:", len(accepted), accepted[1]
server = accepted[0]
print "sent:", net.send(client, "ahoj světe", 1000)
data = net.recv(server, 100, 1000)
print "received:", net.text(data)
try:
    call net.recv(server, 100, 50)
else:
    print "timeout:", last_error()
end
call net.close(client)
print "eof:", len(net.recv(server, 100, 1000))
call net.close(server)
print "no pending accept:", len(net.accept(listener, 10))
call net.close(listener)

listener6 = net.tcp_listen("::1", 0)
port6 = net.local_address(listener6)[1]
client6 = net.tcp_connect("::1", port6, 2000)
accepted6 = net.accept(listener6, 2000)
print "ipv6 peer:", accepted6[1]
call net.close(client6)
call net.close(accepted6[0])
call net.close(listener6)

try:
    call net.tcp_connect("127.0.0.1", 1, 1000)
else:
    print "refused:", last_error()
end

udp = net.udp_open("ipv4")
call net.udp_bind(udp, "127.0.0.1", 0)
udp_port = net.local_address(udp)[1]
sender = net.udp_open("ipv4")
print "udp sent:", net.sendto(sender, "datagram", "127.0.0.1", udp_port)
packet = net.recvfrom(udp, 100, 1000)
print "udp received:", net.text(packet[0]), packet[1]
print "udp timeout:", len(net.recvfrom(udp, 100, 20))
call net.close(udp)

# Multicast na loopbacku: skupina jako LocalSend, rozhraní 127.0.0.1.
group = "224.0.0.167"
receiver = net.udp_open("ipv4")
call net.udp_bind(receiver, "0.0.0.0", 0)
mport = net.local_address(receiver)[1]
call net.multicast_join(receiver, group, "127.0.0.1")
call net.multicast_interface(sender, "127.0.0.1")
call net.multicast_loop(sender, True)
call net.multicast_ttl(sender, 1)
call net.sendto(sender, "{\"alias\":\"test\"}", group, mport)
mpacket = net.recvfrom(receiver, 1000, 2000)
print "multicast:", len(mpacket) == 3 and net.text(mpacket[0]) == "{\"alias\":\"test\"}"
call net.multicast_leave(receiver, group, "127.0.0.1")
call net.close(receiver)

found_loopback = False
for entry in net.interfaces():
    if entry[2] == "127.0.0.1":
        found_loopback = True
    end
end
print "loopback interface:", found_loopback

# GLib: data na soketu zavolají obsluhu v hlavní smyčce.
calls = []
function readable(fd, condition):
    incoming = net.recvfrom(fd, 100, 0)
    calls.append(net.text(incoming[0]))
    call glib.main_quit()
    return False
end
watched = net.udp_open("ipv4")
call net.udp_bind(watched, "127.0.0.1", 0)
call glib.fd_add(watched, glib.IO_IN, readable)
call net.sendto(sender, "loop", "127.0.0.1", net.local_address(watched)[1])
call glib.main()
print "glib watch:", calls
call net.close(watched)
call net.close(sender)
