// LSL CUDA worker: real NVIDIA CUDA Runtime backend for lsl-cuda-v1.
//
// The LSL compiler and generated programs stay pure, syscall-only LSL ELFs.
// This optional process is deliberately a foreign boundary: it owns the CUDA
// context and translates JSON metadata or binary Float64 requests into real
// device allocations and kernel launches.

#include <cuda_runtime.h>

#include <cerrno>
#include <cmath>
#include <cstdlib>
#include <cstring>
#include <iomanip>
#include <iostream>
#include <limits>
#include <sstream>
#include <stdexcept>
#include <string>
#include <vector>

namespace {

constexpr int kThreads = 256;
constexpr int kTile = 16;
constexpr unsigned long long kProbeInput = 0x4c534c4355444136ULL;
constexpr unsigned long long kProbeOutput = 0x91f498ec5844b56bULL;

class WorkerError : public std::runtime_error {
public:
    explicit WorkerError(const std::string& message) : std::runtime_error(message) {}
};

void cuda_check(cudaError_t status, const char* operation) {
    if (status != cudaSuccess) {
        throw WorkerError(std::string(operation) + ": " + cudaGetErrorString(status));
    }
}

std::string json_escape(const std::string& text) {
    std::ostringstream output;
    for (unsigned char character : text) {
        switch (character) {
        case '"':
            output << "\\\"";
            break;
        case '\\':
            output << "\\\\";
            break;
        case '\n':
            output << "\\n";
            break;
        case '\r':
            output << "\\r";
            break;
        case '\t':
            output << "\\t";
            break;
        default:
            if (character < 0x20) {
                output << "\\u" << std::hex << std::setw(4) << std::setfill('0')
                       << static_cast<int>(character) << std::dec;
            } else {
                output << static_cast<char>(character);
            }
        }
    }
    return output.str();
}

std::size_t key_value_position(const std::string& json, const std::string& key) {
    const std::string pattern = "\"" + key + "\"";
    std::size_t position = json.find(pattern);
    if (position == std::string::npos) {
        throw WorkerError("request is missing key " + key);
    }
    position = json.find(':', position + pattern.size());
    if (position == std::string::npos) {
        throw WorkerError("request key " + key + " has no value");
    }
    ++position;
    while (position < json.size() &&
           (json[position] == ' ' || json[position] == '\t' ||
            json[position] == '\r' || json[position] == '\n')) {
        ++position;
    }
    return position;
}

std::string string_value(const std::string& json, const std::string& key) {
    std::size_t position = key_value_position(json, key);
    if (position >= json.size() || json[position] != '"') {
        throw WorkerError("request key " + key + " must be a String");
    }
    ++position;
    std::string result;
    while (position < json.size()) {
        char character = json[position++];
        if (character == '"') {
            return result;
        }
        if (character == '\\') {
            if (position >= json.size()) {
                throw WorkerError("unfinished String escape");
            }
            char escaped = json[position++];
            if (escaped == 'n') {
                result.push_back('\n');
            } else if (escaped == 'r') {
                result.push_back('\r');
            } else if (escaped == 't') {
                result.push_back('\t');
            } else if (escaped == '"' || escaped == '\\' || escaped == '/') {
                result.push_back(escaped);
            } else {
                throw WorkerError("unsupported String escape in request");
            }
        } else {
            result.push_back(character);
        }
    }
    throw WorkerError("unterminated String in request");
}

double number_at(const std::string& json, std::size_t& position) {
    while (position < json.size() &&
           (json[position] == ' ' || json[position] == '\t' ||
            json[position] == '\r' || json[position] == '\n')) {
        ++position;
    }
    const char* start = json.c_str() + position;
    char* stop = nullptr;
    errno = 0;
    double value = std::strtod(start, &stop);
    if (stop == start || errno == ERANGE || !std::isfinite(value)) {
        throw WorkerError("invalid finite numeric value in request");
    }
    position = static_cast<std::size_t>(stop - json.c_str());
    return value;
}

double number_value(const std::string& json, const std::string& key) {
    std::size_t position = key_value_position(json, key);
    return number_at(json, position);
}

long long integer_value(const std::string& json, const std::string& key) {
    double value = number_value(json, key);
    if (value < 0.0 || value > static_cast<double>(std::numeric_limits<int>::max()) ||
        std::floor(value) != value) {
        throw WorkerError("request key " + key + " must be a non-negative Int");
    }
    return static_cast<long long>(value);
}

std::size_t size_argument(const char* text, const char* name) {
    if (text == nullptr || text[0] == '\0') {
        throw WorkerError(std::string("missing binary ") + name);
    }
    char* stop = nullptr;
    errno = 0;
    unsigned long long value = std::strtoull(text, &stop, 10);
    if (stop == text || *stop != '\0' || errno == ERANGE ||
        value > std::numeric_limits<std::size_t>::max()) {
        throw WorkerError(std::string("invalid binary ") + name);
    }
    return static_cast<std::size_t>(value);
}

double double_argument(const char* text, const char* name) {
    if (text == nullptr || text[0] == '\0') {
        throw WorkerError(std::string("missing binary ") + name);
    }
    char* stop = nullptr;
    errno = 0;
    double value = std::strtod(text, &stop);
    if (stop == text || *stop != '\0' || errno == ERANGE || !std::isfinite(value)) {
        throw WorkerError(std::string("invalid binary ") + name);
    }
    return value;
}

std::vector<double> array_value(const std::string& json, const std::string& key) {
    std::size_t position = key_value_position(json, key);
    if (position >= json.size() || json[position] != '[') {
        throw WorkerError("request key " + key + " must be an Array");
    }
    ++position;
    std::vector<double> values;
    while (true) {
        while (position < json.size() &&
               (json[position] == ' ' || json[position] == '\t' ||
                json[position] == '\r' || json[position] == '\n')) {
            ++position;
        }
        if (position >= json.size()) {
            throw WorkerError("unterminated Array in request");
        }
        if (json[position] == ']') {
            ++position;
            return values;
        }
        values.push_back(number_at(json, position));
        while (position < json.size() &&
               (json[position] == ' ' || json[position] == '\t' ||
                json[position] == '\r' || json[position] == '\n')) {
            ++position;
        }
        if (position < json.size() && json[position] == ',') {
            ++position;
        } else if (position < json.size() && json[position] == ']') {
            ++position;
            return values;
        } else {
            throw WorkerError("expected comma or closing bracket in Array");
        }
    }
}

void print_failure(const std::string& message) {
    std::cout << "{\"abi\":1,\"ok\":false,\"error\":\""
              << json_escape(message) << "\"}\n";
}

void print_number(double value) {
    if (!std::isfinite(value)) {
        throw WorkerError("CUDA result is not a finite Float");
    }
    std::cout << "{\"abi\":1,\"ok\":true,\"value\":"
              << std::setprecision(17) << value << "}\n";
}

void print_array(const std::vector<double>& values) {
    std::cout << "{\"abi\":1,\"ok\":true,\"value\":[";
    for (std::size_t index = 0; index < values.size(); ++index) {
        if (index != 0) {
            std::cout << ',';
        }
        if (!std::isfinite(values[index])) {
            throw WorkerError("CUDA result contains a non-finite Float");
        }
        std::cout << std::setprecision(17) << values[index];
    }
    std::cout << "]}\n";
}

template <typename T>
class DeviceBuffer {
public:
    explicit DeviceBuffer(std::size_t count) : pointer_(nullptr), count_(count) {
        if (count_ != 0) {
            cuda_check(cudaMalloc(reinterpret_cast<void**>(&pointer_), count_ * sizeof(T)),
                       "cudaMalloc");
        }
    }

