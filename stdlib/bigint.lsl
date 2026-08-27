# Arbitrary-precision signed integers implemented with canonical decimal
# digits. BigInt deliberately lives in the standard library so normal Int64
# arithmetic keeps its compact native representation and speed.

MAX_BIGINT_DIGITS = 1000000
MAX_BIGINT_QUADRATIC_WORK = 50000000

function _strip_leading_zeros(digits):
    index = 0
    while index + 1 < len(digits) and digits[index] == "0":
        index += 1
    end
    return digits[index:len(digits)]
end

function _validated_parts(text):
    if type(text) != "String":
        Error(TypeError: "BigInt text must be a String")
    elif len(text) > MAX_BIGINT_DIGITS + 2:
        Error(ValueError: "BigInt exceeds one million decimal digits")
    end
    value = text.strip()
    if len(value) == 0:
        Error(ValueError: "BigInt requires at least one decimal digit")
    end

    sign = 1
    start = 0
    if value[0] == "-":
        sign = -1
        start = 1
    elif value[0] == "+":
        start = 1
    end
    if start >= len(value):
        Error(ValueError: "BigInt sign must be followed by decimal digits")
    elif len(value) - start > MAX_BIGINT_DIGITS:
        Error(ValueError: "BigInt exceeds one million decimal digits")
    end

    index = start
    while index < len(value):
        code = ord(value[index])
        if code < 48 or code > 57:
            Error(ValueError: "BigInt accepts decimal digits only")
        end
        index += 1
    end
    digits = value[start:len(value)]
    digits = _strip_leading_zeros(digits)
    if digits == "0":
        sign = 0
    end
    return [sign, digits]
end

function _validated_digits(text):
    if type(text) != "String" or len(text) == 0 or len(text) > MAX_BIGINT_DIGITS:
        Error(ValueError: "invalid BigInt digit storage")
    end
    for character in text:
        code = ord(character)
        if code < 48 or code > 57:
            Error(ValueError: "invalid BigInt digit storage")
        end
    end
    return _strip_leading_zeros(text)
end

function _check_quadratic_work(left, right, operation):
    left_size = len(left)
    right_size = len(right)
    if left_size > MAX_BIGINT_DIGITS or right_size > MAX_BIGINT_DIGITS:
        Error(ValueError: operation + " exceeds the BigInt digit limit")
    elif right_size > 0 and left_size > MAX_BIGINT_QUADRATIC_WORK // right_size:
        Error(ValueError: operation + " exceeds the BigInt work limit")
    end
end

function _parts(value):
    value_type = type(value)
    if value_type == "Int" or value_type == "String" or value_type == "Bool":
        return _validated_parts(String(value))
    elif value_type == "Dictionary" or value_type == "Instance":
        sign = Int(value["sign"])
        digits = _validated_digits(String(value["digits"]))
        if sign < -1 or sign > 1:
            Error(ValueError: "invalid BigInt sign")
        end
        digits = _strip_leading_zeros(digits)
        if digits == "0":
            sign = 0
        end
        return [sign, digits]
    end
    Error(TypeError: "BigInt expects an Int, String, Bool, or BigInt")
end

function _format(sign, digits):
    normalized = _strip_leading_zeros(digits)
    if normalized == "0" or sign == 0:
        return "0"
    elif sign < 0:
        return "-" + normalized
    end
    return normalized
end

function _compare_magnitude(left, right):
    a = _strip_leading_zeros(left)
    b = _strip_leading_zeros(right)
    if len(a) < len(b):
        return -1
    elif len(a) > len(b):
        return 1
    end
    index = 0
    while index < len(a):
        a_digit = ord(a[index])
        b_digit = ord(b[index])
        if a_digit < b_digit:
            return -1
        elif a_digit > b_digit:
            return 1
        end
        index += 1
    end
    return 0
end

