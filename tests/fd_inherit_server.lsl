descriptor = Int(arg(1))
buffer = ByteArray()
buffer.append(0)
print __lsl_fd_read(descriptor, buffer, 1)
