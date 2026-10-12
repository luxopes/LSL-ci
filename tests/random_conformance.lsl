load random
load bigint
load _random_hash

function require(condition, message):
    if not condition:
        Error(TestFailure: message)
    end
end

function hex(data):
    alphabet = "0123456789abcdef"
    result = ""
    for value in data:
        result += alphabet[Int(value) >> 4] + alphabet[Int(value) & 15]
    end
    return result
end

# Published SHA-512 and CPython MT19937 reference vectors. No Python process.
call require(hex(_random_hash.digest(ByteArray())) == "cf83e1357eefb8bdf1542850d66d8007d620e4050b5715dc83f4a921d36ce9ce47d0d13c5d85f2b0ff8318d2877eec2f63b931bd47417a81a538327af927da3e", "SHA512 empty seed")
abc = ByteArray()
for value in [97, 98, 99]:
    call abc.append(Int(value))
end
call require(hex(_random_hash.digest(abc)) == "ddaf35a193617abacc417349ae20413112e6fa4e89a97ea20a9eeee64b55d39a2192992a274fc1a836ba3c23a3feebbd454d4423643ce80e2a9ac94fa54ca49f", "SHA512 abc")
r = random.Random(42)
for expected in [0.6394267984578837, 0.025010755222666936, 0.27502931836911926, 0.22321073814882275, 0.7364712141640124]:
    call require(abs(r.random() - Float(expected)) < 2e-16, "CPython seed 42")
end
call r.seed(0)
call require(r.random() == 0.8444218515250481, "CPython seed zero")
call r.seed(1234567)
call require(bigint.BigInt(r.getrandbits(100)).text() == "97904845777343510404718956115", "CPython 100-bit vector")
call r.seed(1234567)
call require(bigint.BigInt(r.randrange(bigint.BigInt(2).power(99))).text() == "97904845777343510404718956115", "BigInt randrange vector")
call require(bigint.BigInt(r.randint(bigint.BigInt(-4), bigint.BigInt(-4))).equals(-4), "BigInt inclusive singleton")

other = random.Random(-42)
call r.seed(42)
for i in rang(700):
    call require(r.getrandbits(32) == other.getrandbits(32), "negative seed and MT twist boundary")
end
for seed in [0, 1, -1, 9223372036854775807, -9223372036854775808, "", "abc", "žluťoučký 🦊", abc, 0.0, -0.0, 0.5, -3.125, 1e100]:
    call r.seed(seed)
    call other.seed(seed)
    call require(r.getstate() == other.getstate(), "seed reproducibility")
    call require(r.random() == other.random(), "independent generators")
end
call r.seed("abc")
call other.seed(abc)
call require(r.getstate() == other.getstate(), "UTF8 seed equals bytes")
call r.seed(17.0)
call other.seed(17)
call require(r.getstate() == other.getstate(), "finite Float hash seed")
call r.seed("legacy", version=1)
call other.seed("legacy", version=1)
call require(r.getstate() == other.getstate(), "legacy seed")

call r.seed(42)
saved = r.getstate()
call require(r.getrandbits(0) == 0 and r.getstate() == saved, "zero bits consumes no state")
call require(len(r.randbytes(0)) == 0 and r.getstate() == saved, "zero bytes consumes no state")
for bits in [1, 7, 8, 31, 32, 33, 53, 62, 63]:
    value = r.getrandbits(bits)
    call require(type(value) == "Int" and value >= 0, "Int bit range")
    call require(bigint.BigInt(value).compare(bigint.BigInt(2).power(bits)) < 0, "getrandbits upper bound")
end
for bits in [64, 65, 100, 129, 512]:
    big_value = bigint.BigInt(r.getrandbits(bits))
    call require(big_value.compare(0) >= 0 and big_value.compare(bigint.BigInt(2).power(bits)) < 0, "BigInt bit range")
end
call r.seed(42)
call other.seed(42)
bytes = r.randbytes(7)
word1 = Int(other.getrandbits(32))
word2 = Int(other.getrandbits(24))
call require(len(bytes) == 7, "randbytes size")
for i in rang(4):
    call require(bytes[i] == ((word1 >> (8 * i)) & 255), "randbytes little endian")
end
for i in rang(3):
    call require(bytes[i + 4] == ((word2 >> (8 * i)) & 255), "randbytes partial word")
end

call r.gauss()
saved = r.getstate()
first = r.gauss()
following = r.random()
call r.setstate(saved)
call require(first == r.gauss() and following == r.random(), "state includes Gaussian cache")
call require(saved == saved, "immutable state snapshot")
call require(r.randrange(1) == 0 and r.randint(4, 4) == 4, "singleton bounds")
call require(r.randint(9223372036854775807, 9223372036854775807) == 9223372036854775807, "max Int singleton")
call require(r.randrange(-9223372036854775808, 9223372036854775807) < 9223372036854775807, "full Int64 span")
call require(type(r.randint(-9223372036854775808, 9223372036854775807)) == "Int", "full Int64 randint")
for i in rang(500):
    x = r.randrange(10, -10, -3)
    call require(x <= 10 and x > -10 and (10 - x) % 3 == 0, "negative stride")
    y = r.randint(-5, 5)
    call require(y >= -5 and y <= 5, "inclusive randint")