function _add_magnitude(left, right):
    a_index = len(left) - 1
    b_index = len(right) - 1
    carry = 0
    capacity = max(len(left), len(right)) + 1
    result = __lsl_byte_zeros(capacity)
    position = capacity
    while a_index >= 0 or b_index >= 0 or carry > 0:
        a_digit = 0
        b_digit = 0
        if a_index >= 0:
            a_digit = ord(left[a_index]) - 48
        end
        if b_index >= 0:
            b_digit = ord(right[b_index]) - 48
        end
        total = a_digit + b_digit + carry
        position -= 1
        result[position] = 48 + total % 10
        carry = total // 10
        a_index -= 1
        b_index -= 1
    end
    return _strip_leading_zeros(__lsl_text_from_bytes(result, position, capacity - position))
end

function _subtract_magnitude(left, right):
    # Precondition: abs(left) >= abs(right).
    a_index = len(left) - 1
    b_index = len(right) - 1
    borrow = 0
    result = __lsl_byte_zeros(len(left))
    position = len(left)
    while a_index >= 0:
        a_digit = ord(left[a_index]) - 48 - borrow
        b_digit = 0
        if b_index >= 0:
            b_digit = ord(right[b_index]) - 48
        end
        if a_digit < b_digit:
            a_digit += 10
            borrow = 1
        else:
            borrow = 0
        end
        position -= 1
        result[position] = 48 + a_digit - b_digit
        a_index -= 1
        b_index -= 1
    end
    return _strip_leading_zeros(__lsl_text_from_bytes(result, position, len(left) - position))
end

function _multiply_magnitude(left, right):
    if left == "0" or right == "0":
        return "0"
    end
    call _check_quadratic_work(left, right, "BigInt multiplication")
    if len(left) > MAX_BIGINT_DIGITS - len(right):
        Error(ValueError: "BigInt multiplication result exceeds the digit limit")
    end
    digits = __lsl_int_zeros(len(left) + len(right))
    left_index = len(left) - 1
    while left_index >= 0:
        left_digit = ord(left[left_index]) - 48
        right_index = len(right) - 1
        while right_index >= 0:
            right_digit = ord(right[right_index]) - 48
            position = left_index + right_index + 1
            total = digits[position] + left_digit * right_digit
            digits[position] = total % 10
            digits[position - 1] += total // 10
            right_index -= 1
        end
        left_index -= 1
    end

    result = __lsl_byte_zeros(len(digits))
    index = 0
    while index < len(digits):
        result[index] = 48 + digits[index]
        index += 1
    end
    return _strip_leading_zeros(__lsl_text_from_bytes(result, 0, len(result)))
end

function _divmod_magnitude(dividend, divisor):
    if divisor == "0":
        Error(ZeroDivisionError: "BigInt division by zero")
    end
    if _compare_magnitude(dividend, divisor) < 0:
        return ["0", _strip_leading_zeros(dividend)]
    end
    call _check_quadratic_work(dividend, divisor, "BigInt division")

    quotient = __lsl_byte_zeros(len(dividend))
    remainder = "0"
    index = 0
    while index < len(dividend):
        remainder = _strip_leading_zeros(remainder + dividend[index])
        quotient_digit = 0
        while _compare_magnitude(remainder, divisor) >= 0:
            remainder = _subtract_magnitude(remainder, divisor)
            quotient_digit += 1
        end
        quotient[index] = 48 + quotient_digit
        index += 1
    end
    return [_strip_leading_zeros(__lsl_text_from_bytes(quotient, 0, len(quotient))), _strip_leading_zeros(remainder)]
end

function _add_signed(left_sign, left_digits, right_sign, right_digits):
    if left_sign == 0:
        return _format(right_sign, right_digits)
    elif right_sign == 0:
        return _format(left_sign, left_digits)
    elif left_sign == right_sign:
        return _format(left_sign, _add_magnitude(left_digits, right_digits))
    end

    comparison = _compare_magnitude(left_digits, right_digits)
    if comparison == 0:
        return "0"
    elif comparison > 0:
        return _format(left_sign, _subtract_magnitude(left_digits, right_digits))
    end
    return _format(right_sign, _subtract_magnitude(right_digits, left_digits))
