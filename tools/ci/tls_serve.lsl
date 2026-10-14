# Statický HTTPS server (nginx) pro test v CI: tls_serve KOŘEN PORT CERT KLÍČ
load httpserver

exit(httpserver.serve_static_tls(arg(1), "127.0.0.1", Int(arg(2)), arg(3), arg(4), 0))