    ~DeviceBuffer() {
        if (pointer_ != nullptr) {
            cudaFree(pointer_);
        }
    }

    DeviceBuffer(const DeviceBuffer&) = delete;
    DeviceBuffer& operator=(const DeviceBuffer&) = delete;

    T* get() {
        return pointer_;
    }

    const T* get() const {
        return pointer_;
    }

private:
    T* pointer_;
    std::size_t count_;
};

__global__ void probe_kernel(unsigned long long* output) {
    if (blockIdx.x == 0 && threadIdx.x == 0) {
        *output = kProbeInput ^ 0xdda7d4af0d00f45dULL;
    }
}

__global__ void reduce_sum_kernel(const double* input, double* output,
                                  std::size_t count) {
    __shared__ double shared[kThreads];
    const unsigned int thread = threadIdx.x;
    const std::size_t index =
        static_cast<std::size_t>(blockIdx.x) * blockDim.x * 2 + thread;
    double value = 0.0;
    if (index < count) {
        value = input[index];
    }
    if (index + blockDim.x < count) {
        value += input[index + blockDim.x];
    }
    shared[thread] = value;
    __syncthreads();

    for (unsigned int stride = blockDim.x / 2; stride > 0; stride >>= 1) {
        if (thread < stride) {
            shared[thread] += shared[thread + stride];
        }
        __syncthreads();
    }
    if (thread == 0) {
        output[blockIdx.x] = shared[0];
    }
}

__global__ void reduce_dot_kernel(const double* left, const double* right,
                                  double* output, std::size_t count) {
    __shared__ double shared[kThreads];
    const unsigned int thread = threadIdx.x;
    const std::size_t index =
        static_cast<std::size_t>(blockIdx.x) * blockDim.x * 2 + thread;
    double value = 0.0;
    if (index < count) {
        value = left[index] * right[index];
    }
    if (index + blockDim.x < count) {
        value += left[index + blockDim.x] * right[index + blockDim.x];
    }
    shared[thread] = value;
    __syncthreads();

    for (unsigned int stride = blockDim.x / 2; stride > 0; stride >>= 1) {
        if (thread < stride) {
            shared[thread] += shared[thread + stride];
        }
        __syncthreads();
    }
    if (thread == 0) {
        output[blockIdx.x] = shared[0];
    }
}

__global__ void axpy_kernel(double alpha, const double* x, double* y,
                            std::size_t count) {
    const std::size_t index =
        static_cast<std::size_t>(blockIdx.x) * blockDim.x + threadIdx.x;
    if (index < count) {
        y[index] = alpha * x[index] + y[index];
    }
}

__global__ void matmul_kernel(const double* left, const double* right,
                              double* output, int rows, int inner,
                              int columns) {
    __shared__ double left_tile[kTile][kTile];
    __shared__ double right_tile[kTile][kTile];

    const int row = blockIdx.y * kTile + threadIdx.y;
    const int column = blockIdx.x * kTile + threadIdx.x;
    double total = 0.0;
    const int tile_count = (inner + kTile - 1) / kTile;

    for (int tile = 0; tile < tile_count; ++tile) {
        const int left_column = tile * kTile + threadIdx.x;
        const int right_row = tile * kTile + threadIdx.y;
        left_tile[threadIdx.y][threadIdx.x] =
            row < rows && left_column < inner
                ? left[static_cast<std::size_t>(row) * inner + left_column]
                : 0.0;
        right_tile[threadIdx.y][threadIdx.x] =
            right_row < inner && column < columns
                ? right[static_cast<std::size_t>(right_row) * columns + column]
                : 0.0;
        __syncthreads();

#pragma unroll
        for (int offset = 0; offset < kTile; ++offset) {
            total += left_tile[threadIdx.y][offset] *
                     right_tile[offset][threadIdx.x];
        }
        __syncthreads();
    }

    if (row < rows && column < columns) {
        output[static_cast<std::size_t>(row) * columns + column] = total;
    }
}

int selected_device() {
    int count = 0;
    cuda_check(cudaGetDeviceCount(&count), "cudaGetDeviceCount");
    if (count <= 0) {
        throw WorkerError("no CUDA device is available");
    }
    int device = 0;
    const char* configured = std::getenv("LSL_CUDA_DEVICE");
    if (configured != nullptr && configured[0] != '\0') {
        char* stop = nullptr;
        long parsed = std::strtol(configured, &stop, 10);
        if (stop == configured || *stop != '\0' || parsed < 0 || parsed >= count) {
            throw WorkerError("LSL_CUDA_DEVICE does not select an available device");
        }
        device = static_cast<int>(parsed);
    }
    cuda_check(cudaSetDevice(device), "cudaSetDevice");
    return device;
}

void launch_probe() {
    DeviceBuffer<unsigned long long> output(1);
    probe_kernel<<<1, 1>>>(output.get());
    cuda_check(cudaGetLastError(), "probe kernel launch");
    unsigned long long value = 0;
    cuda_check(cudaMemcpy(&value, output.get(), sizeof(value), cudaMemcpyDeviceToHost),
               "probe cudaMemcpy device-to-host");
    if (value != kProbeOutput) {
        throw WorkerError("CUDA probe kernel returned an invalid device value");
    }
}

void print_probe() {
    int device = selected_device();
    launch_probe();
    cudaDeviceProp properties{};
    cuda_check(cudaGetDeviceProperties(&properties, device),
               "cudaGetDeviceProperties");
    int runtime_version = 0;
    int driver_version = 0;
    cuda_check(cudaRuntimeGetVersion(&runtime_version), "cudaRuntimeGetVersion");
    cuda_check(cudaDriverGetVersion(&driver_version), "cudaDriverGetVersion");
    std::cout
        << "{\"abi\":1,\"ok\":true,\"value\":{"
        << "\"backend\":\"nvidia-cuda-runtime\","
        << "\"verified\":true,"
        << "\"device\":" << device << ','
        << "\"name\":\"" << json_escape(properties.name) << "\","
        << "\"compute_capability\":\"" << properties.major << '.'
        << properties.minor << "\","
        << "\"runtime_version\":" << runtime_version << ','
        << "\"driver_version\":" << driver_version
        << "}}\n";
}

void print_devices() {
    int count = 0;
    cuda_check(cudaGetDeviceCount(&count), "cudaGetDeviceCount");
    int runtime_version = 0;
    int driver_version = 0;
    cuda_check(cudaRuntimeGetVersion(&runtime_version), "cudaRuntimeGetVersion");
    cuda_check(cudaDriverGetVersion(&driver_version), "cudaDriverGetVersion");
    std::cout << "{\"abi\":1,\"ok\":true,\"value\":[";
    for (int device = 0; device < count; ++device) {
        if (device != 0) {
            std::cout << ',';
        }
        cudaDeviceProp properties{};
        cuda_check(cudaGetDeviceProperties(&properties, device),
                   "cudaGetDeviceProperties");
        std::cout
            << "{\"index\":" << device
            << ",\"name\":\"" << json_escape(properties.name) << "\""
            << ",\"backend\":\"nvidia-cuda-runtime\""
            << ",\"compute_capability\":\"" << properties.major << '.'
            << properties.minor << "\""
            << ",\"memory_bytes\":"
            << static_cast<unsigned long long>(properties.totalGlobalMem)
            << ",\"multiprocessors\":" << properties.multiProcessorCount
            << ",\"runtime_version\":" << runtime_version
            << ",\"driver_version\":" << driver_version
            << '}';
    }
    std::cout << "]}\n";
}

double gpu_reduce(const std::vector<double>& left,
                  const std::vector<double>* right) {
    if (left.empty()) {
        return 0.0;
    }
    selected_device();
    DeviceBuffer<double> device_left(left.size());
    cuda_check(cudaMemcpy(device_left.get(), left.data(),
                          left.size() * sizeof(double), cudaMemcpyHostToDevice),
               "reduction cudaMemcpy left host-to-device");

    DeviceBuffer<double> device_right(right == nullptr ? 0 : right->size());
    if (right != nullptr) {
        cuda_check(cudaMemcpy(device_right.get(), right->data(),
                              right->size() * sizeof(double),
                              cudaMemcpyHostToDevice),
                   "dot cudaMemcpy right host-to-device");
    }

    std::size_t blocks = (left.size() + kThreads * 2 - 1) / (kThreads * 2);
    DeviceBuffer<double> partial_a(blocks);
    DeviceBuffer<double> partial_b(blocks);
    if (right == nullptr) {
        reduce_sum_kernel<<<static_cast<unsigned int>(blocks), kThreads>>>(
            device_left.get(), partial_a.get(), left.size());
    } else {
        reduce_dot_kernel<<<static_cast<unsigned int>(blocks), kThreads>>>(
            device_left.get(), device_right.get(), partial_a.get(), left.size());
    }
    cuda_check(cudaGetLastError(), "reduction kernel launch");

    std::size_t remaining = blocks;
    bool current_is_a = true;
    while (remaining > 1) {
        std::size_t next_blocks =
            (remaining + kThreads * 2 - 1) / (kThreads * 2);
        const double* input = current_is_a ? partial_a.get() : partial_b.get();
        double* output = current_is_a ? partial_b.get() : partial_a.get();
        reduce_sum_kernel<<<static_cast<unsigned int>(next_blocks), kThreads>>>(
            input, output, remaining);
        cuda_check(cudaGetLastError(), "recursive reduction kernel launch");
        remaining = next_blocks;
        current_is_a = !current_is_a;
    }

    const double* result_pointer =
        current_is_a ? partial_a.get() : partial_b.get();
    double result = 0.0;
    cuda_check(cudaMemcpy(&result, result_pointer, sizeof(result),
                          cudaMemcpyDeviceToHost),
               "reduction cudaMemcpy device-to-host");
    return result;
}

std::vector<double> gpu_axpy(double alpha, const std::vector<double>& x,
                             const std::vector<double>& y) {
    if (x.size() != y.size()) {
        throw WorkerError("cuda.axpy arrays have different lengths");
    }
    if (x.empty()) {
        return {};
    }
    selected_device();
    DeviceBuffer<double> device_x(x.size());
    DeviceBuffer<double> device_y(y.size());
    cuda_check(cudaMemcpy(device_x.get(), x.data(), x.size() * sizeof(double),
                          cudaMemcpyHostToDevice),
               "axpy cudaMemcpy x host-to-device");
    cuda_check(cudaMemcpy(device_y.get(), y.data(), y.size() * sizeof(double),
                          cudaMemcpyHostToDevice),
               "axpy cudaMemcpy y host-to-device");
    const std::size_t blocks = (x.size() + kThreads - 1) / kThreads;
    axpy_kernel<<<static_cast<unsigned int>(blocks), kThreads>>>(
        alpha, device_x.get(), device_y.get(), x.size());
    cuda_check(cudaGetLastError(), "axpy kernel launch");
    std::vector<double> result(y.size());
    cuda_check(cudaMemcpy(result.data(), device_y.get(),
                          result.size() * sizeof(double),
                          cudaMemcpyDeviceToHost),
               "axpy cudaMemcpy device-to-host");
    return result;
}

std::size_t checked_product(std::size_t left, std::size_t right,
                            const char* description) {
    if (left != 0 && right > std::numeric_limits<std::size_t>::max() / left) {
        throw WorkerError(std::string(description) + " size overflow");
    }
    return left * right;
}

std::vector<double> gpu_matmul(const std::vector<double>& left,
                               const std::vector<double>& right,
                               int rows, int inner, int columns) {
    const std::size_t left_count =
        checked_product(static_cast<std::size_t>(rows),
                        static_cast<std::size_t>(inner), "left matrix");
    const std::size_t right_count =
        checked_product(static_cast<std::size_t>(inner),
                        static_cast<std::size_t>(columns), "right matrix");
    const std::size_t output_count =
        checked_product(static_cast<std::size_t>(rows),
                        static_cast<std::size_t>(columns), "output matrix");
    if (left.size() != left_count || right.size() != right_count) {
        throw WorkerError("cuda.matmul array lengths do not match dimensions");
    }
    if (output_count == 0) {
        return {};
    }
    if (inner == 0) {
        return std::vector<double>(output_count, 0.0);
    }

    selected_device();
    DeviceBuffer<double> device_left(left.size());
    DeviceBuffer<double> device_right(right.size());
    DeviceBuffer<double> device_output(output_count);
    cuda_check(cudaMemcpy(device_left.get(), left.data(),
                          left.size() * sizeof(double), cudaMemcpyHostToDevice),
               "matmul cudaMemcpy left host-to-device");
    cuda_check(cudaMemcpy(device_right.get(), right.data(),
                          right.size() * sizeof(double), cudaMemcpyHostToDevice),
               "matmul cudaMemcpy right host-to-device");

    dim3 threads(kTile, kTile);
    dim3 blocks((columns + kTile - 1) / kTile,
                (rows + kTile - 1) / kTile);
    matmul_kernel<<<blocks, threads>>>(device_left.get(), device_right.get(),
                                      device_output.get(), rows, inner, columns);
    cuda_check(cudaGetLastError(), "matmul kernel launch");
    std::vector<double> result(output_count);
    cuda_check(cudaMemcpy(result.data(), device_output.get(),
                          result.size() * sizeof(double),
                          cudaMemcpyDeviceToHost),
               "matmul cudaMemcpy device-to-host");
    return result;
}

void run_request(const std::string& request) {
    const std::string operation = string_value(request, "operation");
    if (operation == "cuda.probe") {
        print_probe();
    } else if (operation == "cuda.devices") {
        print_devices();
    } else if (operation == "cuda.sum") {
        print_number(gpu_reduce(array_value(request, "values"), nullptr));
    } else if (operation == "cuda.dot") {
        const std::vector<double> left = array_value(request, "left");
        const std::vector<double> right = array_value(request, "right");
        if (left.size() != right.size()) {
            throw WorkerError("cuda.dot arrays have different lengths");
        }
        print_number(gpu_reduce(left, &right));
    } else if (operation == "cuda.axpy") {
        const double alpha = number_value(request, "alpha");
        const std::vector<double> x = array_value(request, "x");
        const std::vector<double> y = array_value(request, "y");
        print_array(gpu_axpy(alpha, x, y));
    } else if (operation == "cuda.matmul") {
        const int rows = static_cast<int>(integer_value(request, "m"));
        const int inner = static_cast<int>(integer_value(request, "k"));
        const int columns = static_cast<int>(integer_value(request, "n"));
        const std::vector<double> left = array_value(request, "left");
        const std::vector<double> right = array_value(request, "right");
        print_array(gpu_matmul(left, right, rows, inner, columns));
    } else {
        throw WorkerError("unsupported CUDA operation " + operation);
    }
}

std::string read_stdin() {
    std::ostringstream input;
    input << std::cin.rdbuf();
    return input.str();
}

std::vector<double> doubles_from_bytes(const std::string& bytes,
                                       std::size_t offset,
                                       std::size_t count) {
    const std::size_t byte_count = checked_product(count, sizeof(double),
                                                   "binary FloatArray");
    if (offset > bytes.size() || byte_count > bytes.size() - offset) {
        throw WorkerError("binary CUDA payload is shorter than declared");
    }
    std::vector<double> result(count);
    if (byte_count != 0) {
        std::memcpy(result.data(), bytes.data() + offset, byte_count);
    }
    return result;
}

void write_doubles(const std::vector<double>& values) {
    if (!values.empty()) {
        std::cout.write(reinterpret_cast<const char*>(values.data()),
                        static_cast<std::streamsize>(values.size() * sizeof(double)));
    }
}

void run_binary(int argc, char** argv) {
    if (argc < 4) {
        throw WorkerError("binary worker request has too few arguments");
    }
    const std::string operation = argv[2];
    const std::string payload = read_stdin();
    if (operation == "sum") {
        if (argc != 4) {
            throw WorkerError("binary sum expects count");
        }
        const std::size_t count = size_argument(argv[3], "sum count");
        const std::size_t bytes =
            checked_product(count, sizeof(double), "binary sum");
        if (payload.size() != bytes) {
            throw WorkerError("binary sum payload length differs");
        }
        const std::vector<double> values = doubles_from_bytes(payload, 0, count);
        write_doubles({gpu_reduce(values, nullptr)});
    } else if (operation == "dot") {
        if (argc != 4) {
            throw WorkerError("binary dot expects count");
        }
        const std::size_t count = size_argument(argv[3], "dot count");
        const std::size_t bytes = checked_product(count, sizeof(double), "dot");
        const std::vector<double> left = doubles_from_bytes(payload, 0, count);
        const std::vector<double> right = doubles_from_bytes(payload, bytes, count);
        const std::size_t payload_bytes =
            checked_product(bytes, 2, "binary dot payload");
        if (payload.size() != payload_bytes) {
            throw WorkerError("binary dot payload length differs");
        }
        write_doubles({gpu_reduce(left, &right)});
    } else if (operation == "axpy") {
        if (argc != 5) {
            throw WorkerError("binary axpy expects alpha and count");
        }
        const double alpha = double_argument(argv[3], "axpy alpha");
        const std::size_t count = size_argument(argv[4], "axpy count");
        const std::size_t bytes = checked_product(count, sizeof(double), "axpy");
        const std::vector<double> x = doubles_from_bytes(payload, 0, count);
        const std::vector<double> y = doubles_from_bytes(payload, bytes, count);
        const std::size_t payload_bytes =
            checked_product(bytes, 2, "binary axpy payload");
        if (payload.size() != payload_bytes) {
            throw WorkerError("binary axpy payload length differs");
        }
        write_doubles(gpu_axpy(alpha, x, y));
    } else if (operation == "matmul") {
        if (argc != 6) {
            throw WorkerError("binary matmul expects m, k, and n");
        }
        const std::size_t rows = size_argument(argv[3], "matmul rows");
        const std::size_t inner = size_argument(argv[4], "matmul inner");
        const std::size_t columns = size_argument(argv[5], "matmul columns");
        if (rows > static_cast<std::size_t>(std::numeric_limits<int>::max()) ||
            inner > static_cast<std::size_t>(std::numeric_limits<int>::max()) ||
            columns > static_cast<std::size_t>(std::numeric_limits<int>::max())) {
            throw WorkerError("binary matmul dimensions exceed Int32");
        }
        const std::size_t left_count = checked_product(rows, inner, "left matrix");
        const std::size_t right_count =
            checked_product(inner, columns, "right matrix");
        const std::size_t left_bytes =
            checked_product(left_count, sizeof(double), "left matrix");
        const std::size_t right_bytes =
            checked_product(right_count, sizeof(double), "right matrix");
        if (left_bytes > std::numeric_limits<std::size_t>::max() - right_bytes ||
            payload.size() != left_bytes + right_bytes) {
            throw WorkerError("binary matmul payload length differs");
        }
        const std::vector<double> left =
            doubles_from_bytes(payload, 0, left_count);
        const std::vector<double> right =
            doubles_from_bytes(payload, left_bytes, right_count);
        write_doubles(gpu_matmul(left, right, static_cast<int>(rows),
                                 static_cast<int>(inner),
                                 static_cast<int>(columns)));
    } else {
        throw WorkerError("unsupported binary CUDA operation " + operation);
    }
}

} // namespace

int main(int argc, char** argv) {
    const bool binary = argc >= 2 && std::strcmp(argv[1], "--binary") == 0;
    try {
        if (binary) {
            run_binary(argc, argv);
        } else if (argc == 2) {
            run_request(argv[1]);
        } else if (argc == 1) {
            const std::string input = read_stdin();
            if (input.empty()) {
                throw WorkerError("worker received no JSON request on stdin");
            }
            run_request(input);
        } else {
            throw WorkerError("worker expects JSON on stdin or one argv request");
        }
    } catch (const std::exception& error) {
        if (binary) {
            std::cerr << error.what() << '\n';
            return 2;
        }
        print_failure(error.what());
    }
    return 0;
}
