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
constexpr std::size_t kMaxJsonBytes = 4 * 1024 * 1024;
constexpr std::size_t kMaxJsonElements = 131072;
constexpr std::size_t kMaxElements = 2000000;
constexpr std::size_t kMaxBinaryBytes = kMaxElements * 2 * sizeof(double);
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

class JsonScanner {
public:
    explicit JsonScanner(const std::string& json) : json_(json), position_(0) {}

    std::size_t top_level_value_position(const std::string& target,
                                         std::size_t* value_end = nullptr) {
        skip_whitespace();
        expect('{', "request must be a JSON Object");
        skip_whitespace();
        bool found = false;
        std::size_t result = 0;
        std::size_t result_end = 0;
        if (consume('}')) {
            finish();
            throw WorkerError("request is missing key " + target);
        }
        while (true) {
            const std::string key = parse_string(true);
            skip_whitespace();
            expect(':', "JSON Object key has no value");
            skip_whitespace();
            const std::size_t value_position = position_;
            const bool is_target = key == target;
            if (is_target) {
                if (found) {
                    throw WorkerError("request contains duplicate key " + target);
                }
                found = true;
                result = value_position;
            }
            skip_value(1);
            if (is_target) {
                result_end = position_;
            }
            skip_whitespace();
            if (consume('}')) {
                break;
            }
            expect(',', "expected comma or closing brace in JSON Object");
            skip_whitespace();
        }
        finish();
        if (!found) {
            throw WorkerError("request is missing key " + target);
        }
        if (value_end != nullptr) {
            *value_end = result_end;
        }
        return result;
    }

private:
    static bool is_digit(char character) {
        return character >= '0' && character <= '9';
    }

    static bool is_hex_digit(char character) {
        return is_digit(character) ||
               (character >= 'a' && character <= 'f') ||
               (character >= 'A' && character <= 'F');
    }

    void skip_whitespace() {
        while (position_ < json_.size() &&
               (json_[position_] == ' ' || json_[position_] == '\t' ||
                json_[position_] == '\r' || json_[position_] == '\n')) {
            ++position_;
        }
    }

    bool consume(char expected) {
        if (position_ < json_.size() && json_[position_] == expected) {
            ++position_;
            return true;
        }
        return false;
    }

    void expect(char expected, const char* message) {
        if (!consume(expected)) {
            throw WorkerError(message);
        }
    }

    void finish() {
        skip_whitespace();
        if (position_ != json_.size()) {
            throw WorkerError("unexpected data after JSON request");
        }
    }

    std::string parse_string(bool capture) {
        expect('"', "JSON Object key must be a String");
        std::string result;
        while (position_ < json_.size()) {
            const unsigned char character =
                static_cast<unsigned char>(json_[position_++]);
            if (character == '"') {
                return result;
            }
            if (character < 0x20) {
                throw WorkerError("unescaped control character in JSON String");
            }
            if (character == '\\') {
                if (position_ >= json_.size()) {
                    throw WorkerError("unfinished JSON String escape");
                }
                const char escaped = json_[position_++];
                if (escaped == 'u') {
                    if (json_.size() - position_ < 4) {
                        throw WorkerError("unfinished JSON Unicode escape");
                    }
                    for (int index = 0; index < 4; ++index) {
                        if (!is_hex_digit(json_[position_ + index])) {
                            throw WorkerError("invalid JSON Unicode escape");
                        }
                    }
                    position_ += 4;
                    if (capture) {
                        result.push_back('?');
                    }
                } else if (escaped == '"' || escaped == '\\' || escaped == '/' ||
                           escaped == 'b' || escaped == 'f' || escaped == 'n' ||
                           escaped == 'r' || escaped == 't') {
                    if (capture) {
                        result.push_back(escaped);
                    }
                } else {
                    throw WorkerError("invalid JSON String escape");
                }
            } else if (capture) {
                result.push_back(static_cast<char>(character));
            }
            if (capture && result.size() > 256) {
                throw WorkerError("JSON Object key exceeds 256 bytes");
            }
        }
        throw WorkerError("unterminated JSON String");
    }

