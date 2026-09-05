// Included inside the worker namespace. ABI 2 is a single-client, framed Unix
// stream. Device pointers never cross the process boundary; handles are scoped
// to this connection and all allocations are released on EOF or protocol error.
constexpr std::size_t kMaxSessionElements = 32000000;
constexpr std::size_t kMaxSessionBuffers = 256;
constexpr std::size_t kMaxSessionHeader = 4096;

__global__ void elementwise_kernel(const double* a, const double* b, double* out,
                                    std::size_t count, int operation, double alpha) {
    const std::size_t i = static_cast<std::size_t>(blockIdx.x) * blockDim.x + threadIdx.x;
    if (i >= count) return;
    const double x = a == nullptr ? 0.0 : a[i];
    switch (operation) {
    case 0: out[i] = x + b[i]; break;
    case 1: out[i] = x - b[i]; break;
    case 2: out[i] = x * b[i]; break;
    case 3: out[i] = x / b[i]; break;
    case 4: out[i] = x * alpha; break;
    case 5: out[i] = x < 0.0 ? 0.0 : x; break;
    case 6: out[i] = alpha; break;
    }
}

__global__ void transpose_kernel(const double* a, double* out, int rows, int columns) {
    const std::size_t i = static_cast<std::size_t>(blockIdx.x) * blockDim.x + threadIdx.x;
    if (i < static_cast<std::size_t>(rows) * columns) {
        out[(i % columns) * rows + i / columns] = a[i];
    }
}

class SessionBuffer {
public:
    const std::size_t count;
    DeviceBuffer<double> memory;
    explicit SessionBuffer(std::size_t size) : count(size), memory(size) {}
};

class SessionBuffers {
    std::map<int, std::unique_ptr<SessionBuffer>> values_;
    std::size_t elements_ = 0;
    int next_ = 1;
public:
    int allocate(std::size_t count) {
        if (count > kMaxElements || count > kMaxSessionElements - elements_ ||
            values_.size() >= kMaxSessionBuffers || next_ == std::numeric_limits<int>::max()) {
            throw WorkerError("CUDA session allocation limit exceeded");
        }
        auto buffer = std::make_unique<SessionBuffer>(count);
        const int id = next_++;
        values_.emplace(id, std::move(buffer));
        elements_ += count;
        return id;
    }
    SessionBuffer& get(int id) {
        auto found = values_.find(id);
        if (found == values_.end()) throw WorkerError("invalid or freed CUDA buffer handle");
        return *found->second;
    }
    void free(int id) {
        elements_ -= get(id).count;
        values_.erase(id);
    }
    std::size_t elements() const { return elements_; }
    std::size_t size() const { return values_.size(); }
};

bool socket_read(int socket, void* data, std::size_t size, bool allow_eof = false) {
    auto* bytes = static_cast<char*>(data);
    std::size_t offset = 0;
    while (offset < size) {
        const ssize_t received = recv(socket, bytes + offset, size - offset, 0);
        if (received < 0 && errno == EINTR) continue;
        if (received == 0 && offset == 0 && allow_eof) return false;
        if (received <= 0) throw WorkerError("CUDA session stream ended inside a frame");
        offset += static_cast<std::size_t>(received);
    }
    return true;
}

void socket_write(int socket, const void* data, std::size_t size) {
    auto* bytes = static_cast<const char*>(data);
    std::size_t offset = 0;
    while (offset < size) {
        const ssize_t sent = send(socket, bytes + offset, size - offset, MSG_NOSIGNAL);
        if (sent < 0 && errno == EINTR) continue;
        if (sent <= 0) throw WorkerError("cannot write CUDA session frame");
        offset += static_cast<std::size_t>(sent);
    }
}

void session_response(int socket, const std::string& fields,
                       const std::vector<double>& payload = {}) {
    const std::string header = "{\"abi\":2,\"bytes\":" +
        std::to_string(payload.size() * sizeof(double)) + "," + fields + "}";
    const std::uint32_t size = static_cast<std::uint32_t>(header.size());
    socket_write(socket, &size, sizeof(size));
    socket_write(socket, header.data(), header.size());
    socket_write(socket, payload.data(), payload.size() * sizeof(double));
}

void buffer_response(int socket, int id, std::size_t count) {
    session_response(socket, "\"ok\":true,\"id\":" + std::to_string(id) +
        ",\"count\":" + std::to_string(count));
}

