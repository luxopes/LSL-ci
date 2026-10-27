# lsl: internal-abi
# lsl: link libssl.so.3 libcrypto.so.3
# TLS 1.2 a 1.3 nad systémovým OpenSSL (libssl, cíl linux-x86_64-gnu):
# klient i server nad soketem modulu net, vlastní certifikát a klíč (modul
# crypto nebo soubory PEM), ověření řetězce systémovými CA, nebo bez něj
# s připnutím klíče aplikací (peer_spki → crypto.sha256), certifikát klienta
# (mTLS), ALPN, výběr a pořadí šifer, přednost šifer serveru a čtení
# vyjednané verze, šifry a ALPN. Čtení a zápis mají časový limit;
# neblokující soket (net.set_nonblocking) a handshake_step/glib.fd_add
# napojí spojení na hlavní smyčku GLib bez zamrznutí GUI.
#
# Kontext (SSL_CTX) a spojení (SSL) jsou surové ukazatele (Int). Chyby jsou
# TLSError s textem z fronty chyb OpenSSL, vypršení limitu TimeoutError.

load net

SSL_VERIFY_NONE = 0
SSL_VERIFY_PEER = 1
SSL_VERIFY_FAIL_IF_NO_PEER_CERT = 2
SSL_FILETYPE_PEM = 1
SSL_ERROR_SSL = 1
SSL_ERROR_WANT_READ = 2
SSL_ERROR_WANT_WRITE = 3
SSL_ERROR_SYSCALL = 5
SSL_ERROR_ZERO_RETURN = 6
SSL_CTRL_SET_SESS_CACHE_MODE = 44
SSL_CTRL_SET_TLSEXT_HOSTNAME = 55
SSL_CTRL_SET_MIN_PROTO_VERSION = 123
SSL_CTRL_SET_MAX_PROTO_VERSION = 124
SSL_OP_NO_TICKET = 16384
SSL_OP_CIPHER_SERVER_PREFERENCE = 4194304
TLS1_2_VERSION = 771
TLS1_3_VERSION = 772

function cstr(text):
    return __lsl_address(text) + 16
end

function ptr(value):
    return __lsl_unbox_int(value)
end

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

function bytes_from_c(address, length):
    bytes = __lsl_byte_zeros(ptr(length))
    if ptr(length) > 0:
        call __lsl_qbe_call3(__lsl_symbol("memcpy"), bytes_data(bytes), ptr(address), ptr(length))
    end
    return bytes
end

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

# Text všech chyb ve frontě OpenSSL (fronta se vyprázdní).
function openssl_error():
    parts = []
    loop:
        code = __lsl_qbe_call0(__lsl_symbol("ERR_get_error"))
        if code == 0:
            break
        end
        buffer = __lsl_byte_zeros(256)
        call __lsl_qbe_call3(__lsl_symbol("ERR_error_string_n"), code, bytes_data(buffer), 256)
        parts.append(from_c(bytes_data(buffer)))
    end
    if len(parts) == 0:
        return "unknown OpenSSL error"
    end
    return "; ".join(parts)
end

function fail(action):
    Error(TLSError: action + ": " + openssl_error())
end

function version_number(text):
    if text == "1.2":
        return TLS1_2_VERSION
    elif text == "1.3":
        return TLS1_3_VERSION
    end
    Error(ValueError: "TLS version must be \"1.2\" or \"1.3\", got " + String(text))
end

# --- kontext ---

# Nový kontext pro role "client" nebo "server": TLS 1.2 až 1.3, bez
# ověření protistrany (nastaví verify_system nebo request_client_certificate)
# a bez obnovy relace (session tickets a cache vypnuté).
function context(role):
    if role == "server":
        method = __lsl_qbe_call0(__lsl_symbol("TLS_server_method"))
    elif role == "client":
        method = __lsl_qbe_call0(__lsl_symbol("TLS_client_method"))
    else:
        Error(ValueError: "TLS role must be \"client\" or \"server\"")
    end
    handle = __lsl_qbe_call1(__lsl_symbol("SSL_CTX_new"), method)
    if handle == 0:
        call fail("SSL_CTX_new")
    end
    call __lsl_qbe_call4(__lsl_symbol("SSL_CTX_ctrl"), handle, SSL_CTRL_SET_MIN_PROTO_VERSION, TLS1_2_VERSION, 0)
    call __lsl_qbe_call4(__lsl_symbol("SSL_CTX_ctrl"), handle, SSL_CTRL_SET_SESS_CACHE_MODE, 0, 0)
    call __lsl_qbe_call2(__lsl_symbol("SSL_CTX_set_options"), handle, SSL_OP_NO_TICKET)
    call __lsl_qbe_call3(__lsl_symbol("SSL_CTX_set_verify"), handle, SSL_VERIFY_NONE, 0)
    return handle
