load _random_platform as transport
# Python-shaped random API, entirely in LSL. MT19937 is NOT cryptographic.
# Use SystemRandom for operating-system randomness. See docs/random.md for
# compatibility, Int64/BigInt boundaries, limits and algorithm references.

# MT19937 core: Copyright (C) 1997 - 2002, Makoto Matsumoto and
# Takuji Nishimura. All rights reserved.
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions are met:
# 1. Redistributions of source code must retain the above copyright notice,
#    this list of conditions and the following disclaimer.
# 2. Redistributions in binary form must reproduce the above copyright notice,
#    this list of conditions and the following disclaimer in the documentation
#    and/or other materials provided with the distribution.
# 3. The names of its contributors may not be used to endorse or promote
#    products derived from this software without specific prior written permission.
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
# AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
# IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
# ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE
# LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
# CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
# SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
# INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
# CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
# ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
# POSSIBILITY OF SUCH DAMAGE.

load math
load bigint
load _random_hash

function _integer(value):
    if type(value) != "Int" and type(value) != "Bool":
        Error(TypeError: "random requires an integer, got " + type(value))
    end
    return Int(value)
end

function _finite(value):
    if type(value) != "Float" and type(value) != "Int" and type(value) != "Bool":
        Error(TypeError: "random requires a real number")
    end
    number = Float(value)
    if number != number or abs(number) == 1.0 / 0.0:
        Error(ValueError: "random requires a finite number")
    end
    return number
end

function _entropy(n):
    return transport._entropy(n)
end

function _words64(value):
    result = [value & 0xffffffff]
    high = (value >> 32) & 0xffffffff
    if high != 0:
        call result.append(high)
    end
    return result
end

function _float_seed(value):
    # CPython's finite double hash, modulo 2^61-1, then cast to uint64.
    bits = __lsl_float_bits(value)
    exponent = (bits >> 52) & 2047
    mantissa = bits & 0x000fffffffffffff
    if exponent == 2047:
        if mantissa != 0:
            Error(ValueError: "NaN seeds are not reproducible")
        end
        hash = 314159
    else:
        power = -1074
        if exponent != 0:
            mantissa |= 0x0010000000000000
            power = exponent - 1075
        end
        shift = power % 61
        hash = mantissa
        if shift != 0:
            hash = ((mantissa << shift) & 0x1fffffffffffffff) | (mantissa >> (61 - shift))
        end
        if hash == 0x1fffffffffffffff:
            hash = 0
        end
    end
    if bits < 0:
        hash = -hash
    end
    if hash == -1:
        hash = -2
    end
    return _words64(hash)
end

function _seed_words(a, version):
    if version != 1 and version != 2:
        Error(ValueError: "random seed version must be 1 or 2")
    end
    kind = type(a)
    if a == None:
        entropy = _entropy(32)
        words = []
        for i in rang(8):
            word = 0
            for j in rang(4):
                word = (word << 8) | entropy[i * 4 + j]
            end
            call words.append(word)
        end
        return words
    elif kind == "Int" or kind == "Bool":
        value = Int(a)
        if value < 0:
            value = -value
        end
        return _words64(value)
    elif kind == "Float":
        return _float_seed(Float(a))
    elif kind == "Instance" or kind == "Dictionary":
        number = bigint.BigInt(a)
        number = bigint.BigInt(number.digits)
        if len(number.digits) > 1234:
            Error(ValueError: "random BigInt seed exceeds 4096 bits")
        end
        words = []
        while not number.equals(0):
            call words.append(number.modulo(4294967296).to_int())
            if len(words) > 128:
                Error(ValueError: "random BigInt seed exceeds 4096 bits")
            end
            number = number.floor_divide(4294967296)
        end
        if len(words) == 0:
            call words.append(0)
        end
        return words
    elif kind != "String" and kind != "ByteArray":
        Error(TypeError: "seed expects None, Int, Float, String, ByteArray or BigInt")
    end
    data = ByteArray()
    if kind == "String":
        text = String(a)
        if __lsl_text_byte_length(text) > 1048576:
            Error(ValueError: "random seed exceeds one MiB")
        end
        for i in rang(__lsl_text_byte_length(text)):
            call data.append(__lsl_text_byte(text, i))
        end
    else:
        if len(a) > 1048576:
            Error(ValueError: "random seed exceeds one MiB")
        end
        for value in a:
            call data.append(Int(value))
        end
    end
    if version == 1:
        hash = 0
        if len(a) > 0:
            if kind == "String":
                hash = ord(a[0]) << 7
            else:
                hash = Int(a[0]) << 7
            end
        end
        for value in a:
            if kind == "String":
                hash = (1000003 * hash) ~ ord(value)
            else:
                hash = (1000003 * hash) ~ Int(value)
            end
        end
        hash ~= len(a)
        return _words64(hash)
    end
    digest = _random_hash.digest(data)
    for byte in digest:
        call data.append(Int(byte))
    end
    words = []
    position = len(data)
    while position > 0:
        word = 0
        shift = 0
        while shift < 32 and position > 0:
            position -= 1
            word |= data[position] << shift
            shift += 8
        end
        call words.append(word)
    end
    return words
