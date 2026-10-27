# lsl: internal-abi
# lsl: link libc.so.6
# Sokety TCP a UDP (cíl linux-x86_64-gnu): servery a klienti IPv4 i IPv6
# včetně adres link-local se zónou ("fe80::1%wlan0"), časové limity přes
# poll(), UDP multicast (přihlášení ke skupině, rozhraní, TTL, smyčka) a
# výpis adres rozhraní. Soket je číslo deskriptoru (Int); modul tls nad ním
# staví šifrované spojení a glib.fd_add() ho napojí na hlavní smyčku GLib.
#
# Chyby systému jsou OSError s textem strerror(), vypršení limitu
# TimeoutError. Data pro odeslání jsou String nebo ByteArray, přijatá data
# ByteArray (prázdný = druhá strana spojení zavřela).
#
# Pravidla uvnitř modulu jako v glib: argumenty z běžného kódu jsou
# zabalené, do C je rozbalí ptr(); None a 0 jsou v interním ABI stejné
# slovo, proto funkce místo None vracejí prázdný List nebo vyhodí chybu.

AF_INET = 2
AF_INET6 = 10
SOCK_STREAM = 1
SOCK_DGRAM = 2
SOCK_CLOEXEC = 524288
SOL_SOCKET = 1
SO_REUSEADDR = 2
SO_ERROR = 4
SO_BROADCAST = 6
SO_REUSEPORT = 15
IPPROTO_IP = 0
IPPROTO_TCP = 6
IPPROTO_IPV6 = 41
TCP_NODELAY = 1
IP_MULTICAST_IF = 32
IP_MULTICAST_TTL = 33
IP_MULTICAST_LOOP = 34
IP_ADD_MEMBERSHIP = 35
IP_DROP_MEMBERSHIP = 36
IPV6_MULTICAST_IF = 17
IPV6_MULTICAST_HOPS = 18
IPV6_MULTICAST_LOOP = 19
IPV6_JOIN_GROUP = 20
IPV6_LEAVE_GROUP = 21
IPV6_V6ONLY = 26
AI_PASSIVE = 1
AI_NUMERICHOST = 4
AI_NUMERICSERV = 1024
NI_NUMERICHOST = 1
NI_NUMERICSERV = 2
POLLIN = 1
POLLOUT = 4
POLLERR = 8
POLLHUP = 16
F_GETFL = 3
F_SETFL = 4
O_NONBLOCK = 2048
EINTR = 4
EAGAIN = 11
EINPROGRESS = 115
MSG_NOSIGNAL = 16384
SHUT_RD = 0
SHUT_WR = 1
SHUT_RDWR = 2

function cstr(text):
    return __lsl_address(text) + 16
end

function ptr(value):
    return __lsl_unbox_int(value)
end

# Paměť ByteArray (jako glib.array_data).
function bytes_data(bytes):
    return __lsl_qbe_load64(__lsl_address(bytes) + 24)
end

function from_c(address):
    raw = ptr(address)
    if raw == 0:
        return ""
    end
    length = __lsl_qbe_call1(__lsl_symbol("strlen"), raw)
    bytes = __lsl_byte_zeros(length)
    call __lsl_qbe_call3(__lsl_symbol("memcpy"), bytes_data(bytes), raw, length)
    return __lsl_text_from_bytes(bytes, 0, length)
end

# ByteArray s kopií length bajtů z paměti C.
function bytes_from_c(address, length):
    bytes = __lsl_byte_zeros(ptr(length))
    if ptr(length) > 0:
        call __lsl_qbe_call3(__lsl_symbol("memcpy"), bytes_data(bytes), ptr(address), ptr(length))
    end
    return bytes
end

function errno():
    return __lsl_qbe_s32(__lsl_qbe_load32(__lsl_qbe_call0(__lsl_symbol("__errno_location"))))
end

# Text chyby systému pro číslo errno.
function error_text(code):
    return from_c(__lsl_qbe_call1(__lsl_symbol("strerror"), ptr(code)))
end

function fail(action):
    code = errno()
    Error(OSError: action + ": " + error_text(code))
end

