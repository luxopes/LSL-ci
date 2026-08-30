load fd
load httpserver

listener_box = IntArray()
port_box = IntArray()

function roundtrip_handler(request):
    return {"body": request["body"], "content_type": "application/octet-stream"}
end

function roundtrip_server_worker():
    call httpserver.serve_listener(listener_box[0], -1, roundtrip_handler, 1, False)
    return None
end

function garbage_handler(request):
    rows = []
    row = 0
    while row < 900:
        rows.append("<tr><td>row-" + String(row) + "</td><td>payload</td></tr>")
        row += 1
    end
    return {"body": "<table>" + "".join(rows) + "</table>", "content_type": "text/html; charset=utf-8"}
end

function memory_client_worker():
    separator = chr(13) + chr(10)
    index = 0
    while index < 30:
        client = __lsl_fd_socket(httpserver.AF_INET, httpserver.SOCK_STREAM)
        endpoint = httpserver.sockaddr_ipv4("127.0.0.1", port_box[0])
        check(__lsl_fd_connect(client, endpoint, len(endpoint)) >= 0, "connect")
        call httpserver.set_socket_timeout(client, httpserver.SO_RCVTIMEO, 5)
        call httpserver.set_socket_timeout(client, httpserver.SO_SNDTIMEO, 5)
        payload = httpserver.text_bytes("GET /m HTTP/1.1" + separator + "Host: x" + separator + separator)
        check(__lsl_fd_write(client, payload, len(payload)) >= 0, "write")
        received = httpserver.read_handle_limit(client, 500000)
        call fd.close(client)
        check(received["ok"], "read")
        print "CLI req", index
        index += 1
    end
    return None
end

function exchange_raw(payload, read_limit):
    client = __lsl_fd_socket(httpserver.AF_INET, httpserver.SOCK_STREAM)
    endpoint = httpserver.sockaddr_ipv4("127.0.0.1", port_box[0])
    check(__lsl_fd_connect(client, endpoint, len(endpoint)) >= 0, "connect big")
    call httpserver.set_socket_timeout(client, httpserver.SO_RCVTIMEO, 30)
    call httpserver.set_socket_timeout(client, httpserver.SO_SNDTIMEO, 30)
    check(__lsl_fd_write(client, payload, len(payload)) >= 0, "write big")
    received = httpserver.read_handle_limit(client, read_limit)
    call fd.close(client)
    check(received["ok"], "read big")
    return received["data"]
end

separator = chr(13) + chr(10)
roundtrip_listener = httpserver.listen_ipv4("127.0.0.1", 0, 16)
listener_box.append(roundtrip_listener)
port_box.append(httpserver.local_port(roundtrip_listener))
roundtrip_worker = thread_spawn(roundtrip_server_worker)

big_size = 9437184
big_header = httpserver.text_bytes("POST /big HTTP/1.1" + separator + "Host: x" + separator + "Content-Length: " + String(big_size) + separator + separator)
big_request = __lsl_byte_zeros(len(big_header) + big_size)
call __lsl_byte_copy(big_request, big_header, 0, 0, len(big_header))
fill_index = len(big_header)
while fill_index < len(big_request):
    big_request[fill_index] = 65
    fill_index += 1
end
big_response = exchange_raw(big_request, 10485760)
print "big done", len(big_response)
check(thread_join(roundtrip_worker) == 0, "join roundtrip")

memory_listener = httpserver.listen_ipv4("127.0.0.1", 0, 16)
listener_box[0] = memory_listener
port_box[0] = httpserver.local_port(memory_listener)
memory_worker = thread_spawn(memory_client_worker)
call httpserver.serve_listener(memory_listener, -1, garbage_handler, 30, False)
print "memory served"
check(thread_join(memory_worker) == 0, "join memory")
print "done"
