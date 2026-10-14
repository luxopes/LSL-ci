# Windows: HTTP server nad Winsock (ws2_32). Socket je synchronní (WSASocketW
# bez WSA_FLAG_OVERLAPPED) a nedědí se potomkům. Čtení a zápis jdou přes
# recv/send, časové limity SO_RCVTIMEO/SO_SNDTIMEO jsou v milisekundách
# a accept s limitem čeká přes WSAPoll (accept na Windows SO_RCVTIMEO
# nerespektuje). HTTPS obstará nginx pro Windows jako na Linuxu. Chyby mají
# hodnoty errno Linuxu jako zbytek runtime.
# Argumenty surových volání Win32 musí být Int.
load _platform as platform
load fd
load os
load time

# Linuxová čísla systémových volání veřejné fasády na Windows neexistují.
SYS_SOCKET = -1
SYS_FSTAT = -1
SYS_SENDTO = -1
SYS_ACCEPT4 = -1
SYS_BIND = -1
SYS_LISTEN = -1
SYS_GETSOCKNAME = -1
SYS_SETSOCKOPT = -1
SYS_OPENAT2 = -1

AF_INET = 2
SOCK_STREAM = 1
SOCK_CLOEXEC = 0
SOL_SOCKET = 65535
SO_REUSEADDR = 4
SO_LINGER = 128
SO_RCVTIMEO = 4102
SO_SNDTIMEO = 4101
MSG_NOSIGNAL = 0
# ~SO_REUSEADDR: výhradní port (SO_REUSEADDR na Windows dovolí převzetí portu).
SO_EXCLUSIVEADDRUSE = -5
WSA_FLAG_NO_HANDLE_INHERIT = 128
POLLRDNORM = 256

O_RDONLY = platform.O_RDONLY
O_NONBLOCK = platform.O_NONBLOCK
O_DIRECTORY = 65536
O_CLOEXEC = platform.O_CLOEXEC
O_NOFOLLOW = platform.O_NOFOLLOW
RESOLVE_NO_MAGICLINKS = 2
RESOLVE_NO_SYMLINKS = 4
RESOLVE_BENEATH = 8
S_IFMT = 61440
S_IFREG = 32768

SOCKADDR_IN_BYTES = 16
SOCKADDR_IN_PORT = 2
SOCKADDR_IN_ADDRESS = 4
SOCKET_TIMEOUT_SECONDS = 5
INVALID_SOCKET = -1

GENERIC_READ = 2147483648
FILE_SHARE_READ = 1
OPEN_EXISTING = 3
FILE_FLAG_BACKUP_SEMANTICS = 33554432
FILE_FLAG_OPEN_REPARSE_POINT = 2097152
FILE_ATTRIBUTE_DIRECTORY = 16
FILE_ATTRIBUTE_REPARSE_POINT = 1024
INVALID_ATTRIBUTES = 4294967295

function put_u32(buffer, offset, value):
    target = ByteArray(buffer)
    number = Int(value)
    target[offset] = number % 256
    target[offset + 1] = number // 256 % 256
    target[offset + 2] = number // 65536 % 256
    target[offset + 3] = number // 16777216 % 256
    return None
end

function get_u32(buffer, offset):
    source = ByteArray(buffer)
    return source[offset] + source[offset + 1] * 256 + source[offset + 2] * 65536 + source[offset + 3] * 16777216
end

function put_u64(buffer, offset, value):
    target = ByteArray(buffer)
    number = Int(value)
    for index in range(8):
        target[offset + index] = (number >> (index * 8)) & 255
    end
    return None
end

function data_address(buffer):
    return Int(__lsl_data_address(ByteArray(buffer)))
end

# Výsledek BOOL/int funkce Win32 (jen spodních 32 bitů rax), se znaménkem.
function int32(value):
    number = Int(value) & 4294967295
    if number >= 2147483648:
        number -= 4294967296
    end
    return number
end