end
call require(r.choice("🦊") == "🦊", "Unicode choice")
call require(r.choices(["zero", "yes"], weights=[0, 1], k=8) == ["yes" for i in rang(8)], "weighted choice")
call require(r.choices([1, 2, 3], cum_weights=[0, 0, 4], k=5) == [3, 3, 3, 3, 3], "cumulative choice")
call require(r.choices([], k=0) == [], "empty zero choices")
population = [1, 2, 3, 4, 5]
shuffled = population.copy()
call require(r.shuffle(shuffled) == None, "shuffle return")
call shuffled.sort()
call require(shuffled == population, "shuffle is permutation")
sampled = r.sample(population, 5)
call sampled.sort()
call require(sampled == population, "sample without replacement")
sampled = r.sample(["a", "b", "zero"], 5, counts=[2, 3, 0])
call require(sampled.count("a") == 2 and sampled.count("b") == 3 and "zero" not in sampled, "sample multiplicities")
call require(r.sample([], 0, counts=[]) == [], "empty sample")
call require(population == [1, 2, 3, 4, 5], "sample leaves input alone")
array = float_zeros(4)
for i in rang(4):
    array[i] = Float(i)
end
call r.shuffle(array)
call require(float_sum(array) == 6.0, "typed array shuffle")

call require(r.uniform(2, 2) == 2.0 and r.triangular(3, 3) == 3.0, "degenerate distributions")
call require(r.gauss(mu=5, sigma=0) == 5.0 and r.normalvariate(7, 0) == 7.0, "Gaussian parameters")
call require(r.binomialvariate(n=10, p=0) == 0 and r.binomialvariate(10, 1) == 10, "binomial endpoints")
sum_uniform = 0.0
sum_normal = 0.0
sum_gamma = 0.0
call r.seed(713)
for i in rang(2000):
    sum_uniform += r.random()
    sum_normal += r.normalvariate()
    sum_gamma += r.gammavariate(2, 3)
    beta = r.betavariate(0.5, 2)
    call require(beta >= 0.0 and beta <= 1.0, "beta range")
    call require(r.expovariate() >= 0.0 and r.expovariate(-2) <= 0.0, "exponential sign")
    call require(r.paretovariate(2) >= 1.0 and r.weibullvariate(2, 3) >= 0.0, "positive distributions")
    call require(r.lognormvariate(0, 1) > 0.0, "lognormal")
    call require(r.triangular() >= 0.0 and r.triangular() <= 1.0, "triangular bounds")
    if i % 200 == 0:
        call gc()
    end
end
call require(abs(sum_uniform / 2000.0 - 0.5) < 0.04, "uniform deterministic mean")
call require(abs(sum_normal / 2000.0) < 0.12, "normal deterministic mean")
call require(abs(sum_gamma / 2000.0 - 6.0) < 0.5, "gamma deterministic mean")
for concentration in [0, -1, 0.5, 2, 100]:
    angle = r.vonmisesvariate(1, concentration)
    call require(angle >= 0.0 and angle < 6.283185307179587, "von Mises angle")
end

for case in rang(20):
    failure = ""
    before = r.getstate()
    try:
        if case == 0:
            call r.randrange(0)
        elif case == 1:
            call r.randrange(1, 5, 0)
        elif case == 2:
            call r.randrange(1.5)
        elif case == 3:
            call r.randint(2, 1)
        elif case == 4:
            call r.choice([])
        elif case == 5:
            call r.getrandbits(-1)
        elif case == 6:
            call r.randbytes(1048577)
        elif case == 7:
            call r.choices([1, 2], weights=[0, 0])
        elif case == 8:
            call r.choices([1, 2], cum_weights=[2, 1])
        elif case == 9:
            call r.choices([1], weights=[1], cum_weights=[1])
        elif case == 10:
            call r.sample([1], 2)
        elif case == 11:
            call r.sample([1], 1, counts=[-1])
        elif case == 12:
            call r.shuffle("abc")
        elif case == 13:
            call r.seed([])
        elif case == 14:
            call r.setstate((3, (0,), None))
        elif case == 15:
            call r.expovariate(0)
        elif case == 16:
            call r.gammavariate(0, 1)
        elif case == 17:
            call r.binomialvariate(3, 1.1)
        elif case == 18:
            call r.choices([1], weights=[0.0 / 0.0])
        else:
            call r.triangular(0, 1, 2)
        end
    else:
        failure = last_error()
    end
    call require(failure != "", "invalid random input rejected")
    call require(r.getstate() == before, "validation leaves state unchanged and releases lock")
end
system = random.SystemRandom()
call require(len(system.randbytes(16)) == 16 and system.randrange(1) == 0, "OS random")
call system.seed("ignored")
for operation in [0, 1]:
    failure = ""
    try:
        if operation == 0:
            call system.getstate()
        else:
            call system.setstate(saved)
        end
    else:
        failure = last_error()
    end
    call require(failure.find("NotImplementedError") >= 0, "SystemRandom has no state")
end
call random.seed(42)
call require(abs(random.random() - 0.6394267984578837) < 2e-16, "module global generator")
call require(len(random.choices([1], k=2)) == 2, "module keyword defaults")
print "random conformance passed"