# Ukazatel a délka dat k odeslání (String nebo ByteArray).
function data_pointer(data):
    if type(data) == "String":
        return cstr(data)
    end
    return bytes_data(data)
end

function data_length(data):
    if type(data) == "String":
        return __lsl_text_byte_length(data)
    end
    return len(data)
end

# String z bajtů UTF-8 (ByteArray z recv/recvfrom; část od start délky count,
# count < 0 = do konce).
function text(bytes, start=0, count=-1):
    size = len(bytes)
    first = ptr(start)
    length = ptr(count)
    if first < 0 or first > size:
        Error(ValueError: "text start out of range")
    end
    if length < 0 or first + length > size:
        length = size - first
    end
    return __lsl_text_from_bytes(bytes, first, length)
end

# ByteArray s bajty UTF-8 Stringu.
function bytes(value):
    length = __lsl_text_byte_length(value)
    result = __lsl_byte_zeros(length)
    if length > 0:
        call __lsl_qbe_call3(__lsl_symbol("memcpy"), bytes_data(result), cstr(value), length)
    end
    return result
end

# --- adresy ---

# getaddrinfo: seznam [rodina, adresa sockaddr (ByteArray)]. Prázdný host
# při passive znamená všechny adresy (IPv4 0.0.0.0).
function resolve(host, port, kind, passive):
    hints = __lsl_byte_zeros(48)
    flags = AI_NUMERICSERV
    if passive:
        flags = flags | AI_PASSIVE
    end
    call __lsl_qbe_store32(bytes_data(hints), flags)
    call __lsl_qbe_store32(bytes_data(hints) + 8, ptr(kind))
    result_cell = __lsl_byte_zeros(8)
    service = String(port)
    node = 0
    if host != "":
        node = cstr(host)
    end
    status = __lsl_qbe_icall4(__lsl_symbol("getaddrinfo"), node, cstr(service), bytes_data(hints), bytes_data(result_cell))
    if status != 0:
        Error(OSError: "cannot resolve " + String(host) + ": " + from_c(__lsl_qbe_call1(__lsl_symbol("gai_strerror"), status)))
    end
    first = __lsl_qbe_load64(bytes_data(result_cell))
    result = []
    item = first
    while item != 0:
        family = __lsl_qbe_s32(__lsl_qbe_load32(item + 4))
        length = __lsl_qbe_load32(item + 16)
        address = bytes_from_c(__lsl_qbe_load64(item + 24), length)
        result.append([family, address])
        item = __lsl_qbe_load64(item + 40)
    end
    call __lsl_qbe_call1(__lsl_symbol("freeaddrinfo"), first)
    return result
end

# [adresa, port] ze sockaddr (getnameinfo; IPv6 link-local se zónou).
function describe(address, length):
    host = __lsl_byte_zeros(1025)
    service = __lsl_byte_zeros(32)
    status = __lsl_qbe_icall7(__lsl_symbol("getnameinfo"), ptr(address), ptr(length), bytes_data(host), 1025, bytes_data(service), 32, NI_NUMERICHOST | NI_NUMERICSERV)
    if status != 0:
        return ["", 0]
    end
    return [from_c(bytes_data(host)), Int(from_c(bytes_data(service)))]
end

# Adresa IPv4 v pořadí sítě (inet_pton) jako Int pro struktury multicastu.
function ipv4_word(text):
    cell = __lsl_byte_zeros(4)
    if __lsl_qbe_icall3(__lsl_symbol("inet_pton"), AF_INET, cstr(text), bytes_data(cell)) != 1:
        Error(ValueError: "not an IPv4 address: " + String(text))
    end
    return __lsl_qbe_load32(bytes_data(cell))
end

# Index rozhraní podle jména (0 = výchozí).
function interface_index(name):
    if name == "":
        return 0
    end
    index = __lsl_qbe_icall1(__lsl_symbol("if_nametoindex"), cstr(name))
    if index == 0:
        call fail("unknown interface " + String(name))
    end
    return index
end

# --- deskriptory ---