end

function context_free(handle):
    call __lsl_qbe_call1(__lsl_symbol("SSL_CTX_free"), ptr(handle))
    return 0
end

# Rozsah verzí: "1.2" nebo "1.3" (jen TLS 1.3: set_versions(ctx, "1.3", "1.3")).
function set_versions(handle, minimum, maximum):
    if __lsl_qbe_call4(__lsl_symbol("SSL_CTX_ctrl"), ptr(handle), SSL_CTRL_SET_MIN_PROTO_VERSION, version_number(minimum), 0) != 1:
        call fail("minimum TLS version")
    end
    if __lsl_qbe_call4(__lsl_symbol("SSL_CTX_ctrl"), ptr(handle), SSL_CTRL_SET_MAX_PROTO_VERSION, version_number(maximum), 0) != 1:
        call fail("maximum TLS version")
    end
    return 0
end

# Vlastní certifikát a soukromý klíč (ukazatele z modulu crypto).
function use_certificate(handle, certificate, key):
    if __lsl_qbe_icall2(__lsl_symbol("SSL_CTX_use_certificate"), ptr(handle), ptr(certificate)) != 1:
        call fail("SSL_CTX_use_certificate")
    end
    if __lsl_qbe_icall2(__lsl_symbol("SSL_CTX_use_PrivateKey"), ptr(handle), ptr(key)) != 1:
        call fail("SSL_CTX_use_PrivateKey")
    end
    if __lsl_qbe_icall1(__lsl_symbol("SSL_CTX_check_private_key"), ptr(handle)) != 1:
        call fail("certificate and key do not match")
    end
    return 0
end

# Totéž ze souborů PEM (řetězec certifikátů a klíč).
function use_certificate_files(handle, certificate_path, key_path):
    if __lsl_qbe_icall2(__lsl_symbol("SSL_CTX_use_certificate_chain_file"), ptr(handle), cstr(certificate_path)) != 1:
        call fail("certificate file " + String(certificate_path))
    end
    if __lsl_qbe_icall3(__lsl_symbol("SSL_CTX_use_PrivateKey_file"), ptr(handle), cstr(key_path), SSL_FILETYPE_PEM) != 1:
        call fail("key file " + String(key_path))
    end
    if __lsl_qbe_icall1(__lsl_symbol("SSL_CTX_check_private_key"), ptr(handle)) != 1:
        call fail("certificate and key do not match")
    end
    return 0
end

# Bez ověření protistrany (výchozí): aplikace si klíč připne sama po
# handshaku (peer_spki, peer_certificate_der). Server certifikát klienta
# nežádá.
function verify_none(handle):
    call __lsl_qbe_call3(__lsl_symbol("SSL_CTX_set_verify"), ptr(handle), SSL_VERIFY_NONE, 0)
    return 0
end

# Ověření řetězce systémovými CA (a jména serveru, předá-li client()
# server_name). Pro běžné HTTPS.
function verify_system(handle):
    if __lsl_qbe_icall1(__lsl_symbol("SSL_CTX_set_default_verify_paths"), ptr(handle)) != 1:
        call fail("SSL_CTX_set_default_verify_paths")
    end
    call __lsl_qbe_call3(__lsl_symbol("SSL_CTX_set_verify"), ptr(handle), SSL_VERIFY_PEER, 0)
    return 0
end

# Server žádá certifikát klienta (mTLS) a přijme jakýkoli, i podepsaný
# sebou samým; identitu ověří aplikace (peer_certificate_der). required:
# klient bez certifikátu handshake nedokončí.
function request_client_certificate(handle, required=False):
    mode = SSL_VERIFY_PEER
    if required:
        mode = mode | SSL_VERIFY_FAIL_IF_NO_PEER_CERT
    end
    call __lsl_qbe_call3(__lsl_symbol("SSL_CTX_set_verify"), ptr(handle), mode, __lsl_symbol("lsl_arch_return_one"))
    return 0
end

