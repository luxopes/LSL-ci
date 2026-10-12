# Pure-LSL mathematics and statistics helpers.
#
# Functions use Float64 unless their name explicitly says otherwise. For
# arbitrary-precision integer results, use factorial_big() or load bigint.

load bigint

PI = 3.141592653589793
TAU = 6.283185307179586
E = 2.718281828459045
LN2 = 0.6931471805599453
SQRT2 = 1.4142135623730951

function floor(value):
    if type(value) == "Int" or type(value) == "Bool":
        return Int(value)
    end
    number = Float(value)
    call check_integral(number)
    truncated = Int(number)
    if Float(truncated) > number:
        return truncated - 1
    end
    return truncated
end

function ceil(value):
    if type(value) == "Int" or type(value) == "Bool":
        return Int(value)
    end
    number = Float(value)
    call check_integral(number)
    truncated = Int(number)
    if Float(truncated) < number:
        return truncated + 1
    end
    return truncated
end

# Desetinný zápis Floatu podle nejkratšího String(x): [záporné, číslice, tečka],
# hodnota = 0.číslice × 10^tečka, číslice bez úvodních nul.
function decimal_parts(number):
    text = String(number)
    negative = text.startswith("-")
    if negative:
        text = text[1:len(text)]
    end
    exponent = 0
    marker = text.find("e")
    if marker >= 0:
        power = text[marker + 1:len(text)]
        if power.startswith("+"):
            power = power[1:len(power)]
        end
        exponent = Int(power)
        text = text[0:marker]
    end
    dot = text.find(".")
    whole = text
    fraction = ""
    if dot >= 0:
        whole = text[0:dot]
        fraction = text[dot + 1:len(text)]
    end
    digits = whole + fraction
    point = len(whole) + exponent
    while len(digits) > 1 and digits[0] == "0":
        digits = digits[1:len(digits)]
        point -= 1
    end
    return [negative, digits, point]
end

function check_digits(digits):
    if type(digits) != "Int":
        Error(TypeError: "digits must be Int, got " + type(digits))
    end
end

# Zaokrouhlení (round_half=True) nebo oseknutí na places desetinných míst.
function decimal_round(value, places, round_half):
    number = Float(value)
    if number != number or number - number != 0.0 or number == 0.0:
        return number
    end
    parts = decimal_parts(number)
    digits = parts[1]
    point = parts[2]
    # Meze před součtem: point je malé, places může být až Int.MIN/MAX.
    if places >= len(digits) - point:
        return number
    elif places < -point - 1:
        return 0.0
    end
    keep = point + places
    if keep >= len(digits):
        return number
    end
    kept = ""
    if keep > 0:
        kept = digits[0:keep]
    end
    if keep >= 0 and round_half and Int(digits[keep]) >= 5:
        carried = ""
        carry = True
        index = len(kept) - 1
        while index >= 0:
            digit = Int(kept[index])
            if carry:
                digit += 1
                carry = digit == 10
                if carry:
                    digit = 0
                end
            end
            carried = String(digit) + carried
            index -= 1
        end
        if carry:
            carried = "1" + carried
            point += 1
        end
        kept = carried
    end
    if kept == "" or kept.replace("0", "") == "":
        return 0.0
    end
    result = Float("0." + kept + "e" + String(point))
    if parts[0]:
        return -result
    end
    return result
end

# Int vstup: přesné zaokrouhlení na desítky, stovky… bez převodu na Float.
# Pracuje se zbytkem a posunem k nule, nikdy s abs/negací Int.MIN.
function integer_round(value, places, round_half):
    if places >= 0 or value == 0:
        return value
    elif places < -19:
        # |value| < 9.3e18 < 0.5·10^20: výsledek je vždy 0.
        return 0
    elif places == -19:
        # 10^19 se do Int nevejde; |value| < 10^19, takže výsledek je 0,
        # nebo ±10^19 (mimo rozsah Int) při zaokrouhlení poloviny od nuly.
        if round_half and (value >= 5000000000000000000 or value <= -5000000000000000000):
            Error(ValueError: "rounded value is outside the Int range")
        end
        return 0
    end
    unit = 1
    for step in rang(-places):
        unit *= 10
    end
    remainder = value % unit
    if value >= 0:
        toward_zero = value - remainder
        distance = remainder
    elif remainder == 0:
        toward_zero = value
        distance = 0
    else:
        toward_zero = value - remainder + unit
        distance = unit - remainder
    end
    if round_half and distance > 0 and distance >= unit - distance:
        if value >= 0:
            if toward_zero > 9223372036854775807 - unit:
                Error(ValueError: "rounded value is outside the Int range")
            end
            return toward_zero + unit
        end
        if toward_zero < -9223372036854775807 - 1 + unit:
            Error(ValueError: "rounded value is outside the Int range")
        end
        return toward_zero - unit
    end
    return toward_zero
