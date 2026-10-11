# Wall-clock, monotonic timing and syscall-only sleeping.

function time():
    return __lsl_wall_time()
end

function now():
    return __lsl_wall_time()
end

function monotonic():
    return __lsl_monotonic()
end

function perf_counter():
    return __lsl_monotonic()
end

function sleep(seconds):
    duration = Float(seconds)
    if duration < 0.0:
        Error(ValueError: "sleep duration cannot be negative")
    end
    call __lsl_sleep(duration)
    return None
end

# Kalendářní čas v UTC: ISO-8601 a strftime bez závislosti na časových zónách
# systému. Rozklad používá algoritmus civil_from_days (proleptický gregorián).
WEEKDAY_NAMES = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"]
MONTH_NAMES = ["January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December"]

function _pad(value, width):
    text = String(value)
    while len(text) < width:
        text = "0" + text
    end
    return text
end

function _timestamp(seconds):
    if seconds == None:
        return __lsl_wall_time()
    end
    if type(seconds) != "Int" and type(seconds) != "Float":
        Error(TypeError: "time value must be Int or Float, got " + type(seconds))
    end
    value = Float(seconds)
    if value != value or value > 253402300799.0 or value < -62135596800.0:
        Error(ValueError: "time value is outside years 1..9999")
    end
    return seconds
end

function _days_before_year(year):
    y = year - 1
    return y * 365 + y // 4 - y // 100 + y // 400
end

function _leap(year):
    return (year % 4 == 0 and year % 100 != 0) or year % 400 == 0
end

function _month_days(year, month):
    if month == 2:
        if _leap(year):
            return 29
        end
        return 28
    elif month == 4 or month == 6 or month == 9 or month == 11:
        return 30
    end
    return 31
end

function _whole_seconds(stamp):
    total = Int(stamp)
    if Float(total) > Float(stamp):
        total -= 1
    end
    return total
end