end

function _divide_signed(left_sign, left_digits, right_sign, right_digits):
    if right_sign == 0:
        Error(ZeroDivisionError: "BigInt division by zero")
    elif left_sign == 0:
        return ["0", "0"]
    end

    magnitude = _divmod_magnitude(left_digits, right_digits)
    quotient_digits = String(magnitude[0])
    remainder_digits = String(magnitude[1])
    if left_sign == right_sign:
        return [_format(1, quotient_digits), _format(left_sign, remainder_digits)]
    elif remainder_digits == "0":
        return [_format(-1, quotient_digits), "0"]
    end

    # Match LSL/Python floor division: -7 // 3 == -3 and -7 % 3 == 2.
    quotient_digits = _add_magnitude(quotient_digits, "1")
    remainder_digits = _subtract_magnitude(right_digits, remainder_digits)
    return [_format(-1, quotient_digits), _format(right_sign, remainder_digits)]
end

class BigInt:
    ctype Public

    function init(self, value):
        parsed = _parts(value)
        self.sign = Int(parsed[0])
        self.digits = String(parsed[1])
    end

    function text(self):
        return _format(self.sign, self.digits)
    end

    function is_zero(self):
        return self.sign == 0
    end

    function compare(self, other):
        right = _parts(other)
        right_sign = Int(right[0])
        right_digits = String(right[1])
        if self.sign < right_sign:
            return -1
        elif self.sign > right_sign:
            return 1
        elif self.sign == 0:
            return 0
        end
        comparison = _compare_magnitude(self.digits, right_digits)
        if self.sign < 0:
            return -comparison
        end
        return comparison
    end

    function equals(self, other):
        return self.compare(other) == 0
    end

    function negate(self):
        return BigInt(_format(-self.sign, self.digits))
    end

    function absolute(self):
        return BigInt(self.digits)
    end

    function add(self, other):
        right = _parts(other)
        return BigInt(_add_signed(self.sign, self.digits, Int(right[0]), String(right[1])))
    end

    function subtract(self, other):
        right = _parts(other)
        return BigInt(_add_signed(self.sign, self.digits, -Int(right[0]), String(right[1])))
    end

    function multiply(self, other):
        right = _parts(other)
        sign = self.sign * Int(right[0])
        digits = _multiply_magnitude(self.digits, String(right[1]))
        return BigInt(_format(sign, digits))
    end

    function floor_divide(self, other):
        right = _parts(other)
        result = _divide_signed(self.sign, self.digits, Int(right[0]), String(right[1]))
        return BigInt(String(result[0]))
    end

    function divide(self, other):
        return self.floor_divide(other)
    end

    function modulo(self, other):
        right = _parts(other)
        result = _divide_signed(self.sign, self.digits, Int(right[0]), String(right[1]))
        return BigInt(String(result[1]))
    end

    function power(self, exponent):
        power_value = Int(exponent)
        if power_value < 0:
            Error(ValueError: "BigInt power requires a non-negative exponent")
        end
        result = BigInt(1)
        base = BigInt(self)
        while power_value > 0:
            if power_value % 2 == 1:
                result = result.multiply(base)
            end
            power_value = power_value // 2
            if power_value > 0:
                base = base.multiply(base)
            end
        end
        return result
    end

    function to_int(self):
        if self.sign >= 0:
            if _compare_magnitude(self.digits, "9223372036854775807") > 0:
                Error(OverflowError: "BigInt does not fit in Int")
            end
        elif _compare_magnitude(self.digits, "9223372036854775808") > 0:
            Error(OverflowError: "BigInt does not fit in Int")
        end
        return Int(self.text())
    end
end

# Optional compatibility name for users who prefer the more descriptive label.
class SuperInt(BigInt):
    ctype Public

    function init(self, value):
        call origin.init(value)
    end
end

function parse(value):
    return BigInt(value)
end