function set_option(fd, level, name, value):
    cell = __lsl_byte_zeros(4)
    call __lsl_qbe_store32(bytes_data(cell), ptr(value))
    if __lsl_qbe_icall5(__lsl_symbol("setsockopt"), ptr(fd), ptr(level), ptr(name), bytes_data(cell), 4) < 0:
        call fail("setsockopt")
    end
    return 0
end

function get_option(fd, level, name):
    cell = __lsl_byte_zeros(4)
    size = __lsl_byte_zeros(4)
    call __lsl_qbe_store32(bytes_data(size), 4)
    if __lsl_qbe_icall5(__lsl_symbol("getsockopt"), ptr(fd), ptr(level), ptr(name), bytes_data(cell), bytes_data(size)) < 0:
        call fail("getsockopt")
    end
    return __lsl_qbe_s32(__lsl_qbe_load32(bytes_data(cell)))
end

# Neblokující režim deskriptoru (pro hlavní smyčku GLib).
function set_nonblocking(fd, enabled):
    flags = __lsl_qbe_icall3(__lsl_symbol("fcntl"), ptr(fd), F_GETFL, 0)
    if flags < 0:
        call fail("fcntl")
    end
    if enabled:
        changed = flags | O_NONBLOCK
    else:
        changed = flags & (0 - 1 - O_NONBLOCK)
    end
    if __lsl_qbe_icall3(__lsl_symbol("fcntl"), ptr(fd), F_SETFL, changed) < 0:
        call fail("fcntl")
    end
    return 0
end

# Čekání na událost: vrací revents (POLLIN, POLLOUT, POLLERR, POLLHUP), nebo
# 0 po vypršení. timeout_ms < 0 čeká bez omezení.
function wait(fd, events, timeout_ms):
    cell = __lsl_byte_zeros(8)
    call __lsl_qbe_store32(bytes_data(cell), ptr(fd))
    call __lsl_qbe_store16(bytes_data(cell) + 4, ptr(events))
    loop:
        count = __lsl_qbe_icall3(__lsl_symbol("poll"), bytes_data(cell), 1, ptr(timeout_ms))
        if count >= 0:
            break
        end
        if errno() != EINTR:
            call fail("poll")
        end
    end
    if count == 0:
        return 0
    end
    return __lsl_qbe_load16(bytes_data(cell) + 6)
end

function require_ready(fd, events, timeout_ms, action):
    if wait(fd, events, timeout_ms) == 0:
        Error(TimeoutError: action + " timed out")
    end
    return 0
end

function close(fd):
    if __lsl_qbe_icall1(__lsl_symbol("close"), ptr(fd)) < 0:
        call fail("close")
    end
    return 0
end

# shutdown: SHUT_RD, SHUT_WR nebo SHUT_RDWR.
function shutdown(fd, how):
    if __lsl_qbe_icall2(__lsl_symbol("shutdown"), ptr(fd), ptr(how)) < 0:
        call fail("shutdown")
    end
    return 0
end

function address_of(fd, peer):
    storage = __lsl_byte_zeros(128)
    size = __lsl_byte_zeros(4)
    call __lsl_qbe_store32(bytes_data(size), 128)
    name = "getsockname"
    if peer:
        name = "getpeername"
    end
    if peer:
        status = __lsl_qbe_icall3(__lsl_symbol("getpeername"), ptr(fd), bytes_data(storage), bytes_data(size))
    else:
        status = __lsl_qbe_icall3(__lsl_symbol("getsockname"), ptr(fd), bytes_data(storage), bytes_data(size))
    end
    if status < 0:
        call fail(name)
    end
    return describe(bytes_data(storage), __lsl_qbe_load32(bytes_data(size)))
end

# [adresa, port] místní strany a protistrany.
function local_address(fd):
    return address_of(fd, False)
end

function peer_address(fd):
    return address_of(fd, True)
end

function open_socket(family, kind):
    fd = __lsl_qbe_icall3(__lsl_symbol("socket"), ptr(family), ptr(kind) | SOCK_CLOEXEC, 0)
    if fd < 0:
        call fail("socket")
    end
    return fd
end

function bind_address(fd, address):
    if __lsl_qbe_icall3(__lsl_symbol("bind"), ptr(fd), bytes_data(address), len(address)) < 0:
        code = errno()
        call __lsl_qbe_call1(__lsl_symbol("close"), ptr(fd))
        Error(OSError: "bind: " + error_text(code))
    end
    return 0
