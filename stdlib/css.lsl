# A small CSS-subset parser so LuxOS apps can describe their look
# declaratively instead of hard-coding colors. Supports:
#   .selector { property: value; ... }
#   colors  #rgb, #rrggbb, rgb(r,g,b), rgba(r,g,b,a)
#   background: <color> | linear-gradient(<color>, <color>)
#   border-radius / padding / font-size / width / height: <number>[px]
# parse() returns Dictionary selector -> Dictionary property -> value
# string; the accessor helpers below interpret those strings for gfx.

load gfx

MAX_CSS_BYTES = 1048576
MAX_CSS_BLOCKS = 4096
MAX_CSS_DECLARATIONS = 65536

function hex_digit(character):
    code = ord(character)
    if code >= 48 and code <= 57:
        return code - 48
    end
    if code >= 97 and code <= 102:
        return code - 87
    end
    if code >= 65 and code <= 70:
        return code - 55
    end
    return -1
end

function parse_hex_color(text):
    body = text.strip()
    if body.startswith("#"):
        body = body[1:len(body)]
    end
    if len(body) != 3 and len(body) != 6:
        Error(CSSError: "hex color must contain three or six digits")
    end
    digits = []
    for character in body:
        digit = hex_digit(character)
        if digit < 0:
            Error(CSSError: "hex color contains a non-hexadecimal digit")
        end
        digits.append(digit)
    end
    if len(body) == 3:
        r = digits[0] * 17
        g = digits[1] * 17
        b = digits[2] * 17
        return gfx.rgb(r, g, b)
    end
    r = digits[0] * 16 + digits[1]
    g = digits[2] * 16 + digits[3]
    b = digits[4] * 16 + digits[5]
    return gfx.rgb(r, g, b)
end

# Split the "r, g, b[, a]" inside rgb()/rgba() into a List of String parts.
function split_args(text):
    inside = text
    open_paren = inside.find("(")
    if open_paren >= 0:
        inside = inside[open_paren + 1:len(inside)]
    end
    close_paren = inside.find(")")
    if close_paren >= 0:
        inside = inside[0:close_paren]
    end
    parts = []
    for piece in inside.split(","):
        parts.append(piece.strip())
    end
    return parts
end

# Interpret any single color token to a 0xRRGGBB Int.
function color(text):
    if type(text) != "String" or len(text) > 256:
        Error(CSSError: "color must be a short String")
    end
    value = text.strip()
    if value.startswith("#"):
        return parse_hex_color(value)
    end
    if value.startswith("rgb"):
        parts = split_args(value)
        if len(parts) != 3 and len(parts) != 4:
            Error(CSSError: "rgb color needs three components")
        end
        components = []
        index = 0
        while index < 3:
            component = Int(parts[index])
            if component < 0 or component > 255:
                Error(CSSError: "rgb component is outside 0..255")
            end
            components.append(component)
            index += 1
        end
        return gfx.rgb(components[0], components[1], components[2])
    end
    return 0
end

# Alpha 0..255 for an rgba() token; opaque otherwise.
function alpha(text):
    if type(text) != "String" or len(text) > 256:
        Error(CSSError: "alpha color must be a short String")
    end
    value = text.strip()
    if value.startswith("rgba"):
        parts = split_args(value)
        if len(parts) >= 4:
            value = Float(parts[3])
            if value != value or value < 0.0 or value > 1.0:
                Error(CSSError: "rgba alpha is outside 0..1")
            end
            return Int(value * 255.0)
        end
    end
    return 255
end

function is_gradient(text):
    return text.strip().startswith("linear-gradient")
end

function gradient_top(text):
    parts = split_args(text)
    return color(parts[0])
end

function gradient_bottom(text):
    parts = split_args(text)
    if len(parts) >= 2:
        return color(parts[1])
    end
    return color(parts[0])
end

# Numeric value with an optional px suffix.
function number(text):
    value = text.strip()
    if value.endswith("px"):
        value = value[0:len(value) - 2]
    end
    return Int(value.strip())
end

# Parse a stylesheet String into selector -> {property: value}.
function parse(text):
    if type(text) != "String":
        Error(TypeError: "css.parse expects a String")
    elif __lsl_text_byte_length(String(text)) > MAX_CSS_BYTES:
        Error(CSSError: "stylesheet exceeds 1 MiB")
    end
    sheet = {}
    block_count = 0
    declaration_count = 0
    for block in text.split("}"):
        brace = block.find("{")
        if brace < 0:
            continue
        end
        block_count += 1
        if block_count > MAX_CSS_BLOCKS:
            Error(CSSError: "stylesheet has too many blocks")
        end
        selector = block[0:brace].strip()
        if selector.startswith("."):
            selector = selector[1:len(selector)]
        end
        if len(selector) == 0 or len(selector) > 256:
            Error(CSSError: "selector has an invalid length")
        end
        for character in selector:
            code = ord(character)
            if not ((code >= 48 and code <= 57) or (code >= 65 and code <= 90) or (code >= 97 and code <= 122) or character == "-" or character == "_"):
                Error(CSSError: "selector contains an invalid character")
            end
        end
        body = block[brace + 1:len(block)]
        rules = {}
        for declaration in body.split(";"):
            colon = declaration.find(":")
            if colon < 0:
                continue
            end
            declaration_count += 1
            if declaration_count > MAX_CSS_DECLARATIONS:
                Error(CSSError: "stylesheet has too many declarations")
            end
            key = declaration[0:colon].strip()
            property_value = declaration[colon + 1:len(declaration)].strip()
            if len(key) == 0 or len(key) > 128 or len(property_value) > 4096:
                Error(CSSError: "CSS declaration has an invalid length")
            end
            for character in key:
                code = ord(character)
                if not ((code >= 65 and code <= 90) or (code >= 97 and code <= 122) or character == "-"):
                    Error(CSSError: "CSS property contains an invalid character")
                end
            end
            rules[key] = property_value
        end
        sheet[selector] = rules
    end
    return sheet
end

function rule(sheet, selector):
    return sheet.get(selector, {})
end

function value(rules, key, fallback):
    return rules.get(key, fallback)
end