end

function _seed(state, a, version):
    if state["system"]:
        return None
    end
    key = _seed_words(a, _integer(version))
    mt = __lsl_int_zeros(624)
    mt[0] = 19650218
    for i in rang(1, 624):
        mt[i] = (1812433253 * (mt[i - 1] ~ (mt[i - 1] >> 30)) + i) & 0xffffffff
    end
    i = 1
    j = 0
    for count in rang(max(624, len(key))):
        mt[i] = ((mt[i] ~ ((mt[i - 1] ~ (mt[i - 1] >> 30)) * 1664525)) + Int(key[j]) + j) & 0xffffffff
        i += 1
        j += 1
        if i >= 624:
            mt[0] = mt[623]
            i = 1
        end
        if j >= len(key):
            j = 0
        end
    end
    for count in rang(623):
        mt[i] = ((mt[i] ~ ((mt[i - 1] ~ (mt[i - 1] >> 30)) * 1566083941)) - i) & 0xffffffff
        i += 1
        if i >= 624:
            mt[0] = mt[623]
            i = 1
        end
    end
    mt[0] = 0x80000000
    state["mt"] = mt
    state["index"] = 624
    state["gauss"] = None
    return None
end

function _new(a, system):
    state = {"system": system, "lock": __lsl_int_zeros(1), "mt": IntArray(), "index": 624, "gauss": None}
    call _seed(state, a, 2)
    return state
end

function _next32(state):
    if state["system"]:
        data = _entropy(4)
        return data[0] | (data[1] << 8) | (data[2] << 16) | (data[3] << 24)
    end
    mt = IntArray(state["mt"])
    index = Int(state["index"])
    if index >= 624:
        for i in rang(624):
            y = (mt[i] & 0x80000000) | (mt[(i + 1) % 624] & 0x7fffffff)
            mt[i] = mt[(i + 397) % 624] ~ (y >> 1) ~ ((y & 1) * 0x9908b0df)
        end
        index = 0
    end
    y = mt[index]
    state["index"] = index + 1
    y ~= y >> 11
    y ~= (y << 7) & 0x9d2c5680
    y ~= (y << 15) & 0xefc60000
    y ~= y >> 18
    return y
end

function _unit(state):
    a = _next32(state) >> 5
    b = _next32(state) >> 6
    return (Float(a) * 67108864.0 + Float(b)) / 9007199254740992.0
end

function _bits(state, k):
    if k == 0:
        return 0
    elif k <= 32:
        return _next32(state) >> (32 - k)
    end
    low = _next32(state)
    return low | ((_next32(state) >> (64 - k)) << 32)
end

function _getbits(state, k):
    bits = _integer(k)
    if bits < 0 or bits > 4096:
        Error(ValueError: "getrandbits requires 0..4096 bits")
    elif bits <= 63:
        return _bits(state, bits)
    end
    words = []
    remaining = bits
    while remaining > 0:
        width = min(32, remaining)
        call words.append(_bits(state, width))
        remaining -= width
    end
    result = bigint.BigInt(0)
    for i in rang(len(words) - 1, -1, -1):
        result = result.multiply(4294967296).add(words[i])
    end
    return result
end