# Chyba Winsock -> záporné errno Linuxu (časový limit = EAGAIN jako
# SO_RCVTIMEO na Linuxu).
function socket_error():
    code = int32(__lsl_qbe_call0(__lsl_symbol("WSAGetLastError")))
    if code == 10060 or code == 10035:
        return -11
    elif code == 10004:
        return -4
    elif code == 10054:
        return -104
    elif code == 10053 or code == 10058:
        return -32
    elif code == 10048:
        return -98
    elif code == 10022:
        return -22
    end
    return -5
end

# Winsock 2.2 (počítá se na proces, opakované volání nevadí).
function startup():
    data = __lsl_byte_zeros(512)
    if int32(__lsl_qbe_call2(__lsl_symbol("WSAStartup"), 514, data_address(data))) != 0:
        Error(ServerError: "WSAStartup failed")
    end
    return None
end

function socket_write(handle, payload):
    buffer = ByteArray(payload)
    socket = Int(handle)
    offset = 0
    remaining = len(buffer)
    while remaining > 0:
        part = min(remaining, 1073741824)
        result = int32(__lsl_qbe_call4(__lsl_symbol("send"), socket, data_address(buffer) + offset, part, 0))
        if result > 0:
            offset += result
            remaining -= result
        else:
            error = socket_error()
            if error != -4:
                return error
            end
        end
    end
    return 0
end

# Počet bajtů, 0 na konci spojení, nebo záporné errno (-11 časový limit).
function socket_read(handle, buffer, count):
    target = ByteArray(buffer)
    amount = min(Int(count), len(target))
    result = int32(__lsl_qbe_call4(__lsl_symbol("recv"), Int(handle), data_address(target), amount, 0))
    if result >= 0:
        return result
    end
    return socket_error()
end

function socket_close(handle):
    call __lsl_qbe_call1(__lsl_symbol("closesocket"), Int(handle))
    return None
end

function cstring(value):
    text = String(value)
    if len(text) == 0 or __lsl_text_byte_length(text) > 4095:
        Error(ServerError: "path must contain 1..4095 bytes")
    end
    result = __lsl_byte_zeros(__lsl_text_byte_length(text) + 1)
    index = 0
    while index < __lsl_text_byte_length(text):
        byte = __lsl_text_byte(text, index)
        if byte == 0:
            Error(ServerError: "path must not contain NUL")
        end
        result[index] = byte
        index += 1
    end
    return result
end

function ipv4_octets(address):
    text = String(address)
    parts = text.split(".")
    if len(parts) != 4:
        Error(ServerError: "bind address must be numeric IPv4")
    end
    result = IntArray()
    for part in parts:
        if len(part) == 0 or len(part) > 3:
            Error(ServerError: "bind address must be numeric IPv4")
        end
        for character in part:
            code = ord(character)
            if code < 48 or code > 57:
                Error(ServerError: "bind address must be numeric IPv4")
            end
        end
        octet = Int(part)
        if octet < 0 or octet > 255:
            Error(ServerError: "bind address octet is outside 0..255")
        end
        result.append(octet)
    end
    return result
end

# sockaddr_in Windows má stejné bajty jako Linux (rodina LE, port BE).
function sockaddr_ipv4(address, port):
    number = Int(port)
    if number < 0 or number > 65535:
        Error(ServerError: "port must be between 0 and 65535")
    end
    octets = ipv4_octets(address)
    result = __lsl_byte_zeros(SOCKADDR_IN_BYTES)
    result[0] = AF_INET
    result[1] = 0
    result[SOCKADDR_IN_PORT] = number // 256
    result[SOCKADDR_IN_PORT + 1] = number % 256
    index = 0
    while index < 4:
        result[SOCKADDR_IN_ADDRESS + index] = octets[index]
        index += 1
    end
    return result
end