end

# --- TCP ---

# Naslouchající soket TCP: host "" (všechny adresy IPv4), "0.0.0.0", "::"
# (IPv6 i IPv4), konkrétní adresa nebo "fe80::…%rozhraní"; port 0 vybere
# systém (zjistí local_address). Vrací deskriptor.
function tcp_listen(host, port, backlog=64):
    addresses = resolve(host, port, SOCK_STREAM, True)
    if len(addresses) == 0:
        Error(OSError: "no address for " + String(host))
    end
    family = addresses[0][0]
    fd = open_socket(family, SOCK_STREAM)
    call set_option(fd, SOL_SOCKET, SO_REUSEADDR, 1)
    if family == AF_INET6 and host == "::":
        call set_option(fd, IPPROTO_IPV6, IPV6_V6ONLY, 0)
    end
    call bind_address(fd, addresses[0][1])
    if __lsl_qbe_icall2(__lsl_symbol("listen"), fd, ptr(backlog)) < 0:
        code = errno()
        call __lsl_qbe_call1(__lsl_symbol("close"), fd)
        Error(OSError: "listen: " + error_text(code))
    end
    return fd
end

# Přijme spojení: [deskriptor, adresa, port], nebo [] po vypršení limitu.
function accept(listener, timeout_ms=-1):
    if wait(listener, POLLIN, timeout_ms) == 0:
        return []
    end
    storage = __lsl_byte_zeros(128)
    size = __lsl_byte_zeros(4)
    call __lsl_qbe_store32(bytes_data(size), 128)
    fd = __lsl_qbe_icall4(__lsl_symbol("accept4"), ptr(listener), bytes_data(storage), bytes_data(size), SOCK_CLOEXEC)
    if fd < 0:
        code = errno()
        if code == EAGAIN or code == EINTR:
            return []
        end
        Error(OSError: "accept: " + error_text(code))
    end
    peer = describe(bytes_data(storage), __lsl_qbe_load32(bytes_data(size)))
    return [fd, peer[0], peer[1]]
end

# Spojení TCP na host (jméno nebo adresa) a port; zkouší adresy postupně,
# každou nejvýš timeout_ms. Vrací deskriptor v blokujícím režimu.
function tcp_connect(host, port, timeout_ms=10000):
    addresses = resolve(host, port, SOCK_STREAM, False)
    message = "no address"
    for entry in addresses:
        fd = open_socket(entry[0], SOCK_STREAM)
        call set_nonblocking(fd, True)
        address = entry[1]
        status = __lsl_qbe_icall3(__lsl_symbol("connect"), fd, bytes_data(address), len(address))
        code = 0
        if status < 0:
            code = errno()
            if code == EINPROGRESS:
                if wait(fd, POLLOUT, timeout_ms) == 0:
                    code = -1
                else:
                    code = get_option(fd, SOL_SOCKET, SO_ERROR)
                end
            end
        end
        if code == 0:
            call set_nonblocking(fd, False)
            return fd
        end
        call __lsl_qbe_call1(__lsl_symbol("close"), fd)
        if code < 0:
            message = "timed out"
        else:
            message = error_text(code)
        end
    end
    if message == "timed out":
        Error(TimeoutError: "connect to " + String(host) + " timed out")
    end
    Error(OSError: "connect to " + String(host) + ": " + message)
end

# TCP_NODELAY (malé zprávy hned, bez Naglova algoritmu).
function set_nodelay(fd, enabled):
    value = 0
    if enabled:
        value = 1
    end
    return set_option(fd, IPPROTO_TCP, TCP_NODELAY, value)
end

# Odešle všechna data; vrací počet bajtů. Limit platí pro každé čekání.
function send(fd, data, timeout_ms=-1):
    pointer = data_pointer(data)
    total = data_length(data)
    sent = 0
    while sent < total:
        count = __lsl_qbe_call4(__lsl_symbol("send"), ptr(fd), pointer + sent, total - sent, MSG_NOSIGNAL)
        if count < 0:
            code = errno()
            if code == EAGAIN:
                call require_ready(fd, POLLOUT, timeout_ms, "send")
            elif code != EINTR:
                Error(OSError: "send: " + error_text(code))
            end
        else:
            sent += count
        end
    end
    return sent