function _below(state, n):
    if n <= 0:
        Error(ValueError: "empty range for random")
    end
    bits = 0
    value = n
    while value > 0:
        bits += 1
        value >>= 1
    end
    result = _bits(state, bits)
    while result >= n:
        result = _bits(state, bits)
    end
    return result
end

function _range(state, start, stop, step):
    if type(start) == "Instance" or type(stop) == "Instance" or type(step) == "Instance" or type(start) == "Dictionary" or type(stop) == "Dictionary" or type(step) == "Dictionary":
        return _big_range(state, start, stop, step, False)
    end
    first = _integer(start)
    stride = _integer(step)
    if stop == None:
        if stride != 1:
            Error(TypeError: "randrange with step requires stop")
        end
        return _below(state, first)
    end
    last = _integer(stop)
    if stride == 0:
        Error(ValueError: "randrange step must not be zero")
    elif (stride > 0 and first >= last) or (stride < 0 and first <= last):
        Error(ValueError: "empty range for randrange")
    end
    width = last - first
    if (last > first and width <= 0) or (last < first and width >= 0) or stride == -9223372036854775808 or width == -9223372036854775808:
        return bigint.BigInt(_big_range(state, first, last, stride, False)).to_int()
    end
    distance = abs(width)
    magnitude = abs(stride)
    count = (distance - 1) // magnitude + 1
    return first + stride * _below(state, count)
end

function _big_integer(value):
    if type(value) != "Int" and type(value) != "Bool" and type(value) != "Instance" and type(value) != "Dictionary":
        Error(TypeError: "random range requires Int or BigInt")
    end
    number = bigint.BigInt(value)
    if len(number.digits) > 1234:
        Error(ValueError: "random BigInt range exceeds 4096 bits")
    end
    return number
end

function _big_below(state, bound):
    n = bigint.BigInt(bound)
    if n.compare(0) <= 0:
        Error(ValueError: "empty range for random")
    end
    bits = 0
    remaining = bigint.BigInt(n)
    while not remaining.equals(0):
        bits += 1
        if bits > 4096:
            Error(ValueError: "random range exceeds 4096 bits")
        end
        remaining = remaining.floor_divide(2)
    end
    result = bigint.BigInt(_getbits(state, bits))
    while result.compare(n) >= 0:
        result = bigint.BigInt(_getbits(state, bits))
    end
    return result
end

function _big_range(state, start, stop, step, inclusive):
    first = _big_integer(start)
    stride = _big_integer(step)
    last = bigint.BigInt(0)
    if stop == None:
        if not stride.equals(1):
            Error(TypeError: "randrange with step requires stop")
        end
        return _big_below(state, first)
    end
    last = _big_integer(stop)
    if inclusive:
        last = last.add(1)
    end
    direction = stride.compare(0)
    if direction == 0:
        Error(ValueError: "randrange step must not be zero")
    elif (direction > 0 and first.compare(last) >= 0) or (direction < 0 and first.compare(last) <= 0):
        Error(ValueError: "empty range for random")
    end
    distance = last.subtract(first)
    magnitude = bigint.BigInt(stride)
    if direction < 0:
        distance = first.subtract(last)
        magnitude = bigint.BigInt(stride.digits)
    end
    count = distance.subtract(1).floor_divide(magnitude).add(1)
    return first.add(stride.multiply(_big_below(state, count)))
end

function _sequence(values, mutable):
    kind = type(values)
    if kind == "List" or kind == "IntArray" or kind == "FloatArray" or kind == "ByteArray" or kind == "RealArray":
        return
    elif not mutable and (kind == "Tuple" or kind == "String"):
        return
    end
    Error(TypeError: "random requires a sequence (shuffle requires a mutable sequence)")
end

function _bytes(state, n):
    count = _integer(n)
    if count < 0 or count > 1048576:
        Error(ValueError: "randbytes requires 0..1048576 bytes")
    elif state["system"]:
        return _entropy(count)
    end
    result = __lsl_byte_zeros(count)
    offset = 0
    while offset < count:
        width = min(4, count - offset)
        word = _bits(state, width * 8)
        for i in rang(width):
            result[offset + i] = (word >> (i * 8)) & 255
        end
        offset += width
    end
    return result
end

function _getstate(state):
    if state["system"]:
        Error(NotImplementedError: "SystemRandom has no reproducible state")
    end
    words = List(state["mt"])
    call words.append(state["index"])
    return (3, Tuple(words), state["gauss"])