# SO_REUSEADDR Linuxu odpovídá výchozímu chování Windows; místo něj se
# nastaví SO_EXCLUSIVEADDRUSE, aby port nemohl převzít jiný proces.
function set_socket_option(handle, option, value):
    name = Int(option)
    if name == SO_REUSEADDR:
        name = SO_EXCLUSIVEADDRUSE
    end
    payload = __lsl_byte_zeros(4)
    call put_u32(payload, 0, value)
    if int32(__lsl_qbe_call5(__lsl_symbol("setsockopt"), Int(handle), SOL_SOCKET, name, data_address(payload), 4)) != 0:
        return socket_error()
    end
    return 0
end

function set_socket_timeout(handle, option, seconds):
    payload = __lsl_byte_zeros(4)
    call put_u32(payload, 0, Int(seconds) * 1000)
    if int32(__lsl_qbe_call5(__lsl_symbol("setsockopt"), Int(handle), SOL_SOCKET, Int(option), data_address(payload), 4)) != 0:
        return socket_error()
    end
    return 0
end

# Časový limit SO_RCVTIMEO socketu v ms (0 = bez limitu).
function receive_timeout(handle):
    payload = __lsl_byte_zeros(4)
    size = __lsl_byte_zeros(4)
    call put_u32(size, 0, 4)
    if int32(__lsl_qbe_call5(__lsl_symbol("getsockopt"), Int(handle), SOL_SOCKET, SO_RCVTIMEO, data_address(payload), data_address(size))) != 0:
        return 0
    end
    return get_u32(payload, 0)
end

function listen_ipv4(address, port, backlog):
    endpoint = sockaddr_ipv4(address, port)
    call startup()
    handle = Int(__lsl_qbe_call6(__lsl_symbol("WSASocketW"), AF_INET, SOCK_STREAM, 6, 0, 0, WSA_FLAG_NO_HANDLE_INHERIT))
    if handle == INVALID_SOCKET:
        Error(ServerError: "socket failed (" + String(socket_error()) + ")")
    end
    if set_socket_option(handle, SO_REUSEADDR, 1) < 0:
        call socket_close(handle)
        Error(ServerError: "cannot set SO_REUSEADDR")
    end
    if int32(__lsl_qbe_call3(__lsl_symbol("bind"), handle, data_address(endpoint), len(endpoint))) != 0:
        call socket_close(handle)
        Error(ServerError: "cannot bind " + String(address) + ":" + String(port))
    end
    queue = Int(backlog)
    if queue < 1:
        queue = 1
    elif queue > 4096:
        queue = 4096
    end
    if int32(__lsl_qbe_call2(__lsl_symbol("listen"), handle, queue)) != 0:
        call socket_close(handle)
        Error(ServerError: "listen failed")
    end
    return handle
end

function local_port(listener):
    endpoint = __lsl_byte_zeros(SOCKADDR_IN_BYTES)
    endpoint_length = __lsl_byte_zeros(4)
    call put_u32(endpoint_length, 0, SOCKADDR_IN_BYTES)
    result = int32(__lsl_qbe_call3(__lsl_symbol("getsockname"), Int(listener), data_address(endpoint), data_address(endpoint_length)))
    if result != 0 or endpoint[0] != AF_INET:
        Error(ServerError: "getsockname failed")
    end
    return endpoint[SOCKADDR_IN_PORT] * 256 + endpoint[SOCKADDR_IN_PORT + 1]
end

# Accept s limitem SO_RCVTIMEO naslouchajícího socketu (-11 po vypršení),
# klient dostane limity čtení a zápisu.
function accept_client(listener):
    socket = Int(listener)
    timeout = receive_timeout(socket)
    if timeout > 0:
        # WSAPOLLFD: +0 SOCKET, +8 events, +10 revents.
        poll = __lsl_byte_zeros(16)
        call put_u64(poll, 0, socket)
        poll[8] = POLLRDNORM % 256
        poll[9] = POLLRDNORM // 256
        ready = int32(__lsl_qbe_call3(__lsl_symbol("WSAPoll"), data_address(poll), 1, timeout))
        if ready == 0:
            return -11
        elif ready < 0:
            return socket_error()
        end
    end
    client = Int(__lsl_qbe_call3(__lsl_symbol("accept"), socket, 0, 0))
    if client == INVALID_SOCKET:
        return socket_error()
    end
    receive = set_socket_timeout(client, SO_RCVTIMEO, SOCKET_TIMEOUT_SECONDS)
    send = set_socket_timeout(client, SO_SNDTIMEO, SOCKET_TIMEOUT_SECONDS)
    if receive < 0 or send < 0:
        call socket_close(client)
        return -22
    end
    return client