end

# Převod Float na Int jen pro konečné hodnoty v rozsahu Int.
function check_integral(number):
    if number != number:
        Error(ValueError: "cannot convert NaN to Int")
    elif number - number != 0.0:
        Error(ValueError: "cannot convert Infinity to Int")
    elif number >= 9223372036854775807.0 or number < -9223372036854775808.0:
        Error(ValueError: "value is outside the Int range")
    end
end

function numeric_argument(value):
    if type(value) != "Int" and type(value) != "Float" and type(value) != "Bool":
        Error(TypeError: "value must be Int or Float, got " + type(value))
    end
end

# round(x) zaokrouhlí na Int (poloviny od nuly); round(x, digits) u Float
# vrací Float zaokrouhlený na digits desetinných míst (záporné digits:
# desítky, stovky…); Int zůstává Int.
function round(value, digits=None):
    call numeric_argument(value)
    if digits != None:
        call check_digits(digits)
        if type(value) != "Float":
            return integer_round(Int(value), digits, True)
        end
        return decimal_round(value, digits, True)
    end
    if type(value) != "Float":
        return Int(value)
    end
    number = Float(value)
    call check_integral(number)
    # Rozdíl od celé části je přesný; number + 0.5 by se mohlo zaokrouhlit
    # nahoru (0.49999999999999994 -> 1).
    if number >= 0.0:
        whole = floor(number)
        if number - Float(whole) >= 0.5:
            return whole + 1
        end
        return whole
    end
    whole = ceil(number)
    if Float(whole) - number >= 0.5:
        return whole - 1
    end
    return whole
end

# trunc(x) osekne směrem k nule na Int; trunc(x, digits) u Float vrací Float
# bez zaokrouhlení, oseknutý na digits desetinných míst; Int zůstává Int.
function trunc(value, digits=None):
    call numeric_argument(value)
    if digits != None:
        call check_digits(digits)
        if type(value) != "Float":
            return integer_round(Int(value), digits, False)
        end
        return decimal_round(value, digits, False)
    end
    if type(value) != "Float":
        return Int(value)
    end
    call check_integral(Float(value))
    return Int(Float(value))
end

function sign(value):
    if value < 0:
        return -1
    elif value > 0:
        return 1
    end
    return 0
end

function clamp(value, lower, upper):
    if lower > upper:
        Error(ValueError: "clamp lower bound exceeds upper bound")
    elif value < lower:
        return lower
    elif value > upper:
        return upper
    end
    return value
end

function lerp(start, stop, amount):
    return Float(start) + (Float(stop) - Float(start)) * Float(amount)
end

function degrees(radians_value):
    return Float(radians_value) * 180.0 / PI
end

function radians(degrees_value):
    return Float(degrees_value) * PI / 180.0
end

function gcd(left, right):
    a = Int(left)
    b = Int(right)
    minimum = -9223372036854775807 - 1
    # |Int.MIN| se do Int nevejde: gcd(Int.MIN, 0) a gcd(Int.MIN, Int.MIN)
    # by bylo 2^63; jinak se Int.MIN nejdřív zmenší zbytkem.
    if a == minimum or b == minimum:
        if (a == minimum and (b == 0 or b == minimum)) or (b == minimum and a == 0):
            Error(OverflowError: "gcd result does not fit in Int")
        end
        if a == minimum:
            a = a % abs(b)
        else:
            b = b % abs(a)
        end
    end
    a = abs(a)
    b = abs(b)
    while b != 0:
        remainder = a % b
        a = b
        b = remainder
    end
    return a
end