void session_loop(int socket) {
    SessionBuffers buffers;
    bool verified = false;
    while (true) {
        // Waiting between commands does not expire a live session. Once the
        // first byte arrives, bound the entire request, kernel and response.
        unsigned char first = 0;
        if (!socket_read(socket, &first, 1, true)) return;
        alarm(120);
        std::uint32_t header_size = first;
        socket_read(socket, reinterpret_cast<char*>(&header_size) + 1, 3);
        if (header_size == 0 || header_size > kMaxSessionHeader) {
            throw WorkerError("invalid CUDA session header size");
        }
        std::string header(header_size, '\0');
        socket_read(socket, header.data(), header.size());
        if (header.find('\0') != std::string::npos || integer_value(header, "abi") != 2) {
            throw WorkerError("CUDA session ABI mismatch");
        }
        const std::size_t byte_count = integer_value(header, "bytes");
        if (byte_count > kMaxElements * sizeof(double) || byte_count % sizeof(double) != 0) {
            throw WorkerError("invalid CUDA session payload size");
        }
        std::vector<double> payload(byte_count / sizeof(double));
        socket_read(socket, payload.data(), byte_count);
        try {
            const std::string operation = string_value(header, "operation");
            if (operation != "upload" && operation != "fill" && operation != "scale" &&
                operation != "axpy" && byte_count != 0) {
                throw WorkerError("unexpected CUDA session payload");
            }
            if (!verified) {
                selected_device();
                launch_probe();
                verified = true;
            }
            if (operation == "info") {
                session_response(socket, "\"ok\":true,\"device\":" +
                    std::to_string(selected_device()) + ",\"buffers\":" +
                    std::to_string(buffers.size()) + ",\"elements\":" +
                    std::to_string(buffers.elements()) + ",\"pid\":" + std::to_string(getpid()));
            } else if (operation == "close") {
                session_response(socket, "\"ok\":true");
                return;
            } else if (operation == "synchronize") {
                cuda_check(cudaDeviceSynchronize(), "session synchronize");
                session_response(socket, "\"ok\":true");
            } else if (operation == "upload" || operation == "zeros") {
                const std::size_t count = integer_value(header, "count");
                if (operation == "upload" && payload.size() != count) {
                    throw WorkerError("CUDA upload count differs from payload");
                }
                const int id = buffers.allocate(count);
                try {
                    if (count != 0) {
                        if (operation == "upload") {
                            cuda_check(cudaMemcpy(buffers.get(id).memory.get(), payload.data(),
                                byte_count, cudaMemcpyHostToDevice), "session upload");
                        } else {
                            cuda_check(cudaMemset(buffers.get(id).memory.get(), 0,
                                count * sizeof(double)), "session zeros");
                        }
                    }
                    cuda_check(cudaDeviceSynchronize(), "session allocation synchronize");
                } catch (...) { buffers.free(id); throw; }
                buffer_response(socket, id, count);
            } else {
                const int id = static_cast<int>(integer_value(header, "id"));
                auto& a = buffers.get(id);
                if (operation == "free") {
                    buffers.free(id);
                    session_response(socket, "\"ok\":true");
                } else if (operation == "download") {
                    std::vector<double> result(a.count);
                    if (a.count) cuda_check(cudaMemcpy(result.data(), a.memory.get(),
                        a.count * sizeof(double), cudaMemcpyDeviceToHost), "session download");
                    session_response(socket, "\"ok\":true", result);
                } else if (operation == "sum" || operation == "dot") {
                    SessionBuffer* b = nullptr;
                    if (operation == "dot") {
                        b = &buffers.get(static_cast<int>(integer_value(header, "other")));
                        if (b->count != a.count) throw WorkerError("CUDA dot shape mismatch");
                    }
                    session_response(socket, "\"ok\":true", {gpu_reduce_device(a.memory.get(),
                        b == nullptr ? nullptr : b->memory.get(), a.count)});
                } else {
                    const bool binary = operation == "add" || operation == "subtract" ||
                        operation == "multiply" || operation == "divide" ||
                        operation == "axpy" || operation == "matmul";
                    SessionBuffer* b = binary ? &buffers.get(static_cast<int>(integer_value(header, "other"))) : nullptr;
                    if (binary && operation != "matmul" && b->count != a.count) {
                        throw WorkerError("CUDA elementwise shape mismatch");
                    }
                    double alpha = 0.0;
                    if (operation == "scale" || operation == "fill" || operation == "axpy") {
                        if (payload.size() != 1) throw WorkerError("CUDA scalar payload must be one Float64");
                        alpha = payload[0];
                    }
                    std::size_t count = a.count;
                    int rows = 0, inner = 0, columns = 0, opcode = -1;
                    if (operation == "matmul" || operation == "transpose") {
                        rows = static_cast<int>(integer_value(header, "m"));
                        columns = static_cast<int>(integer_value(header, "n"));
                        inner = operation == "matmul" ? static_cast<int>(integer_value(header, "k")) : columns;
                        if (rows > static_cast<int>(kMaxElements) || inner > static_cast<int>(kMaxElements) ||
                            columns > static_cast<int>(kMaxElements)) throw WorkerError("CUDA dimension limit exceeded");
                        count = checked_product(rows, columns, "session matrix");
                        if (a.count != checked_product(rows, inner, "session left") ||
                            (b && b->count != checked_product(inner, columns, "session right"))) {
                            throw WorkerError("CUDA matrix shape mismatch");
                        }
                    } else if (operation == "add") opcode = 0;
                    else if (operation == "subtract") opcode = 1;
                    else if (operation == "multiply") opcode = 2;
                    else if (operation == "divide") opcode = 3;
                    else if (operation == "scale") opcode = 4;
                    else if (operation == "relu") opcode = 5;
                    else if (operation == "fill") opcode = 6;
                    else if (operation != "axpy") throw WorkerError("unsupported CUDA session operation");
                    const bool inplace = operation == "axpy" || operation == "fill";
                    const int output_id = inplace ? id : buffers.allocate(count);
                    try {
                        double* out = buffers.get(output_id).memory.get();
                        if (count != 0) {
                            const unsigned blocks = static_cast<unsigned>((count + kThreads - 1) / kThreads);
                            if (operation == "axpy") {
                                axpy_kernel<<<blocks, kThreads>>>(alpha, b->memory.get(), out, count);
                            } else if (operation == "matmul") {
                                const unsigned tiles = ((columns + kTile - 1) / kTile) * ((rows + kTile - 1) / kTile);
                                matmul_kernel<<<tiles, dim3(kTile, kTile)>>>(a.memory.get(), b->memory.get(), out, rows, inner, columns);
                            } else if (operation == "transpose") {
                                transpose_kernel<<<blocks, kThreads>>>(a.memory.get(), out, rows, columns);
                            } else {
                                elementwise_kernel<<<blocks, kThreads>>>(a.memory.get(), b ? b->memory.get() : nullptr, out, count, opcode, alpha);
                            }
                            cuda_check(cudaGetLastError(), "session kernel launch");
                            cuda_check(cudaDeviceSynchronize(), "session kernel synchronize");
                        }
                    } catch (...) { if (!inplace) buffers.free(output_id); throw; }
                    buffer_response(socket, output_id, count);
                }
            }
        } catch (const std::exception& error) {
            session_response(socket, "\"ok\":false,\"error\":\"" + json_escape(error.what()) + "\"");
        }
        alarm(0);
    }
}