end

# UTF-8 text -> UTF-16 s NUL (ByteArray) pro funkce ...W.
function wide(text):
    value = String(text)
    source = cstring(value)
    result = __lsl_byte_zeros(len(source) * 2 + 2)
    count = int32(__lsl_qbe_call6(__lsl_symbol("MultiByteToWideChar"), 65001, 8, data_address(source), -1, data_address(result), len(source) + 1))
    if count <= 0:
        Error(ServerError: "path is not valid UTF-8")
    end
    return result
end

# Skutečná cesta otevřeného souboru (odkazy a junction rozřešené, tvar
# \\?\C:\...) v UTF-8, malými písmeny ASCII (Windows je nerozlišuje).
function final_path(handle):
    wide_buffer = __lsl_byte_zeros(65536)
    count = int32(__lsl_qbe_call4(__lsl_symbol("GetFinalPathNameByHandleW"), Int(handle), data_address(wide_buffer), 32767, 0))
    if count <= 0 or count >= 32767:
        return ""
    end
    text = __lsl_byte_zeros(count * 3 + 1)
    size = int32(__lsl_qbe_call8(__lsl_symbol("WideCharToMultiByte"), 65001, 0, data_address(wide_buffer), count, data_address(text), len(text), 0, 0))
    if size <= 0:
        return ""
    end
    return __lsl_text_from_bytes(text, 0, size).lower()
end

function attributes(path):
    return Int(__lsl_qbe_call1(__lsl_symbol("GetFileAttributesW"), data_address(wide(path)))) & 4294967295
end

# Kořen webu jako HANDLE adresáře (drží ho otevřený, nejde smazat ani
# přejmenovat): [zadaná cesta, z níž open_static skládá cesty pod kořenem,
# skutečná cesta kořene].
ROOT_PATHS = {}

function open_root(path):
    root = String(path)
    if attributes(root) == INVALID_ATTRIBUTES or attributes(root) & FILE_ATTRIBUTE_DIRECTORY == 0:
        Error(ServerError: "cannot open server root: " + root)
    end
    handle = Int(__lsl_qbe_call7(__lsl_symbol("CreateFileW"), data_address(wide(root)), GENERIC_READ, FILE_SHARE_READ, 0, OPEN_EXISTING, FILE_FLAG_BACKUP_SEMANTICS, 0))
    if handle == -1:
        Error(ServerError: "cannot open server root: " + root)
    end
    while root.endswith("\\") or root.endswith("/"):
        root = root[0:len(root) - 1]
    end
    resolved = final_path(handle)
    if resolved == "":
        call fd.close(handle)
        Error(ServerError: "cannot open server root: " + root)
    end
    ROOT_PATHS[handle] = [root, resolved]
    return handle
end

# Jméno, které Windows nesmí dostat jako součást cesty pod kořenem: zařízení
# (CON, NUL, COM1…), alternativní datové proudy (:), tečky a mezery na konci
# (Windows je zahazuje), oddělovače a řídicí znaky.
function unsafe_component(name):
    if name == "" or name == "." or name == ".." or name.endswith(".") or name.endswith(" "):
        return True
    end
    for character in name:
        code = ord(character)
        if code < 32 or character == ":" or character == "\\" or character == "*" or character == "?" or character == "\"" or character == "<" or character == ">" or character == "|":
            return True
        end
    end
    stem = name.split(".")[0].upper().strip()
    if stem in ["CON", "PRN", "AUX", "NUL", "CONIN$", "CONOUT$"]:
        return True
    end
    if len(stem) == 4 and (stem.startswith("COM") or stem.startswith("LPT")) and ord(stem[3]) >= 48 and ord(stem[3]) <= 57:
        return True
    end
    return False