function lcm(left, right):
    a = Int(left)
    b = Int(right)
    if a == 0 or b == 0:
        return 0
    end
    minimum = -9223372036854775807 - 1
    if a == minimum or b == minimum:
        Error(OverflowError: "lcm result does not fit in Int")
    end
    a = abs(a)
    b = abs(b)
    reduced = a // gcd(a, b)
    if reduced > 9223372036854775807 // b:
        Error(OverflowError: "lcm result does not fit in Int")
    end
    return reduced * b
end

function factorial(value):
    number = Int(value)
    if number < 0:
        Error(ValueError: "factorial requires a non-negative Int")
    elif number > 20:
        Error(OverflowError: "factorial result does not fit in Int")
    end
    result = 1
    factor = 2
    while factor <= number:
        result *= factor
        factor += 1
    end
    return result
end

function factorial_big(value):
    number = Int(value)
    if number < 0:
        Error(ValueError: "factorial_big requires a non-negative Int")
    elif number > 10000:
        Error(ValueError: "factorial_big exceeds the secure work limit")
    end
    result = bigint.BigInt(1)
    factor = 2
    while factor <= number:
        result = result.multiply(factor)
        factor += 1
    end
    return result
end

# 2^power jako Float přesně (power v rozsahu normálních čísel).
function _power_of_two(power):
    result = 1.0
    if power >= 0:
        for step in rang(power):
            result *= 2.0
        end
    else:
        for step in rang(-power):
            result *= 0.5
        end
    end
    return result
end

# value · 2^power s jediným zaokrouhlením i v subnormální oblasti.
function _scale_by_power_of_two(value, power):
    if power > 1023:
        return value * _power_of_two(1023) * _power_of_two(power - 1023)
    elif power < -1022:
        return value * _power_of_two(-1022) * _power_of_two(power + 1022)
    end
    return value * _power_of_two(power)
end

function exp(value):
    number = Float(value)
    if number != number:
        return number
    elif number > 709.782712893384:
        return 1.0 / 0.0
    elif number < -745.1332191019412:
        return 0.0
    end
    # x = k·ln2 + r, |r| <= ln2/2 (Cody-Waite rozklad ln2), e^x = e^r · 2^k.
    k = round_half_even_int(number / LN2)
    reduced = (number - Float(k) * 6.93147180369123816490e-01) - Float(k) * 1.90821492927058770002e-10
    # Hornerovo schéma od nejmenšího členu: 1 + r(1 + r/2(1 + r/3(...))).
    result = 1.0
    index = 20
    while index >= 1:
        result = 1.0 + reduced * result / Float(index)
        index -= 1
    end
    return _scale_by_power_of_two(result, k)
end

function round_half_even_int(number):
    whole = Int(number)
    fraction = number - Float(whole)
    if fraction > 0.5 or (fraction == 0.5 and whole % 2 != 0):
        return whole + 1
    elif fraction < -0.5 or (fraction == -0.5 and whole % 2 != 0):
        return whole - 1
    end
    return whole
end

function log(value):
    number = Float(value)
    if number != number or number == 1.0 / 0.0:
        Error(ValueError: "log requires a finite value")
    elif number <= 0.0:
        Error(ValueError: "log domain error")
    end

    offset = 0.0
    while number > 2.0:
        number /= 2.0
        offset += LN2
    end
    while number < 0.5:
        number *= 2.0
        offset -= LN2
    end

    ratio = (number - 1.0) / (number + 1.0)
    ratio_squared = ratio * ratio
    term = ratio
    series = 0.0
    denominator = 1
    while denominator <= 39:
        series += term / Float(denominator)
        term *= ratio_squared
        denominator += 2
    end
    return 2.0 * series + offset
end

function log2(value):
    return log(value) / LN2
end

function log10(value):
    return log(value) / 2.302585092994046
end

# Binární rozvoj 1/(2π) (1280 bitů za řádovou čárkou) pro přesnou redukci
# velkých argumentů (Payne-Hanek).
INVERSE_TAU_HEX = "28be60db9391054a7f09d5f47d4d377036d8a5664f10e4107f9458eaf7aef1586dc91b8e909374b801924bba827464873f877ac72c4a69cfba208d7d4baed1213a671c09ad17df904e64758e60d4ce7d272117e2ef7e4a0ec7fe25fff7816603fbcbc462d6829b47db4d9fb3c9f2c26dd3d18fd9a797fa8b5d49eeb1faf97c5ecf41ce7de294a4ba9afed7ec47e357421580cc11bf1edaeafc33ef0826bd0d87"