void start_session() {
    char directory[] = "/tmp/lsl-cuda-XXXXXX";
    if (mkdtemp(directory) == nullptr) throw WorkerError("cannot create CUDA session directory");
    const std::string path = std::string(directory) + "/socket";
    int listener = socket(AF_UNIX, SOCK_STREAM | SOCK_CLOEXEC, 0);
    auto cleanup = [&]() { if (listener >= 0) close(listener); unlink(path.c_str()); rmdir(directory); };
    sockaddr_un address{};
    address.sun_family = AF_UNIX;
    std::memcpy(address.sun_path, path.c_str(), path.size() + 1);
    if (listener < 0 || bind(listener, reinterpret_cast<sockaddr*>(&address), sizeof(address)) != 0 || listen(listener, 1) != 0) {
        cleanup();
        throw WorkerError("cannot bind CUDA session socket");
    }
    // No CUDA calls before fork. The grandchild owns the context; the starter
    // remains a short, shell-free captured process and reaps its direct child.
    const pid_t child = fork();
    if (child < 0) { cleanup(); throw WorkerError("cannot fork CUDA session"); }
    if (child == 0) {
        const pid_t daemon = fork();
        if (daemon < 0) _exit(2);
        if (daemon > 0) _exit(0);
        int null = open("/dev/null", O_RDWR);
        if (null < 0) { cleanup(); _exit(2); }
        for (int descriptor = 0; descriptor < 3; ++descriptor) {
            if (dup2(null, descriptor) < 0) { cleanup(); _exit(2); }
        }
        if (null > 2) close(null);
        pollfd pending{listener, POLLIN, 0};
        int ready;
        do { ready = poll(&pending, 1, 10000); } while (ready < 0 && errno == EINTR);
        int client = ready > 0 ? accept4(listener, nullptr, nullptr, SOCK_CLOEXEC) : -1;
        cleanup();
        if (client >= 0) {
            ucred credentials{};
            socklen_t size = sizeof(credentials);
            if (getsockopt(client, SOL_SOCKET, SO_PEERCRED, &credentials, &size) == 0 && credentials.uid == getuid()) {
                try { session_loop(client); } catch (...) { }
            }
            close(client);
        }
        _exit(0);
    }
    int status = 0;
    pid_t waited;
    do { waited = waitpid(child, &status, 0); } while (waited < 0 && errno == EINTR);
    if (waited != child || !WIFEXITED(status) || WEXITSTATUS(status) != 0) {
        cleanup(); throw WorkerError("cannot start CUDA session child");
    }
    close(listener);
    std::cout << "{\"abi\":1,\"ok\":true,\"value\":\"" << path << "\"}\n";
}
