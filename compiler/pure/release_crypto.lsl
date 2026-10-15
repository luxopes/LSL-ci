# Kryptografie pro ověření vydání bez systémových nástrojů (Windows, macOS):
# SHA-256 (FIPS 180-4) a ověření podpisu Ed25519 (RFC 8032, aritmetika
# podle TweetNaCl: prvek tělesa = 16 limbů po 16 bitech v IntArray).
# Jen ověřování veřejných dat; nic tajného se tu nepočítá, takže konstantní
# čas není potřeba.
load _random_hash as sha512

SHA256_K = [0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
            0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
            0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
            0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
            0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
            0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
            0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
            0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2]
HEX = "0123456789abcdef"

function int_array(values):
    result = __lsl_int_zeros(len(values))
    for i in rang(len(values)):
        result[i] = __lsl_typed_int(values[i])
    end
    return result
end

# SHA-256 souboru v paměti jako 64 malých hex číslic. Bloky se zpracují
# přímo v této funkci: s lokálně typovanými hodnotami je smyčka asi 60x
# rychlejší než přes pomocnou funkci s parametry typu Any.
function sha256_hex(bytes):
    data = ByteArray(bytes)
    total = len(data)
    rest = total % 64
    full = total - rest
    tail_size = 64
    if rest >= 56:
        tail_size = 128
    end
    tail = __lsl_byte_zeros(tail_size)
    if rest > 0:
        call __lsl_byte_copy(tail, data, 0, full, rest)
    end
    tail[rest] = 128
    bits = total * 8
    for i in rang(8):
        tail[tail_size - 1 - i] = (bits >> (8 * i)) & 255
    end
    k = int_array(SHA256_K)
    state = int_array([0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a, 0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19])
    w = __lsl_int_zeros(64)
    block = data
    limit = full
    offset = 0
    phase = 0
    while phase < 2:
        if phase == 1:
            block = tail
            limit = tail_size
            offset = 0
        end
        while offset < limit:
            i = 0
            while i < 16:
                p = offset + i * 4
                w[i] = (block[p] << 24) | (block[p + 1] << 16) | (block[p + 2] << 8) | block[p + 3]
                i += 1
            end
            while i < 64:
                x = w[i - 15]
                y = w[i - 2]
                s0 = ((x >> 7) | (x << 25)) ~ ((x >> 18) | (x << 14)) ~ (x >> 3)
                s1 = ((y >> 17) | (y << 15)) ~ ((y >> 19) | (y << 13)) ~ (y >> 10)
                w[i] = (w[i - 16] + s0 + w[i - 7] + s1) & 0xFFFFFFFF
                i += 1
            end
            a = state[0]
            b = state[1]
            c = state[2]
            d = state[3]
            e = state[4]
            f = state[5]
            g = state[6]
            h = state[7]
            i = 0
            while i < 64:
                t1 = (h + ((((e >> 6) | (e << 26)) ~ ((e >> 11) | (e << 21)) ~ ((e >> 25) | (e << 7))) & 0xFFFFFFFF) + ((e & f) ~ ((0xFFFFFFFF ~ e) & g)) + k[i] + w[i]) & 0xFFFFFFFF
                t2 = (((((a >> 2) | (a << 30)) ~ ((a >> 13) | (a << 19)) ~ ((a >> 22) | (a << 10))) & 0xFFFFFFFF) + ((a & b) ~ (a & c) ~ (b & c))) & 0xFFFFFFFF
                h = g
                g = f
                f = e
                e = (d + t1) & 0xFFFFFFFF
                d = c
                c = b
                b = a
                a = (t1 + t2) & 0xFFFFFFFF
                i += 1
            end
            state[0] = (state[0] + a) & 0xFFFFFFFF
            state[1] = (state[1] + b) & 0xFFFFFFFF
            state[2] = (state[2] + c) & 0xFFFFFFFF
            state[3] = (state[3] + d) & 0xFFFFFFFF
            state[4] = (state[4] + e) & 0xFFFFFFFF
            state[5] = (state[5] + f) & 0xFFFFFFFF
            state[6] = (state[6] + g) & 0xFFFFFFFF
            state[7] = (state[7] + h) & 0xFFFFFFFF
            offset += 64
        end
        phase += 1
    end
    result = ""
    for i in rang(8):
        for shift in [28, 24, 20, 16, 12, 8, 4, 0]:
            result += HEX[(state[i] >> shift) & 15]
        end
    end
    return result