end

function _setstate(state, snapshot):
    if state["system"]:
        Error(NotImplementedError: "SystemRandom has no reproducible state")
    end
    if type(snapshot) != "Tuple" and type(snapshot) != "List":
        Error(TypeError: "invalid random state")
    elif len(snapshot) != 3:
        Error(ValueError: "invalid random state length")
    end
    version = _integer(snapshot[0])
    if version != 2 and version != 3:
        Error(ValueError: "unsupported random state version")
    end
    words = snapshot[1]
    if type(words) != "Tuple" and type(words) != "List":
        Error(TypeError: "invalid MT19937 state")
    elif len(words) != 625:
        Error(ValueError: "MT19937 state must have 625 integers")
    end
    mt = __lsl_int_zeros(624)
    nonzero = False
    for i in rang(624):
        word = _integer(words[i])
        if version == 2:
            word &= 0xffffffff
        elif word < 0 or word > 0xffffffff:
            Error(ValueError: "MT19937 word outside uint32")
        end
        mt[i] = word
        nonzero = nonzero or word != 0
    end
    index = _integer(words[624])
    if index < 0 or index > 624 or not nonzero:
        Error(ValueError: "invalid MT19937 index or zero state")
    end
    cached = snapshot[2]
    if cached != None:
        cached = _finite(cached)
    end
    state["mt"] = mt
    state["index"] = index
    state["gauss"] = cached
    return None
end

function _search(cumulative, value):
    low = 0
    high = len(cumulative) - 1
    while low < high:
        middle = (low + high) // 2
        if value < cumulative[middle]:
            high = middle
        else:
            low = middle + 1
        end
    end
    return low
end

function _choices(state, population, weights, cumulative, k):
    call _sequence(population, False)
    count = _integer(k)
    if count < 0 or count > 1048576:
        Error(ValueError: "choices k must be 0..1048576")
    elif weights != None and cumulative != None:
        Error(TypeError: "specify weights or cum_weights, not both")
    end
    size = len(population)
    sums = FloatArray()
    total = 0.0
    if weights != None or cumulative != None:
        source = weights
        if cumulative != None:
            source = cumulative
        end
        call _sequence(source, False)
        if len(source) != size:
            Error(ValueError: "weights and population lengths differ")
        end
        for value in source:
            weight = _finite(value)
            if weight < 0.0:
                Error(ValueError: "weights must be non-negative")
            end
            if cumulative != None:
                if weight < total:
                    Error(ValueError: "cum_weights must be nondecreasing")
                end
                total = weight
            else:
                total += weight
            end
            call sums.append(total)
        end
        if total <= 0.0 or total == 1.0 / 0.0:
            Error(ValueError: "total weight must be positive and finite")
        end
    elif size == 0 and count > 0:
        Error(IndexError: "cannot choose from an empty sequence")
    end
    result = []
    for i in rang(count):
        index = 0
        if weights == None and cumulative == None:
            index = Int(_unit(state) * Float(size))
        else:
            index = _search(sums, _unit(state) * total)
        end
        call result.append(population[index])
    end
    return result
end

function _sample(state, population, k, counts):
    call _sequence(population, False)
    count = _integer(k)
    size = len(population)
    cumulative = IntArray()
    if counts != None:
        call _sequence(counts, False)
        if len(counts) != size:
            Error(ValueError: "counts and population lengths differ")
        end
        size = 0
        for item in counts:
            number = _integer(item)
            if number < 0 or number > 9223372036854775807 - size:
                Error(ValueError: "counts must be non-negative with an Int64 total")
            end
            size += number
            call cumulative.append(size)
        end
    end
    if count < 0 or count > size or count > 1048576:
        Error(ValueError: "sample k exceeds population or work limit")
    end
    # Virtual Fisher-Yates pool: O(k) storage even for large multiplicities.
    moved = {}
    result = []
    for i in rang(count):
        selected = _below(state, size - i)
        index = Int(moved.get(selected, selected))
        moved[selected] = moved.get(size - i - 1, size - i - 1)
        if counts != None:
            index = _search(cumulative, index)
        end
        call result.append(population[index])
    end
    return result
end