# Šifry TLS 1.3 v pořadí přednosti, např.
# "TLS_AES_256_GCM_SHA384:TLS_CHACHA20_POLY1305_SHA256:TLS_AES_128_GCM_SHA256".
function set_ciphersuites(handle, suites):
    if __lsl_qbe_icall2(__lsl_symbol("SSL_CTX_set_ciphersuites"), ptr(handle), cstr(suites)) != 1:
        call fail("SSL_CTX_set_ciphersuites")
    end
    return 0
end

# Šifry TLS 1.2 (syntaxe OpenSSL, např. "ECDHE+AESGCM:ECDHE+CHACHA20").
function set_cipher_list(handle, ciphers):
    if __lsl_qbe_icall2(__lsl_symbol("SSL_CTX_set_cipher_list"), ptr(handle), cstr(ciphers)) != 1:
        call fail("SSL_CTX_set_cipher_list")
    end
    return 0
end

# Server vybírá šifru podle svého pořadí (SSL_OP_CIPHER_SERVER_PREFERENCE).
function server_preference(handle, enabled=True):
    if enabled:
        call __lsl_qbe_call2(__lsl_symbol("SSL_CTX_set_options"), ptr(handle), SSL_OP_CIPHER_SERVER_PREFERENCE)
    else:
        call __lsl_qbe_call2(__lsl_symbol("SSL_CTX_clear_options"), ptr(handle), SSL_OP_CIPHER_SERVER_PREFERENCE)
    end
    return 0
end

# ALPN: List protokolů v pořadí přednosti (["luxdrop/1"], ["http/1.1"]).
# Klient je nabídne, server vybere první svůj, který klient nabídl; bez
# shody spojení pokračuje bez ALPN (alpn() vrátí "").
function set_alpn(handle, protocols):
    size = 0
    for protocol in protocols:
        length = __lsl_text_byte_length(protocol)
        if length == 0 or length > 255:
            Error(ValueError: "ALPN protocol must have 1 to 255 bytes")
        end
        size += length + 1
    end
    # Paměť C žije s kontextem (server ji čte při každém handshaku).
    wire = __lsl_qbe_call1(__lsl_symbol("malloc"), size + 1)
    position = 0
    for protocol in protocols:
        length = __lsl_text_byte_length(protocol)
        call __lsl_qbe_store8(wire + position, length)
        call __lsl_qbe_call3(__lsl_symbol("memcpy"), wire + position + 1, cstr(protocol), length)
        position += length + 1
    end
    if __lsl_qbe_icall3(__lsl_symbol("SSL_CTX_set_alpn_protos"), ptr(handle), wire, size) != 0:
        call fail("SSL_CTX_set_alpn_protos")
    end
    argument = __lsl_qbe_call1(__lsl_symbol("malloc"), 24)
    call __lsl_qbe_store64(argument, __lsl_symbol("SSL_select_next_proto"))
    call __lsl_qbe_store64(argument + 8, wire)
    call __lsl_qbe_store64(argument + 16, size)
    call __lsl_qbe_call3(__lsl_symbol("SSL_CTX_set_alpn_select_cb"), ptr(handle), __lsl_symbol("lsl_arch_alpn_select"), argument)
    return 0
end

# --- spojení ---

function connection(handle, sock):
    ssl = __lsl_qbe_call1(__lsl_symbol("SSL_new"), ptr(handle))
    if ssl == 0:
        call fail("SSL_new")
    end
    if __lsl_qbe_icall2(__lsl_symbol("SSL_set_fd"), ssl, ptr(sock)) != 1:
        call __lsl_qbe_call1(__lsl_symbol("SSL_free"), ssl)
        call fail("SSL_set_fd")
    end
    return ssl
end

# Klientská strana nad připojeným soketem; server_name pošle SNI a při
# verify_system kontroluje jméno v certifikátu. Handshake až handshake().
function client(handle, sock, server_name=""):
    ssl = connection(handle, sock)
    if server_name != "":
        call __lsl_qbe_call4(__lsl_symbol("SSL_ctrl"), ssl, SSL_CTRL_SET_TLSEXT_HOSTNAME, 0, cstr(server_name))
        if __lsl_qbe_icall2(__lsl_symbol("SSL_set1_host"), ssl, cstr(server_name)) != 1:
            call fail("SSL_set1_host")
        end
    end
    call __lsl_qbe_call1(__lsl_symbol("SSL_set_connect_state"), ssl)
    return ssl
end