end

# Hex (malá písmena, sudá délka) -> ByteArray; jinak None.
function hex_bytes(text):
    value = String(text)
    if len(value) % 2 != 0:
        return None
    end
    result = __lsl_byte_zeros(len(value) // 2)
    for i in rang(len(result)):
        high = HEX.find(value[2 * i])
        low = HEX.find(value[2 * i + 1])
        if high < 0 or low < 0:
            return None
        end
        result[i] = high * 16 + low
    end
    return result
end

# --- Ed25519: těleso GF(2^255 - 19) ---

function gf():
    return __lsl_int_zeros(16)
end

function gf_copy(source):
    result = __lsl_int_zeros(16)
    for i in rang(16):
        result[i] = source[i]
    end
    return result
end

function set25519(target, source):
    for i in rang(16):
        target[i] = source[i]
    end
end

GF0 = gf()
GF1 = int_array([1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0])
CURVE_D = int_array([0x78a3, 0x1359, 0x4dca, 0x75eb, 0xd8ab, 0x4141, 0x0a4d, 0x0070, 0xe898, 0x7779, 0x4079, 0x8cc7, 0xfe73, 0x2b6f, 0x6cee, 0x5203])
CURVE_D2 = int_array([0xf159, 0x26b2, 0x9b94, 0xebd6, 0xb156, 0x8283, 0x149a, 0x00e0, 0xd130, 0xeef3, 0x80f2, 0x198e, 0xfce7, 0x56df, 0xd9dc, 0x2406])
BASE_X = int_array([0xd51a, 0x8f25, 0x2d60, 0xc956, 0xa7b2, 0x9525, 0xc760, 0x692c, 0xdc5c, 0xfdd6, 0xe231, 0xc0a4, 0x53fe, 0xcd6e, 0x36d3, 0x2169])
BASE_Y = int_array([0x6658, 0x6666, 0x6666, 0x6666, 0x6666, 0x6666, 0x6666, 0x6666, 0x6666, 0x6666, 0x6666, 0x6666, 0x6666, 0x6666, 0x6666, 0x6666])
SQRT_M1 = int_array([0xa0b0, 0x4a0e, 0x1b27, 0xc4ee, 0xe478, 0xad2f, 0x1806, 0x2f43, 0xd7a7, 0x3dfb, 0x0099, 0x2b4d, 0xdf0b, 0x4fc1, 0x2480, 0x2b83])
# Řád podgrupy L v little-endian bajtech.
ORDER = int_array([0xed, 0xd3, 0xf5, 0x5c, 0x1a, 0x63, 0x12, 0x58, 0xd6, 0x9c, 0xf7, 0xa2, 0xde, 0xf9, 0xde, 0x14, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0x10])

function car25519(o):
    for i in rang(16):
        o[i] += 65536
        c = o[i] >> 16
        if i < 15:
            o[i + 1] += c - 1
        else:
            o[0] += 38 * (c - 1)
        end
        o[i] -= c << 16
    end
end

function sel25519(p, q, b):
    c = ~(b - 1)
    for i in rang(16):
        t = c & (p[i] ~ q[i])
        p[i] = p[i] ~ t
        q[i] = q[i] ~ t
    end
end

function pack25519(o, n):
    t = gf_copy(n)
    m = gf()
    call car25519(t)
    call car25519(t)
    call car25519(t)
    for j in rang(2):
        m[0] = t[0] - 0xffed
        for i in rang(1, 15):
            m[i] = t[i] - 0xffff - ((m[i - 1] >> 16) & 1)
            m[i - 1] = m[i - 1] & 0xffff
        end
        m[15] = t[15] - 0x7fff - ((m[14] >> 16) & 1)
        b = (m[15] >> 16) & 1
        m[14] = m[14] & 0xffff
        call sel25519(t, m, 1 - b)
    end
    for i in rang(16):
        o[2 * i] = t[i] & 255
        o[2 * i + 1] = (t[i] >> 8) & 255
    end
end

function neq25519(a, b):
    c = __lsl_byte_zeros(32)
    d = __lsl_byte_zeros(32)
    call pack25519(c, a)
    call pack25519(d, b)
    for i in rang(32):
        if c[i] != d[i]:
            return True
        end
    end
    return False
end

function par25519(a):
    d = __lsl_byte_zeros(32)
    call pack25519(d, a)
    return d[0] & 1
end

function unpack25519(o, n):
    for i in rang(16):
        o[i] = n[2 * i] + (n[2 * i + 1] << 8)
    end
    o[15] = o[15] & 0x7fff
end

function fadd(o, a, b):
    for i in rang(16):
        o[i] = a[i] + b[i]
    end
end

function fsub(o, a, b):
    for i in rang(16):
        o[i] = a[i] - b[i]
    end
end

function fmul(o, a, b):
    t = __lsl_int_zeros(31)
    x = IntArray(a)
    y = IntArray(b)
    i = 0
    while i < 16:
        v = x[i]
        j = 0
        while j < 16:
            t[i + j] += v * y[j]
            j += 1
        end
        i += 1
    end
    i = 0
    while i < 15:
        t[i] += 38 * t[i + 16]
        i += 1
    end
    for i in rang(16):
        o[i] = t[i]
    end
    call car25519(o)
    call car25519(o)
end

function fsquare(o, a):
    call fmul(o, a, a)
end

function inv25519(o, value):
    c = gf_copy(value)
    a = 253
    while a >= 0:
        call fsquare(c, c)
        if a != 2 and a != 4:
            call fmul(c, c, value)
        end
        a -= 1
    end
    call set25519(o, c)
end

function pow2523(o, value):
    c = gf_copy(value)
    a = 250
    while a >= 0:
        call fsquare(c, c)
        if a != 1:
            call fmul(c, c, value)
        end
        a -= 1
    end
    call set25519(o, c)
end

# --- body křivky v rozšířených souřadnicích [X, Y, Z, T] ---

function point():
    return [gf(), gf(), gf(), gf()]
end

function point_add(p, q):
    a = gf()
    b = gf()
    c = gf()
    d = gf()
    t = gf()
    e = gf()
    f = gf()
    g = gf()
    h = gf()
    call fsub(a, p[1], p[0])
    call fsub(t, q[1], q[0])
    call fmul(a, a, t)
    call fadd(b, p[0], p[1])
    call fadd(t, q[0], q[1])
    call fmul(b, b, t)
    call fmul(c, p[3], q[3])
    call fmul(c, c, CURVE_D2)
    call fmul(d, p[2], q[2])
    call fadd(d, d, d)
    call fsub(e, b, a)
    call fsub(f, d, c)
    call fadd(g, d, c)
    call fadd(h, b, a)
    call fmul(p[0], e, f)
    call fmul(p[1], h, g)
    call fmul(p[2], g, f)
    call fmul(p[3], e, h)
end

function cswap(p, q, b):
    for i in rang(4):
        call sel25519(p[i], q[i], b)
    end
end

function pack_point(r, p):
    tx = gf()
    ty = gf()
    zi = gf()
    call inv25519(zi, p[2])
    call fmul(tx, p[0], zi)
    call fmul(ty, p[1], zi)
    call pack25519(r, ty)
    r[31] = r[31] ~ (par25519(tx) << 7)
end

function scalarmult(p, q, s):
    call set25519(p[0], GF0)
    call set25519(p[1], GF1)
    call set25519(p[2], GF1)
    call set25519(p[3], GF0)
    i = 255
    while i >= 0:
        b = (s[i // 8] >> (i & 7)) & 1
        call cswap(p, q, b)
        call point_add(q, p)
        call point_add(p, p)
        call cswap(p, q, b)
        i -= 1
    end
end

function scalarbase(p, s):
    q = point()
    call set25519(q[0], BASE_X)
    call set25519(q[1], BASE_Y)
    call set25519(q[2], GF1)
    call fmul(q[3], BASE_X, BASE_Y)
    call scalarmult(p, q, s)
end

# Redukce 64bajtového čísla (little-endian) modulo L do 32 bajtů r.
function mod_order(r, x):
    i = 63
    while i >= 32:
        carry = 0
        j = i - 32
        while j < i - 12:
            x[j] += carry - 16 * x[i] * ORDER[j - (i - 32)]
            carry = (x[j] + 128) >> 8
            x[j] -= carry << 8
            j += 1
        end
        x[j] += carry
        x[i] = 0
        i -= 1
    end
    carry = 0
    for j in rang(32):
        x[j] += carry - (x[31] >> 4) * ORDER[j]
        carry = x[j] >> 8
        x[j] = x[j] & 255
    end
    for j in rang(32):
        x[j] -= carry * ORDER[j]
    end
    for i in rang(32):
        x[i + 1] += x[i] >> 8
        r[i] = x[i] & 255
    end
end

function reduce_hash(digest):
    x = __lsl_int_zeros(64)
    for i in rang(64):
        x[i] = digest[i]
    end
    r = __lsl_byte_zeros(32)
    call mod_order(r, x)
    return r
end

# Dekóduje veřejný klíč jako záporný bod -A; None pro neplatný bod.
function unpack_negative(key):
    r = point()
    t = gf()
    check = gf()
    num = gf()
    den = gf()
    den2 = gf()
    den4 = gf()
    den6 = gf()
    call set25519(r[2], GF1)
    call unpack25519(r[1], key)
    call fsquare(num, r[1])
    call fmul(den, num, CURVE_D)
    call fsub(num, num, r[2])
    call fadd(den, r[2], den)
    call fsquare(den2, den)
    call fsquare(den4, den2)
    call fmul(den6, den4, den2)
    call fmul(t, den6, num)
    call fmul(t, t, den)
    call pow2523(t, t)
    call fmul(t, t, num)
    call fmul(t, t, den)
    call fmul(t, t, den)
    call fmul(r[0], t, den)
    call fsquare(check, r[0])
    call fmul(check, check, den)
    if neq25519(check, num):
        call fmul(r[0], r[0], SQRT_M1)
    end
    call fsquare(check, r[0])
    call fmul(check, check, den)
    if neq25519(check, num):
        return None
    end
    if par25519(r[0]) == (key[31] >> 7):
        call fsub(r[0], GF0, r[0])
    end
    call fmul(r[3], r[0], r[1])
    return r
end

# S musí být kanonické (S < L), jinak by šlo podpis pozměnit.
function canonical_scalar(signature):
    i = 31
    while i >= 0:
        if signature[32 + i] < ORDER[i]:
            return True
        elif signature[32 + i] > ORDER[i]:
            return False
        end
        i -= 1
    end
    return False
end

# Ověří podpis Ed25519 (64 bajtů) zprávy message (ByteArray) veřejným
# klíčem key (32 bajtů). Vrací True/False, nikdy nevyhazuje kvůli datům.
function ed25519_verify(signature, message, key):
    if type(signature) != "ByteArray" or type(message) != "ByteArray" or type(key) != "ByteArray":
        return False
    end
    if len(signature) != 64 or len(key) != 32 or not canonical_scalar(signature):
        return False
    end
    q = unpack_negative(key)
    if q == None:
        return False
    end
    if len(message) > 1048576 - 64:
        return False
    end
    hashed = __lsl_byte_zeros(64 + len(message))
    call __lsl_byte_copy(hashed, signature, 0, 0, 32)
    call __lsl_byte_copy(hashed, key, 32, 0, 32)
    if len(message) > 0:
        call __lsl_byte_copy(hashed, message, 64, 0, len(message))
    end
    h = reduce_hash(sha512.digest(hashed))
    p = point()
    call scalarmult(p, q, h)
    s = __lsl_byte_zeros(32)
    call __lsl_byte_copy(s, signature, 0, 32, 32)
    base = point()
    call scalarbase(base, s)
    call point_add(p, base)
    packed = __lsl_byte_zeros(32)
    call pack_point(packed, p)
    for i in rang(32):
        if packed[i] != signature[i]:
            return False
        end
    end
    return True
end