end

# Přijme nejvýš maximum bajtů: ByteArray (prázdný = konec spojení).
# Po vypršení limitu TimeoutError.
function recv(fd, maximum=65536, timeout_ms=-1):
    call require_ready(fd, POLLIN, timeout_ms, "recv")
    buffer = __lsl_byte_zeros(ptr(maximum))
    loop:
        count = __lsl_qbe_call4(__lsl_symbol("recv"), ptr(fd), bytes_data(buffer), ptr(maximum), 0)
        if count >= 0:
            break
        end
        code = errno()
        if code == EAGAIN:
            call require_ready(fd, POLLIN, timeout_ms, "recv")
        elif code != EINTR:
            Error(OSError: "recv: " + error_text(code))
        end
    end
    return bytes_from_c(bytes_data(buffer), count)
end

# --- UDP a multicast ---

# Soket UDP pro rodinu "ipv4" nebo "ipv6".
function udp_open(family="ipv4"):
    if family == "ipv6":
        return open_socket(AF_INET6, SOCK_DGRAM)
    end
    return open_socket(AF_INET, SOCK_DGRAM)
end

# Naváže soket UDP na adresu a port; reuse dovolí více posluchačů téhož
# portu (multicast, např. LocalSend 53317).
function udp_bind(fd, host, port, reuse=True):
    if reuse:
        call set_option(fd, SOL_SOCKET, SO_REUSEADDR, 1)
        call set_option(fd, SOL_SOCKET, SO_REUSEPORT, 1)
    end
    addresses = resolve(host, port, SOCK_DGRAM, True)
    if len(addresses) == 0:
        Error(OSError: "no address for " + String(host))
    end
    call bind_address(fd, addresses[0][1])
    return 0
end

function set_broadcast(fd, enabled):
    value = 0
    if enabled:
        value = 1
    end
    return set_option(fd, SOL_SOCKET, SO_BROADCAST, value)
end

# Přihlášení ke skupině IPv4 (interface = adresa rozhraní, "" = výchozí),
# nebo IPv6 (interface = jméno rozhraní).
function multicast_join(fd, group, interface=""):
    return membership(fd, group, interface, True)
end

function multicast_leave(fd, group, interface=""):
    return membership(fd, group, interface, False)
end

function membership(fd, group, interface, join):
    if group.find(":") >= 0:
        request = __lsl_byte_zeros(20)
        if __lsl_qbe_icall3(__lsl_symbol("inet_pton"), AF_INET6, cstr(group), bytes_data(request)) != 1:
            Error(ValueError: "not an IPv6 address: " + String(group))
        end
        call __lsl_qbe_store32(bytes_data(request) + 16, interface_index(interface))
        option = IPV6_LEAVE_GROUP
        if join:
            option = IPV6_JOIN_GROUP
        end
        if __lsl_qbe_icall5(__lsl_symbol("setsockopt"), ptr(fd), IPPROTO_IPV6, option, bytes_data(request), 20) < 0:
            call fail("multicast membership")
        end
        return 0
    end
    request = __lsl_byte_zeros(8)
    call __lsl_qbe_store32(bytes_data(request), ipv4_word(group))
    local = 0
    if interface != "":
        local = ipv4_word(interface)
    end
    call __lsl_qbe_store32(bytes_data(request) + 4, local)
    option = IP_DROP_MEMBERSHIP
    if join:
        option = IP_ADD_MEMBERSHIP
    end
    if __lsl_qbe_icall5(__lsl_symbol("setsockopt"), ptr(fd), IPPROTO_IP, option, bytes_data(request), 8) < 0:
        call fail("multicast membership")
    end
    return 0
end