    void skip_number() {
        consume('-');
        if (position_ >= json_.size()) {
            throw WorkerError("unfinished JSON Number");
        }
        if (consume('0')) {
            if (position_ < json_.size() && is_digit(json_[position_])) {
                throw WorkerError("JSON Number has a leading zero");
            }
        } else {
            if (json_[position_] < '1' || json_[position_] > '9') {
                throw WorkerError("invalid JSON Number");
            }
            while (position_ < json_.size() && is_digit(json_[position_])) {
                ++position_;
            }
        }
        if (consume('.')) {
            if (position_ >= json_.size() || !is_digit(json_[position_])) {
                throw WorkerError("invalid JSON Number fraction");
            }
            while (position_ < json_.size() && is_digit(json_[position_])) {
                ++position_;
            }
        }
        if (position_ < json_.size() &&
            (json_[position_] == 'e' || json_[position_] == 'E')) {
            ++position_;
            if (position_ < json_.size() &&
                (json_[position_] == '+' || json_[position_] == '-')) {
                ++position_;
            }
            if (position_ >= json_.size() || !is_digit(json_[position_])) {
                throw WorkerError("invalid JSON Number exponent");
            }
            while (position_ < json_.size() && is_digit(json_[position_])) {
                ++position_;
            }
        }
    }

    void skip_literal(const char* literal) {
        const std::size_t length = std::strlen(literal);
        if (json_.size() - position_ < length ||
            json_.compare(position_, length, literal) != 0) {
            throw WorkerError("invalid JSON value");
        }
        position_ += length;
    }

    void skip_value(std::size_t depth) {
        if (depth > 64) {
            throw WorkerError("JSON nesting exceeds 64 levels");
        }
        skip_whitespace();
        if (position_ >= json_.size()) {
            throw WorkerError("missing JSON value");
        }
        const char first = json_[position_];
        if (first == '"') {
            parse_string(false);
        } else if (first == '{') {
            ++position_;
            skip_whitespace();
            if (consume('}')) {
                return;
            }
            while (true) {
                parse_string(false);
                skip_whitespace();
                expect(':', "JSON Object key has no value");
                skip_value(depth + 1);
                skip_whitespace();
                if (consume('}')) {
                    return;
                }
                expect(',', "expected comma or closing brace in JSON Object");
                skip_whitespace();
            }
        } else if (first == '[') {
            ++position_;
            skip_whitespace();
            if (consume(']')) {
                return;
            }
            while (true) {
                skip_value(depth + 1);
                skip_whitespace();
                if (consume(']')) {
                    return;
                }
                expect(',', "expected comma or closing bracket in JSON Array");
                skip_whitespace();
            }
        } else if (first == 't') {
            skip_literal("true");
        } else if (first == 'f') {
            skip_literal("false");
        } else if (first == 'n') {
            skip_literal("null");
        } else if (first == '-' || is_digit(first)) {
            skip_number();
        } else {
            throw WorkerError("invalid JSON value");
        }
    }

    const std::string& json_;
    std::size_t position_;
};

std::size_t key_value_position(const std::string& json, const std::string& key) {
    JsonScanner scanner(json);
    return scanner.top_level_value_position(key);
}