function _normal(state):
    # Kinderman-Monahan ratio-of-uniforms rejection.
    while True:
        u = _unit(state)
        v = 1.0 - _unit(state)
        z = 1.7155277699214135 * (u - 0.5) / v
        if z * z / 4.0 <= -math.log(v):
            return z
        end
    end
end

function _gauss(state):
    cached = state["gauss"]
    state["gauss"] = None
    if cached != None:
        return Float(cached)
    end
    angle = _unit(state) * math.TAU
    radius = sqrt(-2.0 * math.log(1.0 - _unit(state)))
    state["gauss"] = math.sin(angle) * radius
    return math.cos(angle) * radius
end

function _gamma(state, alpha):
    # Marsaglia-Tsang, with the standard shape-boost for alpha < 1.
    if alpha < 1.0:
        boosted = _gamma(state, alpha + 1.0)
        return boosted * _positive_power(1.0 - _unit(state), 1.0 / alpha)
    end
    d = alpha - 1.0 / 3.0
    c = 1.0 / sqrt(9.0 * d)
    while True:
        x = _normal(state)
        v = 1.0 + c * x
        if v <= 0.0:
            continue
        end
        v = v * v * v
        u = 1.0 - _unit(state)
        if u < 1.0 - 0.0331 * x * x * x * x or math.log(u) < 0.5 * x * x + d * (1.0 - v + math.log(v)):
            return d * v
        end
    end
end

function _positive_power(base, exponent):
    if base == 0.0 and exponent > 0.0:
        return 0.0
    end
    return math.exp(math.log(base) * exponent)
end

function _acos(value):
    # Monotone inverse, avoiding a dependency on platform libm.
    low = 0.0
    high = math.PI
    for i in rang(54):
        mid = (low + high) / 2.0
        if math.cos(mid) > value:
            low = mid
        else:
            high = mid
        end
    end
    return (low + high) / 2.0
end

function _vonmises(state, mu, kappa):
    if kappa <= 1e-6:
        return math.TAU * _unit(state)
    elif kappa > 1e12:
        Error(ValueError: "vonmisesvariate kappa exceeds numerical limit 1e12")
    end
    s = 0.5 / kappa
    r = s + sqrt(1.0 + s * s)
    while True:
        z = math.cos(math.PI * _unit(state))
        d = z / (r + z)
        u = _unit(state)
        if u < 1.0 - d * d or u <= (1.0 - d) * math.exp(d):
            break
        end
    end
    q = 1.0 / r
    angle = _acos(math.clamp((q + z) / (1.0 + q * z), -1.0, 1.0))
    if _unit(state) < 0.5:
        angle = -angle
    end
    return (mu + angle) % math.TAU
end