end

# Soubor pod kořenem bez reparse pointů (symbolických odkazů, junction)
# v cestě, jen obyčejný soubor: HANDLE, nebo záporné errno.
function open_static(root_handle, relative_path):
    call cstring(relative_path)
    root = ROOT_PATHS.get(Int(root_handle), None)
    if root == None:
        return -9
    end
    path = String(root[0])
    for component in String(relative_path).split("/"):
        if unsafe_component(component):
            return -22
        end
        path = path + "\\" + component
        found = attributes(path)
        if found == INVALID_ATTRIBUTES:
            return -2
        elif found & FILE_ATTRIBUTE_REPARSE_POINT != 0:
            return -40
        end
    end
    if attributes(path) & FILE_ATTRIBUTE_DIRECTORY != 0:
        return -22
    end
    handle = Int(__lsl_qbe_call7(__lsl_symbol("CreateFileW"), data_address(wide(path)), GENERIC_READ, FILE_SHARE_READ, 0, OPEN_EXISTING, FILE_FLAG_OPEN_REPARSE_POINT, 0))
    if handle == -1:
        return -13
    end
    # Soubor musí opravdu ležet pod kořenem: odkaz, který se jako reparse
    # point neohlásil (unixový odkaz pod wine) nebo vznikl po kontrole cesty.
    if not final_path(handle).startswith(String(root[1]) + "\\"):
        call fd.close(handle)
        return -40
    end
    # Druh otevřeného souboru znovu podle handle (cesta se mohla změnit).
    information = __lsl_byte_zeros(56)
    if int32(__lsl_qbe_call2(__lsl_symbol("GetFileInformationByHandle"), handle, data_address(information))) == 0 or get_u32(information, 0) & (FILE_ATTRIBUTE_DIRECTORY + FILE_ATTRIBUTE_REPARSE_POINT) != 0:
        call fd.close(handle)
        return -22
    end
    return handle
end

function system_tool(primary, fallback, label):
    if exists(primary):
        return primary
    elif exists(fallback):
        return fallback
    end
    Error(ServerError: "trusted " + String(label) + " executable is required")
end

# Soukromý pracovní adresář nginx v %TEMP% (cesta s lomítky pro nginx).
function runtime_directory():
    base = __lsl_getenv("TEMP")
    if base == None or String(base) == "":
        base = "C:\\Windows\\Temp"
    end
    base = forward_slashes(String(base))
    process = String(Int(__lsl_qbe_call0(__lsl_symbol("GetCurrentProcessId"))) & 4294967295)
    attempt = 0
    directory = base + "/lsl-https-" + process
    while __lsl_mkdir_private(directory) != 0:
        attempt += 1
        if attempt > 100:
            Error(ServerError: "cannot create a private HTTPS runtime directory")
        end
        directory = base + "/lsl-https-" + process + "-" + String(attempt)
    end
    return directory
end

function forward_slashes(path):
    result = ""
    for character in String(path):
        if character == "\\":
            result += "/"
        else:
            result += character
        end
    end
    return result
end

# Skutečná cesta existujícího souboru nebo adresáře pro nginx (C:/...).
function canonical_path(path, label):
    handle = Int(__lsl_qbe_call7(__lsl_symbol("CreateFileW"), data_address(wide(String(path))), 0, FILE_SHARE_READ + 2 + 4, 0, OPEN_EXISTING, FILE_FLAG_BACKUP_SEMANTICS, 0))
    if handle == -1:
        Error(ServerError: "cannot resolve " + String(label) + ": " + String(path))
    end
    wide_buffer = __lsl_byte_zeros(65536)
    count = int32(__lsl_qbe_call4(__lsl_symbol("GetFinalPathNameByHandleW"), handle, data_address(wide_buffer), 32767, 0))
    call fd.close(handle)
    if count <= 0 or count >= 32767:
        Error(ServerError: "cannot resolve " + String(label) + ": " + String(path))
    end
    text = __lsl_byte_zeros(count * 3 + 1)
    size = int32(__lsl_qbe_call8(__lsl_symbol("WideCharToMultiByte"), 65001, 0, data_address(wide_buffer), count, data_address(text), len(text), 0, 0))
    result = __lsl_text_from_bytes(text, 0, size)
    if result.startswith("\\\\?\\"):
        result = result[4:len(result)]
    end
    result = forward_slashes(result)
    if len(result) == 0 or chr(10) in result or chr(13) in result or "\"" in result:
        Error(ServerError: String(label) + " has an unsupported path")
    end
    return result
