# Modul tls nad OpenSSL na loopbacku: TLS 1.3 s připnutým klíčem, ALPN,
# přednost šifer serveru, data oběma směry, mTLS (volitelný, chybějící,
# povinný), TLS 1.2, nesouhlas verzí a ALPN, close_notify, časový limit
# a odmítnutí certifikátu podepsaného sebou samým při ověření systémovými CA.
# Obě strany běží v jednom procesu na neblokujících soketech (handshake_step).
load net
load tls
load crypto

server_key = crypto.ec_generate()
server_cert = crypto.self_signed_certificate(server_key, "LuxDrop server")
client_key = crypto.ec_generate()
client_cert = crypto.self_signed_certificate(client_key, "LuxDrop client")
server_fp = crypto.hex(crypto.sha256(crypto.public_key_der(server_key)))
client_fp = crypto.hex(crypto.sha256(crypto.public_key_der(client_key)))

function server_context():
    handle = tls.context("server")
    call tls.use_certificate(handle, server_cert, server_key)
    call tls.set_ciphersuites(handle, "TLS_AES_256_GCM_SHA384:TLS_CHACHA20_POLY1305_SHA256:TLS_AES_128_GCM_SHA256")
    call tls.server_preference(handle, True)
    call tls.set_alpn(handle, ["luxdrop/1"])
    return handle
end

# [server, klient] po dokončeném handshaku; chyba handshaku se propaguje.
function connect_pair(server_handle, client_handle):
    listener = net.tcp_listen("127.0.0.1", 0)
    port = net.local_address(listener)[1]
    client_socket = net.tcp_connect("127.0.0.1", port, 2000)
    accepted = net.accept(listener, 2000)
    call net.close(listener)
    call net.set_nonblocking(client_socket, True)
    call net.set_nonblocking(accepted[0], True)
    server_side = tls.server(server_handle, accepted[0])
    client_side = tls.client(client_handle, client_socket)
    server_done = False
    client_done = False
    rounds = 0
    while not (server_done and client_done) and rounds < 100000:
        if not client_done:
            client_done = tls.handshake_step(client_side) == "done"
        end
        if not server_done:
            server_done = tls.handshake_step(server_side) == "done"
        end
        rounds += 1
    end
    return [server_side, client_side]
end

function close_pair(pair):
    call tls.close(pair[0])
    call tls.close(pair[1])
end

# 1. TLS 1.3, klient bez ověření řetězce, připnutí klíče serveru.
server_handle = server_context()
client_handle = tls.context("client")
call tls.set_versions(client_handle, "1.3", "1.3")
call tls.set_ciphersuites(client_handle, "TLS_CHACHA20_POLY1305_SHA256:TLS_AES_256_GCM_SHA384")
call tls.set_alpn(client_handle, ["luxdrop/1"])
pair = connect_pair(server_handle, client_handle)
print "version:", tls.version(pair[1]), tls.version(pair[0])
print "cipher (server preference):", tls.cipher(pair[1]), tls.cipher(pair[0])
print "alpn:", tls.alpn(pair[1]), tls.alpn(pair[0])
print "pinned server key:", crypto.hex(crypto.sha256(tls.peer_spki(pair[1]))) == server_fp
print "server cert der:", crypto.constant_time_equal(tls.peer_certificate_der(pair[1]), crypto.certificate_der(server_cert))
print "no client certificate:", len(tls.peer_certificate_der(pair[0])), tls.peer_certificate(pair[0]) == 0

payload = "x" * 100000 + "konec"
print "written:", tls.write(pair[1], payload, 2000)
received = ByteArray()
while len(received) < 100005:
    chunk = tls.read(pair[0], 65536, 2000)
    for byte in chunk:
        received.append(byte)
    end
end
print "received:", len(received), crypto.constant_time_equal(received, payload)
call tls.write(pair[0], "odpověď", 2000)
print "reply:", net.text(tls.read(pair[1], 100, 2000))
try:
    call tls.read(pair[0], 100, 50)
else:
    print "timeout:", last_error()
end
call tls.shutdown(pair[1])
print "close_notify:", len(tls.read(pair[0], 100, 2000))
call close_pair(pair)

# 2. ALPN bez shody: spojení pokračuje bez ALPN.
other_client = tls.context("client")
call tls.set_alpn(other_client, ["http/1.1"])
pair = connect_pair(server_handle, other_client)
print "alpn mismatch:", "[" + tls.alpn(pair[1]) + "]", "[" + tls.alpn(pair[0]) + "]"
call close_pair(pair)

# 3. mTLS: server chce certifikát klienta, přijme podepsaný sebou samým.
mtls_server = server_context()
call tls.request_client_certificate(mtls_server, False)
mtls_client = tls.context("client")
call tls.use_certificate(mtls_client, client_cert, client_key)
pair = connect_pair(mtls_server, mtls_client)
print "mtls client key:", crypto.hex(crypto.sha256(tls.peer_spki(pair[0]))) == client_fp
peer = tls.peer_certificate(pair[0])
print "mtls client cn:", crypto.certificate_common_name(peer)
call crypto.certificate_free(peer)
call close_pair(pair)
plain_client = tls.context("client")
pair = connect_pair(mtls_server, plain_client)
print "optional client certificate missing:", len(tls.peer_spki(pair[0]))
call close_pair(pair)
required_server = server_context()
call tls.request_client_certificate(required_server, True)
try:
    pair = connect_pair(required_server, plain_client)
    print "required client certificate: accepted"
else:
    print "required client certificate:", String(last_error()).startswith("TLSError: handshake")
end

# 4. TLS 1.2 (LocalSend dovoluje 1.2 i 1.3).
legacy_server = server_context()
call tls.set_versions(legacy_server, "1.2", "1.2")
pair = connect_pair(legacy_server, tls.context("client"))
print "tls 1.2:", tls.version(pair[1]), tls.cipher(pair[1]).startswith("ECDHE-ECDSA-")
call close_pair(pair)
try:
    pair = connect_pair(legacy_server, client_handle)
    print "1.3-only client vs 1.2 server: connected"
else:
    print "1.3-only client vs 1.2 server:", String(last_error()).startswith("TLSError: handshake")
end

# 5. Ověření systémovými CA odmítne certifikát podepsaný sebou samým.
strict_client = tls.context("client")
call tls.verify_system(strict_client)
try:
    pair = connect_pair(server_handle, strict_client)
    print "system verification: accepted"
else:
    print "system verification:", String(last_error()).find("self-signed certificate") >= 0
end