function _operate(state, operation, args):
    if operation == "seed":
        return _seed(state, args[0], args[1])
    elif operation == "getstate":
        return _getstate(state)
    elif operation == "setstate":
        return _setstate(state, args[0])
    elif operation == "random":
        return _unit(state)
    elif operation == "getrandbits":
        return _getbits(state, args[0])
    elif operation == "randbytes":
        return _bytes(state, args[0])
    elif operation == "randrange":
        return _range(state, args[0], args[1], args[2])
    elif operation == "randint":
        if type(args[0]) == "Instance" or type(args[1]) == "Instance" or type(args[0]) == "Dictionary" or type(args[1]) == "Dictionary":
            return _big_range(state, args[0], args[1], 1, True)
        end
        integer_low = _integer(args[0])
        integer_high = _integer(args[1])
        if integer_high < integer_low:
            Error(ValueError: "empty range for randint")
        end
        span = integer_high - integer_low
        if span < 0 or span == 9223372036854775807:
            return bigint.BigInt(_big_range(state, integer_low, integer_high, 1, True)).to_int()
        end
        return integer_low + _below(state, span + 1)
    elif operation == "choice":
        population = args[0]
        call _sequence(population, False)
        if len(population) == 0:
            Error(IndexError: "cannot choose from an empty sequence")
        end
        return population[_below(state, len(population))]
    elif operation == "choices":
        return _choices(state, args[0], args[1], args[2], args[3])
    elif operation == "sample":
        return _sample(state, args[0], args[1], args[2])
    elif operation == "shuffle":
        population = args[0]
        call _sequence(population, True)
        for i in rang(len(population) - 1, 0, -1):
            j = _below(state, i + 1)
            value = population[i]
            population[i] = population[j]
            population[j] = value
        end
        return None
    end
    a = _finite(args[0])
    if operation == "expovariate":
        if a == 0.0:
            Error(ValueError: "expovariate lambda must not be zero")
        end
        return -math.log(1.0 - _unit(state)) / a
    elif operation == "paretovariate":
        if a <= 0.0:
            Error(ValueError: "paretovariate alpha must be positive")
        end
        return _positive_power(1.0 - _unit(state), -1.0 / a)
    end
    b = _finite(args[1])
    if operation == "uniform":
        return a + (b - a) * _unit(state)
    elif operation == "triangular":
        if a == b:
            return a
        end
        c = 0.5
        if args[2] != None:
            c = (_finite(args[2]) - a) / (b - a)
        end
        if c < 0.0 or c > 1.0:
            Error(ValueError: "triangular mode must lie between low and high")
        end
        u = _unit(state)
        if u > c:
            return b + (a - b) * sqrt((1.0 - u) * (1.0 - c))
        end
        return a + (b - a) * sqrt(u * c)
    elif operation == "gauss":
        return a + b * _gauss(state)
    elif operation == "normalvariate":
        return a + b * _normal(state)
    elif operation == "lognormvariate":
        return math.exp(a + b * _normal(state))
    elif operation == "gammavariate" or operation == "betavariate" or operation == "weibullvariate":
        if a <= 0.0 or b <= 0.0:
            Error(ValueError: "distribution parameters must be positive")
        end
        if operation == "gammavariate":
            return _gamma(state, a) * b
        elif operation == "weibullvariate":
            return a * _positive_power(-math.log(1.0 - _unit(state)), 1.0 / b)
        end
        x = _gamma(state, a)
        if x == 0.0:
            return 0.0
        end
        y = _gamma(state, b)
        if x > y:
            return 1.0 / (1.0 + y / x)
        end
        return (x / y) / (1.0 + x / y)
    elif operation == "vonmisesvariate":
        return _vonmises(state, a, b)
    elif operation == "binomialvariate":
        n = _integer(args[0])
        if n < 0 or n > 1048576 or b < 0.0 or b > 1.0:
            Error(ValueError: "binomialvariate requires n in 0..1048576 and p in [0,1]")
        end
        if b == 0.0:
            return 0
        elif b == 1.0:
            return n
        end
        successes = 0
        for i in rang(n):
            if _unit(state) < b:
                successes += 1
            end
        end
        return successes
    end
    Error(ValueError: "unknown random operation")
end

function _call(state, operation, args):
    # One lock covers a whole public call, including the Gaussian cache and
    # seed/state transactions. Internal helpers never re-enter this lock.
    lock = IntArray(state["lock"])
    while atomic_cas(lock, 0, 0, 1) != 0:
        call atomic_pause()
    end
    failure = ""
    result = None
    try:
        result = _operate(state, operation, args)
    else:
        failure = last_error()
    end
    call atomic_xchg(lock, 0, 0)
    if failure != "":
        Error(RandomError: failure)
    end
    return result
end

_state = _new(None, False)