std::string object_value(const std::string& json, const std::string& key) {
    JsonScanner scanner(json);
    std::size_t end = 0;
    const std::size_t start = scanner.top_level_value_position(key, &end);
    if (start >= json.size() || json[start] != '{' || end <= start) {
        throw WorkerError("request key " + key + " must be an Object");
    }
    return json.substr(start, end - start);
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
        if (result.size() > 256) {
            throw WorkerError("request String value exceeds 256 bytes");
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
        value > std::numeric_limits<std::size_t>::max() || value > kMaxElements) {
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
        if (values.size() >= kMaxJsonElements) {
            throw WorkerError("request Array exceeds the 131072-element JSON limit");
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
    if (values.size() > kMaxJsonElements) {
        throw WorkerError("JSON response exceeds the secure element limit");
    }
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
        if (count_ > kMaxElements ||
            count_ > std::numeric_limits<std::size_t>::max() / sizeof(T)) {
            throw WorkerError("CUDA buffer exceeds the secure element limit");
        }
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
    if (count < 0 || count > 256) {
        throw WorkerError("CUDA device count exceeds the secure limit");
    }
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
                               int rows, int inner, int columns,
                               std::size_t element_limit = kMaxElements) {
    const std::size_t left_count =
        checked_product(static_cast<std::size_t>(rows),
                        static_cast<std::size_t>(inner), "left matrix");
    const std::size_t right_count =
        checked_product(static_cast<std::size_t>(inner),
                        static_cast<std::size_t>(columns), "right matrix");
    const std::size_t output_count =
        checked_product(static_cast<std::size_t>(rows),
                        static_cast<std::size_t>(columns), "output matrix");
    if (left_count > element_limit || right_count > element_limit ||
        output_count > element_limit) {
        throw WorkerError("cuda.matmul exceeds the secure element limit");
    }
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
    if (request.empty() || request.size() > kMaxJsonBytes ||
        request.find('\0') != std::string::npos) {
        throw WorkerError("JSON request must contain 1..4194304 bytes without NUL");
    }
    if (integer_value(request, "abi") != 1) {
        throw WorkerError("CUDA request ABI version mismatch");
    }
    const std::string operation = string_value(request, "operation");
    const std::string payload = object_value(request, "payload");
    if (operation == "cuda.probe") {
        print_probe();
    } else if (operation == "cuda.devices") {
        print_devices();
    } else if (operation == "cuda.sum") {
        print_number(gpu_reduce(array_value(payload, "values"), nullptr));
    } else if (operation == "cuda.dot") {
        const std::vector<double> left = array_value(payload, "left");
        const std::vector<double> right = array_value(payload, "right");
        if (left.size() != right.size()) {
            throw WorkerError("cuda.dot arrays have different lengths");
        }
        print_number(gpu_reduce(left, &right));
    } else if (operation == "cuda.axpy") {
        const double alpha = number_value(payload, "alpha");
        const std::vector<double> x = array_value(payload, "x");
        const std::vector<double> y = array_value(payload, "y");
        print_array(gpu_axpy(alpha, x, y));
    } else if (operation == "cuda.matmul") {
        const int rows = static_cast<int>(integer_value(payload, "m"));
        const int inner = static_cast<int>(integer_value(payload, "k"));
        const int columns = static_cast<int>(integer_value(payload, "n"));
        const std::vector<double> left = array_value(payload, "left");
        const std::vector<double> right = array_value(payload, "right");
        print_array(gpu_matmul(left, right, rows, inner, columns,
                               kMaxJsonElements));
    } else {
        throw WorkerError("unsupported CUDA operation " + operation);
    }
}

std::string read_stdin(std::size_t limit) {
    std::string input;
    char buffer[65536];
    while (std::cin.good()) {
        std::cin.read(buffer, static_cast<std::streamsize>(sizeof(buffer)));
        const std::streamsize received = std::cin.gcount();
        if (received > 0) {
            const std::size_t count = static_cast<std::size_t>(received);
            if (input.size() > limit || count > limit - input.size()) {
                throw WorkerError("worker stdin exceeds the secure size limit");
            }
            input.append(buffer, count);
        }
    }
    if (std::cin.bad()) {
        throw WorkerError("cannot read worker stdin");
    }
    return input;
}

std::vector<double> doubles_from_bytes(const std::string& bytes,
                                       std::size_t offset,
                                       std::size_t count) {
    const std::size_t byte_count = checked_product(count, sizeof(double),
                                                   "binary FloatArray");
    if (count > kMaxElements) {
        throw WorkerError("binary FloatArray exceeds the secure element limit");
    }
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
    if (values.size() > kMaxElements) {
        throw WorkerError("binary CUDA output exceeds the secure element limit");
    }
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
    const std::string payload = read_stdin(kMaxBinaryBytes);
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
            const std::string input = read_stdin(kMaxJsonBytes);
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