# Serverová strana nad přijatým soketem (net.accept).
function server(handle, sock):
    ssl = connection(handle, sock)
    call __lsl_qbe_call1(__lsl_symbol("SSL_set_accept_state"), ssl)
    return ssl
end

# Soket spojení (pro net.wait a glib.fd_add).
function fd(ssl):
    return __lsl_qbe_icall1(__lsl_symbol("SSL_get_fd"), ptr(ssl))
end

# Výsledek operace OpenSSL: "done", "read"/"write" (čekat na soket),
# "closed" (protistrana poslala close_notify), jinak TLSError.
function outcome(ssl, status, action):
    if status > 0:
        return "done"
    end
    code = __lsl_qbe_icall2(__lsl_symbol("SSL_get_error"), ptr(ssl), ptr(status))
    if code == SSL_ERROR_WANT_READ:
        return "read"
    elif code == SSL_ERROR_WANT_WRITE:
        return "write"
    elif code == SSL_ERROR_ZERO_RETURN:
        return "closed"
    elif code == SSL_ERROR_SYSCALL:
        text = openssl_error()
        if text == "unknown OpenSSL error":
            if status == 0:
                Error(TLSError: action + ": connection closed by peer")
            end
            Error(TLSError: action + ": " + net.error_text(net.errno()))
        end
        Error(TLSError: action + ": " + text)
    end
    detail = openssl_error()
    verify = __lsl_qbe_call1(__lsl_symbol("SSL_get_verify_result"), ptr(ssl))
    if verify != 0:
        detail += " (certificate: " + from_c(__lsl_qbe_call1(__lsl_symbol("X509_verify_cert_error_string"), verify)) + ")"
    end
    Error(TLSError: action + ": " + detail)
end

function await_socket(ssl, state, timeout_ms, action):
    events = net.POLLIN
    if state == "write":
        events = net.POLLOUT
    end
    if net.wait(fd(ssl), events, timeout_ms) == 0:
        Error(TimeoutError: action + " timed out")
    end
    return 0
end

# Jeden krok handshaku na neblokujícím soketu: "done", nebo "read"/"write"
# (zavolat znovu, až bude soket připravený, např. z glib.fd_add).
function handshake_step(ssl):
    return outcome(ssl, __lsl_qbe_icall1(__lsl_symbol("SSL_do_handshake"), ptr(ssl)), "handshake")
end

# Celý handshake; limit platí pro každé čekání na soket.
function handshake(ssl, timeout_ms=30000):
    loop:
        state = handshake_step(ssl)
        if state == "done":
            return 0
        elif state == "closed":
            Error(TLSError: "handshake: connection closed by peer")
        end
        call await_socket(ssl, state, timeout_ms, "handshake")
    end
end

# Přijme nejvýš maximum bajtů aplikačních dat: ByteArray (prázdný = konec
# spojení). Nejsou-li data do timeout_ms, TimeoutError (0 = jen to, co je
# hned k dispozici, pro obsluhu z hlavní smyčky).
function read(ssl, maximum=65536, timeout_ms=-1):
    buffer = __lsl_byte_zeros(ptr(maximum))
    count = __lsl_byte_zeros(8)
    loop:
        status = __lsl_qbe_icall4(__lsl_symbol("SSL_read_ex"), ptr(ssl), bytes_data(buffer), ptr(maximum), bytes_data(count))
        state = outcome(ssl, status, "read")
        if state == "done":
            return bytes_from_c(bytes_data(buffer), __lsl_qbe_load64(bytes_data(count)))
        elif state == "closed":
            return __lsl_byte_zeros(0)
        end
        call await_socket(ssl, state, timeout_ms, "read")
    end
end

# Bajty už dešifrované v OpenSSL (čtou se bez čekání na soket).
function pending(ssl):
    return __lsl_qbe_icall1(__lsl_symbol("SSL_pending"), ptr(ssl))
end

# Zapíše všechna data; vrací počet bajtů.
function write(ssl, data, timeout_ms=-1):
    pointer = data_pointer(data)
    total = data_length(data)
    written = 0
    count = __lsl_byte_zeros(8)
    while written < total:
        status = __lsl_qbe_icall4(__lsl_symbol("SSL_write_ex"), ptr(ssl), pointer + written, total - written, bytes_data(count))
        state = outcome(ssl, status, "write")
        if state == "done":
            written += __lsl_qbe_load64(bytes_data(count))
        elif state == "closed":
            Error(TLSError: "write: connection closed by peer")
        else:
            call await_socket(ssl, state, timeout_ms, "write")
        end
    end
    return written