# Bit na pozici position (1 = první za řádovou čárkou) rozvoje 1/(2π).
function _inverse_tau_bit(position):
    if position < 1 or position > 1280:
        return 0
    end
    nibble = "0123456789abcdef".find(INVERSE_TAU_HEX[(position - 1) // 4])
    return (nibble >> (3 - (position - 1) % 4)) & 1
end

# Úhel v [-π, π] pro |x| >= 2^25: frac(m·2^e/(2π)) z okna 120 bitů rozvoje.
function _reduced_large_angle(number):
    bits = __lsl_float_bits(number)
    exponent_field = (bits >> 52) & 2047
    mantissa = (bits & 4503599627370495) | 4503599627370496
    exponent = exponent_field - 1075
    # Okno F = bity (e+1)..(e+120) rozvoje; pět limbů po 24 bitech.
    window = [0, 0, 0, 0, 0]
    for offset in rang(120):
        bit = _inverse_tau_bit(exponent + 1 + offset)
        if bit == 1:
            place = 119 - offset
            window[place // 24] += 1 << (place % 24)
        end
    end
    # m po 24 bitech a dolních 120 bitů součinu m·F.
    mantissa_limbs = [mantissa & 16777215, (mantissa >> 24) & 16777215, mantissa >> 48]
    product = [0, 0, 0, 0, 0, 0, 0, 0]
    for left in rang(3):
        for right in rang(5):
            product[left + right] += mantissa_limbs[left] * window[right]
        end
    end
    carry = 0
    for index in rang(8):
        total = product[index] + carry
        product[index] = total & 16777215
        carry = total >> 24
    end
    fraction = Float(product[4]) / 16777216.0 + Float(product[3]) / 281474976710656.0 + Float(product[2]) / 4722366482869645213696.0
    angle = fraction * TAU
    if angle > PI:
        angle -= TAU
    end
    return angle
end

function _normalized_angle(value):
    number = Float(value)
    if number != number or number - number != 0.0:
        Error(ValueError: "math domain error: trigonometric function of NaN or Infinity")
    end
    if number >= 33554432.0 or number <= -33554432.0:
        if number < 0.0:
            return -_reduced_large_angle(-number)
        end
        return _reduced_large_angle(number)
    end
    turns = floor((number + PI) / TAU)
    return number - Float(turns) * TAU
end

function sin(value):
    angle = _normalized_angle(value)
    term = angle
    result = angle
    square = angle * angle
    index = 1
    while index <= 16:
        left = Float(index * 2)
        right = Float(index * 2 + 1)
        term = -term * square / (left * right)
        result += term
        index += 1
    end
    return result
end

function cos(value):
    angle = _normalized_angle(value)
    term = 1.0
    result = 1.0
    square = angle * angle
    index = 1
    while index <= 16:
        left = Float(index * 2 - 1)
        right = Float(index * 2)
        term = -term * square / (left * right)
        result += term
        index += 1
    end
    return result
end

function tan(value):
    cosine = cos(value)
    if abs(cosine) < 1e-15:
        Error(ValueError: "tan is undefined at this angle")
    end
    return sin(value) / cosine
end

function sigmoid(value):
    number = Float(value)
    if number >= 0.0:
        return 1.0 / (1.0 + exp(-number))
    end
    scaled = exp(number)
    return scaled / (1.0 + scaled)
end

function tanh(value):
    number = Float(value)
    if number > 20.0:
        return 1.0
    elif number < -20.0:
        return -1.0
    end
    scaled = exp(2.0 * number)
    return (scaled - 1.0) / (scaled + 1.0)
end

function relu(value):
    if value > 0:
        return value
    end
    return 0
end

function softplus(value):
    number = Float(value)
    if number > 30.0:
        return number
    elif number < -30.0:
        return exp(number)
    end
    return log(1.0 + exp(number))
end

function swish(value):
    number = Float(value)
    return number * sigmoid(number)
end

function hypot(x, y):
    left = abs(Float(x))
    right = abs(Float(y))
    infinity = 1.0 / 0.0
    if left == infinity or right == infinity:
        return infinity
    elif left != left or right != right:
        return 0.0 / 0.0
    end
    larger = max(left, right)
    smaller = min(left, right)
    if larger == 0.0:
        return 0.0
    end
    # Škálování největší hodnotou: bez zbytečného přetečení i podtečení.
    ratio = smaller / larger
    return larger * sqrt(1.0 + ratio * ratio)
end

function is_close(left, right, relative_tolerance, absolute_tolerance):
    a = Float(left)
    b = Float(right)
    relative = Float(relative_tolerance)
    absolute = Float(absolute_tolerance)
    if relative < 0.0 or absolute < 0.0 or relative != relative or absolute != absolute:
        Error(ValueError: "tolerances must be non-negative")
    end
    if a == b:
        return True
    end
    # NaN není blízko ničemu; nekonečno jen sobě (řeší rovnost výše).
    if a != a or b != b or a - a != 0.0 or b - b != 0.0:
        return False
    end
    difference = abs(a - b)
    limit = max(Float(absolute_tolerance), Float(relative_tolerance) * max(abs(a), abs(b)))
    return difference <= limit
end

function mean(values):
    if len(values) == 0:
        Error(ValueError: "mean requires at least one value")
    end
    total = 0.0
    for value in values:
        total += Float(value)
    end
    count = Float(len(values))
    if total - total != 0.0 and total == total:
        # Mezisoučet přetekl: konečné hodnoty sečíst škálované počtem.
        scaled = 0.0
        finite = True
        for value in values:
            number = Float(value)
            if number - number != 0.0:
                finite = False
            end
            scaled += number / count
        end
        if finite:
            return scaled
        end
    end
    return total / count
end

function variance(values):
    if len(values) == 0:
        Error(ValueError: "variance requires at least one value")
    end
    average = mean(values)
    total = 0.0
    for value in values:
        difference = Float(value) - average
        total += difference * difference
    end
    return total / Float(len(values))
end

function standard_deviation(values):
    return sqrt(variance(values))
end

function median(values):
    if len(values) == 0:
        Error(ValueError: "median requires at least one value")
    end
    ordered = List(values)
    call ordered.sort()
    middle = len(ordered) // 2
    if len(ordered) % 2 == 1:
        return Float(ordered[middle])
    end
    lower = Float(ordered[middle - 1])
    upper = Float(ordered[middle])
    middle_value = (lower + upper) / 2.0
    if middle_value - middle_value != 0.0 and lower - lower == 0.0 and upper - upper == 0.0:
        return lower / 2.0 + upper / 2.0
    end
    return middle_value
end

function pi(decimal_places):
    places = Int(decimal_places)
    if places < 0:
        Error(ValueError: "pi decimal places cannot be negative")
    elif places > 2000:
        Error(ValueError: "pi exceeds the secure 2000-digit work limit")
    end

    # Rabinowitz-Wagon spigot algorithm. Every cell stays small enough for
    # Int64, while the generated decimal String can contain arbitrary digits.
    wanted = places + 1
    boxes = wanted * 10 // 3 + 1
    remainders = __lsl_int_zeros(boxes)
    index = 0
    while index < boxes:
        remainders[index] = 2
        index += 1
    end

    produced = ""
    predigit = 0
    held_nines = 0
    iteration = 0
    while iteration < wanted + 1:
        carry = 0
        index = boxes - 1
        while index > 0:
            value = remainders[index] * 10 + carry
            denominator = index * 2 + 1
            remainders[index] = value % denominator
            carry = (value // denominator) * index
            index -= 1
        end

        value = remainders[0] * 10 + carry
        remainders[0] = value % 10
        digit = value // 10
        if digit == 9:
            held_nines += 1
        elif digit == 10:
            produced += chr(48 + predigit + 1)
            while held_nines > 0:
                produced += "0"
                held_nines -= 1
            end
            predigit = 0
        else:
            produced += chr(48 + predigit)
            predigit = digit
            while held_nines > 0:
                produced += "9"
                held_nines -= 1
            end
        end
        iteration += 1
    end
    produced += chr(48 + predigit)

    digits = produced[1:len(produced)]
    if places == 0:
        return digits[0]
    end
    return digits[0] + "." + digits[1:places + 1]
end
