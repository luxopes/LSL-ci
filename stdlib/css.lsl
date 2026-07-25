# A small CSS-subset parser so LuxOS apps can describe their look
# declaratively instead of hard-coding colors. Supports:
#   .selector { property: value; ... }
#   colors  #rgb, #rrggbb, rgb(r,g,b), rgba(r,g,b,a)
#   background: <color> | linear-gradient(<color>, <color>)
#   border-radius / padding / font-size / width / height: <number>[px]
# parse() returns Dictionary selector -> Dictionary property -> value
# string; the accessor helpers below interpret those strings for gfx.

load gfx

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
    return 0
end

function parse_hex_color(text):
    body = text.strip()
    if body.startswith("#"):
        body = body[1:len(body)]
    end
    if len(body) == 3:
        r = hex_digit(body[0:1]) * 17
        g = hex_digit(body[1:2]) * 17
        b = hex_digit(body[2:3]) * 17
        return gfx.rgb(r, g, b)
    end
    r = hex_digit(body[0:1]) * 16 + hex_digit(body[1:2])
    g = hex_digit(body[2:3]) * 16 + hex_digit(body[3:4])
    b = hex_digit(body[4:5]) * 16 + hex_digit(body[5:6])
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
    value = text.strip()
    if value.startswith("#"):
        return parse_hex_color(value)
    end
    if value.startswith("rgb"):
        parts = split_args(value)
        return gfx.rgb(Int(parts[0]), Int(parts[1]), Int(parts[2]))
    end
    return 0
end

# Alpha 0..255 for an rgba() token; opaque otherwise.
function alpha(text):
    value = text.strip()
    if value.startswith("rgba"):
        parts = split_args(value)
        if len(parts) >= 4:
            return Int(Float(parts[3]) * 255.0)
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
    sheet = {}
    for block in text.split("}"):
        brace = block.find("{")
        if brace < 0:
            continue
        end
        selector = block[0:brace].strip()
        if selector.startswith("."):
            selector = selector[1:len(selector)]
        end
        body = block[brace + 1:len(block)]
        rules = {}
        for declaration in body.split(";"):
            colon = declaration.find(":")
            if colon < 0:
                continue
            end
            key = declaration[0:colon].strip()
            rules[key] = declaration[colon + 1:len(declaration)].strip()
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