# Rozhraní pro odchozí multicast: adresa IPv4 rozhraní, nebo jméno pro IPv6.
function multicast_interface(fd, interface, ipv6=False):
    if ipv6:
        return set_option(fd, IPPROTO_IPV6, IPV6_MULTICAST_IF, interface_index(interface))
    end
    cell = __lsl_byte_zeros(4)
    call __lsl_qbe_store32(bytes_data(cell), ipv4_word(interface))
    if __lsl_qbe_icall5(__lsl_symbol("setsockopt"), ptr(fd), IPPROTO_IP, IP_MULTICAST_IF, bytes_data(cell), 4) < 0:
        call fail("multicast interface")
    end
    return 0
end

function multicast_ttl(fd, ttl, ipv6=False):
    if ipv6:
        return set_option(fd, IPPROTO_IPV6, IPV6_MULTICAST_HOPS, ttl)
    end
    return set_option(fd, IPPROTO_IP, IP_MULTICAST_TTL, ttl)
end

# Doručení vlastních multicastových zpráv zpět na tentýž stroj.
function multicast_loop(fd, enabled, ipv6=False):
    value = 0
    if enabled:
        value = 1
    end
    if ipv6:
        return set_option(fd, IPPROTO_IPV6, IPV6_MULTICAST_LOOP, value)
    end
    return set_option(fd, IPPROTO_IP, IP_MULTICAST_LOOP, value)
end

# Datagram na host a port; vrací počet odeslaných bajtů.
function sendto(fd, data, host, port):
    addresses = resolve(host, port, SOCK_DGRAM, False)
    if len(addresses) == 0:
        Error(OSError: "no address for " + String(host))
    end
    address = addresses[0][1]
    count = __lsl_qbe_call6(__lsl_symbol("sendto"), ptr(fd), data_pointer(data), data_length(data), MSG_NOSIGNAL, bytes_data(address), len(address))
    if count < 0:
        call fail("sendto")
    end
    return count
end

# Datagram: [ByteArray, adresa, port], nebo [] po vypršení limitu.
function recvfrom(fd, maximum=65536, timeout_ms=-1):
    if wait(fd, POLLIN, timeout_ms) == 0:
        return []
    end
    buffer = __lsl_byte_zeros(ptr(maximum))
    storage = __lsl_byte_zeros(128)
    size = __lsl_byte_zeros(4)
    call __lsl_qbe_store32(bytes_data(size), 128)
    count = __lsl_qbe_call6(__lsl_symbol("recvfrom"), ptr(fd), bytes_data(buffer), ptr(maximum), 0, bytes_data(storage), bytes_data(size))
    if count < 0:
        code = errno()
        if code == EAGAIN or code == EINTR:
            return []
        end
        Error(OSError: "recvfrom: " + error_text(code))
    end
    peer = describe(bytes_data(storage), __lsl_qbe_load32(bytes_data(size)))
    return [bytes_from_c(bytes_data(buffer), count), peer[0], peer[1]]
end

# --- rozhraní ---

# Adresy rozhraní (getifaddrs): List [jméno, "ipv4"/"ipv6", adresa,
# maska, příznaky]; příznaky jsou IFF_* (UP 1, BROADCAST 2, LOOPBACK 8,
# RUNNING 64, MULTICAST 4096).
function interfaces():
    cell = __lsl_byte_zeros(8)
    if __lsl_qbe_icall1(__lsl_symbol("getifaddrs"), bytes_data(cell)) < 0:
        call fail("getifaddrs")
    end
    first = __lsl_qbe_load64(bytes_data(cell))
    result = []
    item = first
    while item != 0:
        address = __lsl_qbe_load64(item + 24)
        if address != 0:
            family = __lsl_qbe_load16(address)
            if family == AF_INET or family == AF_INET6:
                length = 16
                kind = "ipv4"
                if family == AF_INET6:
                    length = 28
                    kind = "ipv6"
                end
                shown = describe(address, length)
                mask = ""
                netmask = __lsl_qbe_load64(item + 32)
                if netmask != 0:
                    mask = describe(netmask, length)[0]
                end
                result.append([from_c(__lsl_qbe_load64(item + 8)), kind, shown[0], mask, __lsl_qbe_load32(item + 16)])
            end
        end
        item = __lsl_qbe_load64(item)
    end
    call __lsl_qbe_call1(__lsl_symbol("freeifaddrs"), first)
    return result
end