function utc(seconds=None):
    stamp = _timestamp(seconds)
    total = _whole_seconds(stamp)
    microsecond = 0
    if type(stamp) == "Float":
        microsecond = Int((stamp - Float(total)) * 1000000.0 + 0.5)
        if microsecond >= 1000000:
            microsecond -= 1000000
            total += 1
        end
    end
    days = total // 86400
    rest = total - days * 86400
    shifted = days + 719468
    era = shifted // 146097
    day_of_era = shifted - era * 146097
    year_of_era = (day_of_era - day_of_era // 1460 + day_of_era // 36524 - day_of_era // 146096) // 365
    year = year_of_era + era * 400
    day_of_year = day_of_era - (365 * year_of_era + year_of_era // 4 - year_of_era // 100)
    month_index = (5 * day_of_year + 2) // 153
    day = day_of_year - (153 * month_index + 2) // 5 + 1
    month = month_index + 3
    if month > 12:
        month -= 12
    end
    if month <= 2:
        year += 1
    end
    yearday = days + 719162 - _days_before_year(year) + 1
    return {"year": year, "month": month, "day": day, "hour": rest // 3600, "minute": rest % 3600 // 60, "second": rest % 60, "microsecond": microsecond, "weekday": (days + 3) % 7, "yearday": yearday}
end

function iso8601(seconds=None, digits=6):
    if type(digits) != "Int":
        Error(TypeError: "digits must be Int, got " + type(digits))
    elif digits < 0 or digits > 6:
        Error(ValueError: "digits must be between 0 and 6")
    end
    parts = utc(seconds)
    text = _pad(parts["year"], 4) + "-" + _pad(parts["month"], 2) + "-" + _pad(parts["day"], 2)
    text += "T" + _pad(parts["hour"], 2) + ":" + _pad(parts["minute"], 2) + ":" + _pad(parts["second"], 2)
    if digits > 0:
        text += "." + _pad(parts["microsecond"], 6)[0:digits]
    end
    return text + "+00:00"
end

function strftime(format, seconds=None):
    if type(format) != "String":
        Error(TypeError: "strftime format must be String, got " + type(format))
    end
    parts = utc(seconds)
    output = []
    index = 0
    while index < len(format):
        character = format[index]
        if character != "%":
            output.append(character)
            index += 1
            continue
        end
        if index + 1 >= len(format):
            Error(ValueError: "strftime format ends with a lone %")
        end
        code = format[index + 1]
        index += 2
        if code == "Y":
            output.append(_pad(parts["year"], 4))
        elif code == "y":
            output.append(_pad(parts["year"] % 100, 2))
        elif code == "m":
            output.append(_pad(parts["month"], 2))
        elif code == "d":
            output.append(_pad(parts["day"], 2))
        elif code == "e":
            day_text = String(parts["day"])
            if len(day_text) < 2:
                day_text = " " + day_text
            end
            output.append(day_text)
        elif code == "H":
            output.append(_pad(parts["hour"], 2))
        elif code == "I":
            hour12 = parts["hour"] % 12
            if hour12 == 0:
                hour12 = 12
            end
            output.append(_pad(hour12, 2))
        elif code == "p":
            if parts["hour"] < 12:
                output.append("AM")
            else:
                output.append("PM")
            end
        elif code == "M":
            output.append(_pad(parts["minute"], 2))
        elif code == "S":
            output.append(_pad(parts["second"], 2))
        elif code == "f":
            output.append(_pad(parts["microsecond"], 6))
        elif code == "j":
            output.append(_pad(parts["yearday"], 3))
        elif code == "a":
            output.append(WEEKDAY_NAMES[parts["weekday"]][0:3])
        elif code == "A":
            output.append(WEEKDAY_NAMES[parts["weekday"]])
        elif code == "u":
            output.append(String(parts["weekday"] + 1))
        elif code == "w":
            output.append(String((parts["weekday"] + 1) % 7))
        elif code == "b":
            output.append(MONTH_NAMES[parts["month"] - 1][0:3])
        elif code == "B":
            output.append(MONTH_NAMES[parts["month"] - 1])
        elif code == "F":
            output.append(_pad(parts["year"], 4) + "-" + _pad(parts["month"], 2) + "-" + _pad(parts["day"], 2))
        elif code == "T":
            output.append(_pad(parts["hour"], 2) + ":" + _pad(parts["minute"], 2) + ":" + _pad(parts["second"], 2))
        elif code == "s":
            output.append(String(_whole_seconds(_timestamp(seconds))))
        elif code == "z":
            output.append("+0000")
        elif code == "Z":
            output.append("UTC")
        elif code == "%":
            output.append("%")
        else:
            Error(ValueError: "unsupported strftime directive %" + code)
        end
    end
    return "".join(output)
end

function _digits_at(text, start, count, label):
    if start + count > len(text):
        Error(ValueError: "invalid ISO-8601 time: missing " + label)
    end
    value = 0
    for offset in rang(count):
        position = "0123456789".find(text[start + offset])
        if position < 0:
            Error(ValueError: "invalid ISO-8601 time: bad " + label)
        end
        value = value * 10 + position
    end
    return value
end

function _expect(text, position, character):
    if position >= len(text) or text[position] != character:
        Error(ValueError: "invalid ISO-8601 time: expected " + character + " at offset " + String(position))
    end
end

# Převod ISO-8601 (YYYY-MM-DDTHH:MM:SS[.zlomek](Z|±HH:MM)) na unixový čas.
function parse_iso8601(text):
    if type(text) != "String":
        Error(TypeError: "ISO-8601 time must be String, got " + type(text))
    end
    year = _digits_at(text, 0, 4, "year")
    call _expect(text, 4, "-")
    month = _digits_at(text, 5, 2, "month")
    call _expect(text, 7, "-")
    day = _digits_at(text, 8, 2, "day")
    if len(text) <= 10 or (text[10] != "T" and text[10] != " "):
        Error(ValueError: "invalid ISO-8601 time: expected T at offset 10")
    end
    hour = _digits_at(text, 11, 2, "hour")
    call _expect(text, 13, ":")
    minute = _digits_at(text, 14, 2, "minute")
    call _expect(text, 16, ":")
    second = _digits_at(text, 17, 2, "second")
    if year < 1 or month < 1 or month > 12 or day < 1 or day > _month_days(year, month) or hour > 23 or minute > 59 or second > 59:
        Error(ValueError: "invalid ISO-8601 time: field out of range")
    end
    position = 19
    fraction = 0.0
    if position < len(text) and text[position] == ".":
        position += 1
        scale = 0.1
        start = position
        while position < len(text) and "0123456789".find(text[position]) >= 0:
            fraction += Float("0123456789".find(text[position])) * scale
            scale = scale / 10.0
            position += 1
        end
        if position == start:
            Error(ValueError: "invalid ISO-8601 time: empty fraction")
        end
    end
    offset = 0
    if position < len(text) and text[position] == "Z":
        position += 1
    elif position < len(text) and (text[position] == "+" or text[position] == "-"):
        sign = 1
        if text[position] == "-":
            sign = -1
        end
        offset_hours = _digits_at(text, position + 1, 2, "offset hour")
        call _expect(text, position + 3, ":")
        offset_minutes = _digits_at(text, position + 4, 2, "offset minute")
        if offset_hours > 23 or offset_minutes > 59:
            Error(ValueError: "invalid ISO-8601 time: offset out of range")
        end
        offset = sign * (offset_hours * 3600 + offset_minutes * 60)
        position += 6
    else:
        Error(ValueError: "invalid ISO-8601 time: missing Z or offset")
    end
    if position != len(text):
        Error(ValueError: "invalid ISO-8601 time: unexpected text at offset " + String(position))
    end
    days = _days_before_year(year) - 719162
    for earlier in rang(1, month):
        days += _month_days(year, earlier)
    end
    days += day - 1
    whole = days * 86400 + hour * 3600 + minute * 60 + second - offset
    if fraction == 0.0:
        return Float(whole)
    end
    return Float(whole) + fraction
end