class Random(True):
    ctype Public

    function init(self, x=None):
        self.state = _new(x, False)
    end

    function seed(self, a=None, version=2):
        return _call(self.state, "seed", [a, version])
    end

    function getstate(self):
        return _call(self.state, "getstate", [])
    end

    function setstate(self, state):
        return _call(self.state, "setstate", [state])
    end

    function random(self):
        return Float(_call(self.state, "random", []))
    end

    function getrandbits(self, k):
        return _call(self.state, "getrandbits", [k])
    end

    function randbytes(self, n):
        return ByteArray(_call(self.state, "randbytes", [n]))
    end

    function randrange(self, start, stop=None, step=1):
        return _call(self.state, "randrange", [start, stop, step])
    end

    function randint(self, a, b):
        return _call(self.state, "randint", [a, b])
    end

    function choice(self, seq):
        return _call(self.state, "choice", [seq])
    end

    function choices(self, population, weights=None, cum_weights=None, k=1):
        return List(_call(self.state, "choices", [population, weights, cum_weights, k]))
    end

    function sample(self, population, k, counts=None):
        return List(_call(self.state, "sample", [population, k, counts]))
    end

    function shuffle(self, x):
        return _call(self.state, "shuffle", [x])
    end

    function uniform(self, a, b):
        return Float(_call(self.state, "uniform", [a, b]))
    end

    function triangular(self, low=0.0, high=1.0, mode=None):
        return Float(_call(self.state, "triangular", [low, high, mode]))
    end

    function gauss(self, mu=0.0, sigma=1.0):
        return Float(_call(self.state, "gauss", [mu, sigma]))
    end

    function normalvariate(self, mu=0.0, sigma=1.0):
        return Float(_call(self.state, "normalvariate", [mu, sigma]))
    end

    function lognormvariate(self, mu, sigma):
        return Float(_call(self.state, "lognormvariate", [mu, sigma]))
    end

    function expovariate(self, lambd=1.0):
        return Float(_call(self.state, "expovariate", [lambd]))
    end

    function gammavariate(self, alpha, beta):
        return Float(_call(self.state, "gammavariate", [alpha, beta]))
    end

    function betavariate(self, alpha, beta):
        return Float(_call(self.state, "betavariate", [alpha, beta]))
    end

    function vonmisesvariate(self, mu, kappa):
        return Float(_call(self.state, "vonmisesvariate", [mu, kappa]))
    end

    function paretovariate(self, alpha):
        return Float(_call(self.state, "paretovariate", [alpha]))
    end

    function weibullvariate(self, alpha, beta):
        return Float(_call(self.state, "weibullvariate", [alpha, beta]))
    end

    function binomialvariate(self, n=1, p=0.5):
        return Int(_call(self.state, "binomialvariate", [n, p]))
    end
end

class SystemRandom(Random):
    ctype Public

    function init(self, x=None):
        self.state = _new(None, True)
    end
end

function seed(a=None, version=2):
    return _call(_state, "seed", [a, version])
end

function getstate():
    return _call(_state, "getstate", [])
end

function setstate(state):
    return _call(_state, "setstate", [state])
end

function random():
    return Float(_call(_state, "random", []))
end

function getrandbits(k):
    return _call(_state, "getrandbits", [k])
end

function randbytes(n):
    return ByteArray(_call(_state, "randbytes", [n]))
end

function randrange(start, stop=None, step=1):
    return _call(_state, "randrange", [start, stop, step])
end

function randint(a, b):
    return _call(_state, "randint", [a, b])
end

function choice(seq):
    return _call(_state, "choice", [seq])
end

function choices(population, weights=None, cum_weights=None, k=1):
    return List(_call(_state, "choices", [population, weights, cum_weights, k]))
end

function sample(population, k, counts=None):
    return List(_call(_state, "sample", [population, k, counts]))
end

function shuffle(x):
    return _call(_state, "shuffle", [x])
end

function uniform(a, b):
    return Float(_call(_state, "uniform", [a, b]))
end

function triangular(low=0.0, high=1.0, mode=None):
    return Float(_call(_state, "triangular", [low, high, mode]))
end

function gauss(mu=0.0, sigma=1.0):
    return Float(_call(_state, "gauss", [mu, sigma]))
end

function normalvariate(mu=0.0, sigma=1.0):
    return Float(_call(_state, "normalvariate", [mu, sigma]))
end

function lognormvariate(mu, sigma):
    return Float(_call(_state, "lognormvariate", [mu, sigma]))
end

function expovariate(lambd=1.0):
    return Float(_call(_state, "expovariate", [lambd]))
end

function gammavariate(alpha, beta):
    return Float(_call(_state, "gammavariate", [alpha, beta]))
end

function betavariate(alpha, beta):
    return Float(_call(_state, "betavariate", [alpha, beta]))
end

function vonmisesvariate(mu, kappa):
    return Float(_call(_state, "vonmisesvariate", [mu, kappa]))
end

function paretovariate(alpha):
    return Float(_call(_state, "paretovariate", [alpha]))
end

function weibullvariate(alpha, beta):
    return Float(_call(_state, "weibullvariate", [alpha, beta]))
end

function binomialvariate(n=1, p=0.5):
    return Int(_call(_state, "binomialvariate", [n, p]))
end