end

# Pošle close_notify (na odpověď protistrany nečeká).
function shutdown(ssl):
    call __lsl_qbe_icall1(__lsl_symbol("SSL_shutdown"), ptr(ssl))
    call __lsl_qbe_call0(__lsl_symbol("ERR_clear_error"))
    return 0
end

# Uvolní spojení a zavře jeho soket (close_socket=False ho nechá otevřený).
function close(ssl, close_socket=True):
    descriptor = fd(ssl)
    call __lsl_qbe_call1(__lsl_symbol("SSL_free"), ptr(ssl))
    if close_socket and descriptor >= 0:
        call __lsl_qbe_call1(__lsl_symbol("close"), descriptor)
    end
    return 0
end

# --- vyjednané parametry ---

# "TLSv1.3", "TLSv1.2"
function version(ssl):
    return from_c(__lsl_qbe_call1(__lsl_symbol("SSL_get_version"), ptr(ssl)))
end

# Šifra: TLS 1.3 "TLS_AES_256_GCM_SHA384", TLS 1.2 jméno OpenSSL
# ("ECDHE-ECDSA-AES256-GCM-SHA384"), "" před handshakem (jako Python ssl).
function cipher(ssl):
    current = __lsl_qbe_call1(__lsl_symbol("SSL_get_current_cipher"), ptr(ssl))
    if current == 0:
        return ""
    end
    return from_c(__lsl_qbe_call1(__lsl_symbol("SSL_CIPHER_get_name"), current))
end

# Vybraný protokol ALPN ("" bez ALPN).
function alpn(ssl):
    data = __lsl_byte_zeros(8)
    size = __lsl_byte_zeros(4)
    call __lsl_qbe_call3(__lsl_symbol("SSL_get0_alpn_selected"), ptr(ssl), bytes_data(data), bytes_data(size))
    length = __lsl_qbe_load32(bytes_data(size))
    if length == 0:
        return ""
    end
    bytes = bytes_from_c(__lsl_qbe_load64(bytes_data(data)), length)
    return __lsl_text_from_bytes(bytes, 0, length)
end

# Certifikát protistrany jako ukazatel X509 (crypto.certificate_free), nebo
# 0, když žádný neposlala.
function peer_certificate(ssl):
    return __lsl_qbe_call1(__lsl_symbol("SSL_get1_peer_certificate"), ptr(ssl))
end

# Certifikát protistrany v DER (otisk LocalSend = sha256 z něj); prázdný
# ByteArray bez certifikátu.
function peer_certificate_der(ssl):
    certificate = peer_certificate(ssl)
    if certificate == 0:
        return __lsl_byte_zeros(0)
    end
    length = __lsl_qbe_icall2(__lsl_symbol("i2d_X509"), certificate, 0)
    output = __lsl_byte_zeros(length)
    cell = __lsl_byte_zeros(8)
    call __lsl_qbe_store64(bytes_data(cell), bytes_data(output))
    call __lsl_qbe_icall2(__lsl_symbol("i2d_X509"), certificate, bytes_data(cell))
    call __lsl_qbe_call1(__lsl_symbol("X509_free"), certificate)
    return output
end

# SubjectPublicKeyInfo protistrany v DER (otisk LuxDrop = sha256 z něj);
# prázdný ByteArray bez certifikátu.
function peer_spki(ssl):
    certificate = peer_certificate(ssl)
    if certificate == 0:
        return __lsl_byte_zeros(0)
    end
    key = __lsl_qbe_call1(__lsl_symbol("X509_get_pubkey"), certificate)
    length = __lsl_qbe_icall2(__lsl_symbol("i2d_PUBKEY"), key, 0)
    output = __lsl_byte_zeros(length)
    cell = __lsl_byte_zeros(8)
    call __lsl_qbe_store64(bytes_data(cell), bytes_data(output))
    call __lsl_qbe_icall2(__lsl_symbol("i2d_PUBKEY"), key, bytes_data(cell))
    call __lsl_qbe_call1(__lsl_symbol("EVP_PKEY_free"), key)
    call __lsl_qbe_call1(__lsl_symbol("X509_free"), certificate)
    return output
end

# Výsledek ověření certifikátu (0 = v pořádku, jinak kód X509_V_ERR_*).
function verify_result(ssl):
    return __lsl_qbe_call1(__lsl_symbol("SSL_get_verify_result"), ptr(ssl))
end
