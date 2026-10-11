load http

# The verifier supplies an executable that writes arg(2) verbatim to stderr
# and exits with status 7, independently of curl/network availability.
output = capture(arg(1), [arg(2)])
result = http.transport_response(output)
print result["status"], result["ok"], result["text"] == arg(3)