end

function nginx_quote(value):
    result = "\""
    for character in String(value):
        if character == chr(92) or character == "\"" or character == "$":
            result += chr(92)
        end
        result += character
    end
    return result + "\""
end

# nginx pro Windows: C:\\nginx, Program Files, nebo PATH (shim Chocolatey).
function nginx_tool():
    roots = ["C:\\nginx"]
    program_files = __lsl_getenv("ProgramFiles")
    if program_files != None:
        roots.append(String(program_files) + "\\nginx")
    end
    for root in roots:
        if exists(root + "\\nginx.exe"):
            return root + "\\nginx.exe"
        end
    end
    chocolatey = chocolatey_nginx()
    if chocolatey != None:
        return chocolatey
    end
    found = os.which("nginx")
    if found == None:
        Error(ServerError: "nginx for Windows is required (C:\\nginx, Program Files, Chocolatey or PATH)")
    end
    return String(found)
end

# Balíček Chocolatey dá nginx do %ChocolateyToolsLocation%\nginx-<verze>
# (výchozí C:\tools) bez záznamu v PATH; vybere se nejvyšší verze.
function chocolatey_nginx():
    tools = __lsl_getenv("ChocolateyToolsLocation")
    if tools == None or String(tools) == "":
        tools = "C:\\tools"
    end
    root = String(tools)
    found = __lsl_byte_zeros(600)
    handle = Int(__lsl_qbe_call2(__lsl_symbol("FindFirstFileW"), data_address(wide(root + "\\nginx-*")), data_address(found)))
    if handle == -1:
        return None
    end
    best = ""
    loop:
        # WIN32_FIND_DATAW: +0 atributy, +44 jméno (UTF-16).
        name = ""
        index = 44
        while found[index] != 0 or found[index + 1] != 0:
            name += chr(found[index] + found[index + 1] * 256)
            index += 2
        end
        if get_u32(found, 0) & FILE_ATTRIBUTE_DIRECTORY != 0 and exists(root + "\\" + name + "\\nginx.exe") and newer_version(name, best):
            best = name
        end
        if int32(__lsl_qbe_call2(__lsl_symbol("FindNextFileW"), handle, data_address(found))) == 0:
            break
        end
    end
    call __lsl_qbe_call1(__lsl_symbol("FindClose"), handle)
    if best == "":
        return None
    end
    return root + "\\" + best + "\\nginx.exe"
end

# Porovná nginx-A.B.C podle číselných částí verze.
function newer_version(candidate, current):
    if current == "":
        return True
    end
    left = candidate[6:len(candidate)].split(".")
    right = current[6:len(current)].split(".")
    index = 0
    while index < len(left) and index < len(right):
        a = digits_value(left[index])
        b = digits_value(right[index])
        if a != b:
            return a > b
        end
        index += 1
    end
    return len(left) > len(right)
end

function digits_value(text):
    value = 0
    for character in text:
        code = ord(character)
        if code < 48 or code > 57:
            return value
        end
        value = value * 10 + code - 48
    end
    return value
end

function serve_static_tls(root, address, port, certificate, private_key, maximum_requests):
    if maximum_requests != 0:
        Error(ServerError: "HTTPS mode does not support --max-requests")
    end
    number = port
    if number < 1 or number > 65535:
        Error(ServerError: "HTTPS port must be between 1 and 65535")
    end
    # Validate the address using the same strict numeric parser as native HTTP.
    call ipv4_octets(address)
    root_path = canonical_path(root, "server root")
    certificate_path = canonical_path(certificate, "TLS certificate")
    key_path = canonical_path(private_key, "TLS private key")
    directory = runtime_directory()
    config_path = directory + "/nginx.conf"
    config = "worker_processes 1;" + chr(10)
    config += "master_process off;" + chr(10)
    config += "daemon off;" + chr(10)
    config += "pid " + nginx_quote(directory + "/nginx.pid") + ";" + chr(10)
    config += "error_log stderr warn;" + chr(10)
    config += "events { worker_connections 128; }" + chr(10)
    config += "http {" + chr(10)
    config += "  access_log off;" + chr(10)
    config += "  server_tokens off;" + chr(10)
    config += "  client_body_temp_path " + nginx_quote(directory + "/client-body") + ";" + chr(10)
    config += "  proxy_temp_path " + nginx_quote(directory + "/proxy") + ";" + chr(10)
    config += "  fastcgi_temp_path " + nginx_quote(directory + "/fastcgi") + ";" + chr(10)
    config += "  uwsgi_temp_path " + nginx_quote(directory + "/uwsgi") + ";" + chr(10)
    config += "  scgi_temp_path " + nginx_quote(directory + "/scgi") + ";" + chr(10)
    config += "  sendfile on;" + chr(10)
    config += "  client_header_timeout 5s;" + chr(10)
    config += "  client_body_timeout 5s;" + chr(10)
    config += "  send_timeout 5s;" + chr(10)
    config += "  keepalive_timeout 0;" + chr(10)
    config += "  client_max_body_size 1k;" + chr(10)
    config += "  large_client_header_buffers 2 8k;" + chr(10)
    config += "  default_type application/octet-stream;" + chr(10)
    config += "  types { text/html html htm; text/css css; text/javascript js; application/json json; text/plain txt md; image/svg+xml svg; image/png png; image/jpeg jpg jpeg; image/gif gif; application/wasm wasm; }" + chr(10)
    config += "  server {" + chr(10)
    config += "    listen " + String(address) + ":" + String(number) + " ssl;" + chr(10)
    config += "    server_name _;" + chr(10)
    config += "    ssl_certificate " + nginx_quote(certificate_path) + ";" + chr(10)
    config += "    ssl_certificate_key " + nginx_quote(key_path) + ";" + chr(10)
    config += "    ssl_protocols TLSv1.2 TLSv1.3;" + chr(10)
    config += "    ssl_session_tickets off;" + chr(10)
    config += "    root " + nginx_quote(root_path) + ";" + chr(10)
    config += "    autoindex off;" + chr(10)
    config += "    disable_symlinks on from=$document_root;" + chr(10)
    config += "    add_header X-Content-Type-Options nosniff always;" + chr(10)
    config += "    add_header Referrer-Policy no-referrer always;" + chr(10)
    config += "    if ($request_method !~ ^(GET|HEAD)$) { return 405; }" + chr(10)
    config += "    location / { try_files $uri =404; }" + chr(10)
    config += "  }" + chr(10)
    config += "}" + chr(10)
    call writefile(config_path, config)
    nginx = nginx_tool()
    print "LSL HTTPS server listening on https://" + String(address) + ":" + String(number) + "/"
    # Winsock v nginx potřebuje prostředí (SystemRoot): run, ne run_clean.
    print "DEBUG config", config_path, exists(config_path), len(readfile(config_path)), nginx
    status = run(nginx, ["-p", directory + "/", "-c", config_path])
    print "DEBUG status", status, exists(config_path)
    call unlink(directory + "/nginx.pid")
    call unlink(config_path)
    call rmdir(directory + "/client-body")
    call rmdir(directory + "/proxy")
    call rmdir(directory + "/fastcgi")
    call rmdir(directory + "/uwsgi")
    call rmdir(directory + "/scgi")
    call rmdir(directory)
    return status
end

function interrupted(result):
    return result == -4
end
