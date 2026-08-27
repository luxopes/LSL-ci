# Token-span recursive-descent parser for the direct compiler.

load diagnostics
load lexer

function state(path, source):
    return state_with_interpolation(path, source, 0)
end

function state_with_interpolation(path, source, interpolation_depth):
    # Keep the source compact on successful parses; line materialization is only
    # needed when producing a parser diagnostic.
    # Slots 4/5 bound recursive unary/block parsing. Slots 6/7 bound the token
    # complexity of one expression, and slot 8 follows nested Lux Strings.
    return [lexer.tokenize(path, source), 0, path, source, 0, 0, 0, 0, interpolation_depth]
end

function current(parser):
    return parser[0][parser[1]]
end

function previous(parser):
    if parser[1] == 0:
        return parser[0][0]
    end
    return parser[0][parser[1] - 1]
end

function advance(parser):
    token = current(parser)
    if token["kind"] != "eof":
        parser[1] = parser[1] + 1
    end
    return token
end

function check(parser, value):
    return current(parser)["value"] == value
end

function check_kind(parser, kind):
    return current(parser)["kind"] == kind
end

function match(parser, value):
    token = current(parser)
    if token["kind"] == "string" or token["kind"] == "number":
        return False
    end
    if token["value"] == value:
        call advance(parser)
        return True
    end
    return False
end

function line_source(parser, line):
    lines = parser[3].split(chr(10))
    if line < 1 or line > len(lines):
        return ""
    end
    return lines[line - 1]
end

function fail_at(parser, token, code, message, help_text):
    width = max(1, token["end_column"] - token["column"])
    call diagnostics.fail(parser[2], token["line"], token["column"], width, line_source(parser, token["line"]), code, message, help_text)
end

function expect(parser, value, code, message):
    if not check(parser, value):
        call fail_at(parser, current(parser), code, message, "expected `" + value + "` here")
    end
    return advance(parser)
end

function expect_kind(parser, kind, code, message):
    if not check_kind(parser, kind):
        call fail_at(parser, current(parser), code, message, "check the token at this position")
    end
    return advance(parser)
end

function skip_newlines(parser):
    while check_kind(parser, "newline"):
        call advance(parser)
    end
end

function location(token):
    return {"line": token["line"], "column": token["column"], "end_column": token["end_column"]}
end

function node(kind, token):
    return {"kind": kind, "line": token["line"], "column": token["column"], "end_column": token["end_column"]}
end

function finish_node(value, parser):
    value["end_column"] = previous(parser)["end_column"]
    return value
end

function parse_arguments(parser):
    arguments = []
    if match(parser, ")"):
        return arguments
    end
    loop:
        arguments.append(parse_expression(parser))
        if match(parser, ")"):
            break
        end
        call expect(parser, ",", "E1101", "expected comma between arguments")
    end
    return arguments
end

function interpolation_literal(token, value):
    result = node("literal", token)
    result["literal_kind"] = "string"
    result["value"] = value
    return result
end

function interpolation_value(parser, value, token):
    path = parser[2]
    parts = []
    literal = []
    index = 0
    while index < len(value):
        character = value[index]
        if character == "{" and index + 1 < len(value) and value[index + 1] == "{":
            literal.append("{")
            index += 2
        elif character == "}" and index + 1 < len(value) and value[index + 1] == "}":
            literal.append("}")
            index += 2
        elif character == "{":
            if len(parts) >= 1024:
                call diagnostics.fail(path, token["line"], token["column"], max(1, token["end_column"] - token["column"]), value, "E1116", "Lux String contains too many interpolations", "use at most 1024 interpolated fields")
            end
            if len(literal) > 0:
                parts.append(interpolation_literal(token, "".join(literal)))
                literal = []
            end
            closing = index + 1
            depth = 1
            quote = ""
            while closing < len(value) and depth > 0:
                current_character = value[closing]
                if quote != "":
                    if current_character == quote:
                        quote = ""
                    end
                elif current_character == "\"" or current_character == "'":
                    quote = current_character
                elif current_character == "{":
                    depth += 1
                elif current_character == "}":
                    depth -= 1
                end
                closing += 1
            end
            if depth != 0:
                call diagnostics.fail(path, token["line"], token["column"], max(1, token["end_column"] - token["column"]), value, "E1112", "unclosed Lux String interpolation", "add a closing brace or use {{ for a literal opening brace")
            end
            expression_source = value[index + 1:closing - 1]
            if len(expression_source.strip()) == 0:
                call diagnostics.fail(path, token["line"], token["column"], max(1, token["end_column"] - token["column"]), value, "E1113", "empty Lux String interpolation", "put an expression between the braces")
            end
            if parser[8] >= 64:
                call diagnostics.fail(path, token["line"], token["column"], max(1, token["end_column"] - token["column"]), value, "E1117", "Lux String interpolation nesting exceeds 64 levels", "split the expression into intermediate values")
            end
            expression_parser = state_with_interpolation(path, expression_source, parser[8] + 1)
            expression = parse_expression(expression_parser)
            if not check_kind(expression_parser, "eof"):
                call fail_at(expression_parser, current(expression_parser), "E1114", "unexpected token in Lux String interpolation", "use one expression between the braces")
            end
            conversion = node("call", token)
            conversion["target"] = node("name", token)
            conversion["target"]["name"] = "String"
            conversion["arguments"] = [expression]
            parts.append(conversion)
            index = closing
        elif character == "}":
            call diagnostics.fail(path, token["line"], token["column"], max(1, token["end_column"] - token["column"]), value, "E1115", "unexpected closing brace in Lux String", "use }} for a literal closing brace")
        else:
            literal.append(character)
            index += 1
        end
    end
    if len(literal) > 0 or len(parts) == 0:
        parts.append(interpolation_literal(token, "".join(literal)))
    end

    # A balanced concatenation tree avoids quadratic copying for templates with
    # many fields while keeping the result a normal first-class String.
    while len(parts) > 1:
        merged = []
        part_index = 0
        while part_index < len(parts):
            if part_index + 1 < len(parts):
                merged.append(binary_node("+", parts[part_index], parts[part_index + 1]))
            else:
                merged.append(parts[part_index])
            end
            part_index += 2
        end
        parts = merged
    end
    return parts[0]
end

function parse_primary(parser):
    token = advance(parser)
    kind = token["kind"]
    value = token["value"]
    if kind == "lux_string":
        result = interpolation_value(parser, value, token)
    elif kind == "string" or kind == "number":
        result = node("literal", token)
        result["literal_kind"] = kind
        result["value"] = value
        if kind == "number" and value.find(".") < 0 and value.find("e") < 0 and value.find("E") < 0:
            # Parse validated decimal tokens once, before code generation's
            # high-memory runtime emission. The AST stores a boxed Int.
            result["integer_value"] = __lsl_parse_literal_int(value)
        end
    elif value == "True" or value == "False" or value == "None":
        result = node("literal", token)
        result["literal_kind"] = "name"
        result["value"] = value
    elif kind == "name":
        result = node("name", token)
        result["name"] = value
        # Original LSL input syntax is expression-like but omits call
        # parentheses: `name = input "Prompt: "`. Lower it to the same call AST
        # as `input("Prompt: ")`; keep a bare `input` name first-class.
        if value == "input" and check_kind(parser, "string"):
            input_call = node("call", token)
            input_call["target"] = result
            input_call["arguments"] = [parse_expression(parser)]
            result = finish_node(input_call, parser)
        end
    elif value == "(":
        if match(parser, ")"):
            result = node("tuple", token)
            result["items"] = []
        else:
            first = parse_expression(parser)
            if match(parser, ","):
                items = [first]
                while not check(parser, ")"):
                    items.append(parse_expression(parser))
                    if not match(parser, ","):
                        break
                    end
                end
                call expect(parser, ")", "E1102", "unclosed Tuple literal")
                result = node("tuple", token)
                result["items"] = items
            else:
                call expect(parser, ")", "E1103", "unclosed parenthesized expression")
                result = first
            end
        end
    elif value == "[":
        items = []
        if not match(parser, "]"):
            loop:
                items.append(parse_expression(parser))
                if match(parser, "]"):
                    break
                end
                call expect(parser, ",", "E1104", "expected comma in List literal")
            end
        end
        result = node("list", token)
        result["items"] = items
    elif value == "{":
        entries = []
        if not match(parser, "}"):
            loop:
                key = parse_expression(parser)
                call expect(parser, ":", "E1105", "expected colon in Dictionary literal")
                value_node = parse_expression(parser)
                entries.append([key, value_node])
                if match(parser, "}"):
                    break
                end
                if not match(parser, ","):
                    if current(parser)["line"] <= previous(parser)["line"]:
                        call expect(parser, ",", "E1106", "expected comma in Dictionary literal")
                    end
                end
            end
        end
        result = node("dictionary", token)
        result["entries"] = entries
    else:
        call fail_at(parser, token, "E1100", "expected an expression", "use a literal, name, collection, or function call")
        result = node("invalid", token)
    end

    loop:
        if match(parser, "("):
            call_node = node("call", token)
            call_node["target"] = result
            call_node["arguments"] = parse_arguments(parser)
            result = finish_node(call_node, parser)
        elif match(parser, "["):
            index_node = node("index", token)
            index_node["target"] = result
            index_node["step"] = None
            if match(parser, ":"):
                index_node["start"] = None
                if check(parser, "]") or check(parser, ":"):
                    index_node["stop"] = None
                else:
                    index_node["stop"] = parse_expression(parser)
                end
                index_node["kind"] = "slice"
                if match(parser, ":"):
                    if check(parser, "]"):
                        index_node["step"] = None
                    else:
                        index_node["step"] = parse_expression(parser)
                    end
                end
            else:
                start = parse_expression(parser)
                if match(parser, ":"):
                    index_node["kind"] = "slice"
                    index_node["start"] = start
                    if check(parser, "]") or check(parser, ":"):
                        index_node["stop"] = None
                    else:
                        index_node["stop"] = parse_expression(parser)
                    end
                    if match(parser, ":"):
                        if check(parser, "]"):
                            index_node["step"] = None
                        else:
                            index_node["step"] = parse_expression(parser)
                        end
                    end
                else:
                    index_node["index"] = start
                end
            end
            call expect(parser, "]", "E1107", "unclosed index or slice")
            result = finish_node(index_node, parser)
        elif match(parser, "."):
            member_token = expect_kind(parser, "name", "E1108", "expected member name after dot")
            member_node = node("member", member_token)
            member_node["target"] = result
            member_node["name"] = member_token["value"]
            result = member_node
        else:
            break
        end
    end
    return result
end

function parse_unary(parser):
    token = current(parser)
    if match(parser, "not") or match(parser, "-") or match(parser, "+") or match(parser, "~"):
        parser[4] += 1
        if parser[4] > 256:
            call fail_at(parser, token, "E1111", "unary nesting exceeds 256 levels", "split the expression into smaller statements")
        end
        result = node("unary", token)
        result["operator"] = token["value"]
        result["operand"] = parse_unary(parser)
        parser[4] -= 1
        return finish_node(result, parser)
    elif match(parser, "!"):
        call expect(parser, "[", "E1109", "expected List literal after !")
        items = []
        if not match(parser, "]"):
            loop:
                items.append(parse_expression(parser))
                if match(parser, "]"):
                    break
                end
                call expect(parser, ",", "E1110", "expected comma in RealArray literal")
            end
        end
        result = node("real_array", token)
        result["items"] = items
        return finish_node(result, parser)
    end
    return parse_primary(parser)
end

function binary_node(operator, left, right):
    result = {"kind": "binary", "line": left["line"], "column": left["column"], "end_column": right["end_column"]}
    result["operator"] = operator
    result["left"] = left
    result["right"] = right
    return result
end

function parse_power(parser):
    left = parse_unary(parser)
    if match(parser, "^"):
        parser[4] += 1
        if parser[4] > 256:
            call fail_at(parser, current(parser), "E1112", "power nesting exceeds 256 levels", "split the expression into smaller statements")
        end
        right = parse_power(parser)
        parser[4] -= 1
        return binary_node("^", left, right)
    end
    return left
end

function parse_factor(parser):
    left = parse_power(parser)
    loop:
        operator = current(parser)["value"]
        if operator != "*" and operator != "/" and operator != "//" and operator != "%":
            break
        end
        call advance(parser)
        left = binary_node(operator, left, parse_power(parser))
    end
    return left
end

function parse_term(parser):
    left = parse_factor(parser)
    loop:
        operator = current(parser)["value"]
        if operator != "+" and operator != "-":
            break
        end
        call advance(parser)
        left = binary_node(operator, left, parse_factor(parser))
    end
    return left
end

function parse_shift(parser):
    left = parse_term(parser)
    loop:
        operator = current(parser)["value"]
        if operator != "<<" and operator != ">>":
            break
        end
        call advance(parser)
        left = binary_node(operator, left, parse_term(parser))
    end
    return left
end

function parse_bitand(parser):
    left = parse_shift(parser)
    while match(parser, "&"):
        left = binary_node("&", left, parse_shift(parser))
    end
    return left
end

function parse_bitxor(parser):
    left = parse_bitand(parser)
    while match(parser, "~"):
        left = binary_node("~", left, parse_bitand(parser))
    end
    return left
end

function parse_bitor(parser):
    left = parse_bitxor(parser)
    while match(parser, "|"):
        left = binary_node("|", left, parse_bitxor(parser))
    end
    return left
end

function parse_compare(parser):
    operands = [parse_bitor(parser)]
    operators = []
    loop:
        operator = current(parser)["value"]
        if operator != "==" and operator != "!=" and operator != "<" and operator != "<=" and operator != ">" and operator != ">=" and operator != "in" and operator != "not" and operator != "is":
            break
        end
        call advance(parser)
        if operator == "not":
            call expect(parser, "in", "E1111", "expected in after not")
            operator = "not in"
        elif operator == "is" and match(parser, "not"):
            operator = "is not"
        end
        operators.append(operator)
        operands.append(parse_bitor(parser))
    end
    if len(operators) == 0:
        return operands[0]
    end
    result = {"kind": "compare", "line": operands[0]["line"], "column": operands[0]["column"], "end_column": operands[len(operands) - 1]["end_column"]}
    result["operators"] = operators
    result["operands"] = operands
    return result
end

function parse_and(parser):
    left = parse_compare(parser)
    while match(parser, "and"):
        left = binary_node("and", left, parse_compare(parser))
    end
    return left
end

function parse_or(parser):
    left = parse_and(parser)
    while match(parser, "or"):
        left = binary_node("or", left, parse_and(parser))
    end
    return left
end

function parse_expression(parser):
    outer = parser[6] == 0
    if outer:
        parser[7] = parser[1]
    end
    parser[6] += 1
    result = parse_or(parser)
    parser[6] -= 1
    if outer and parser[1] - parser[7] > 1024:
        call fail_at(parser, current(parser), "E1118", "expression exceeds the 1024-token complexity limit", "split the expression into intermediate values")
    end
    return result
end

function consume_line_end(parser):
    if check_kind(parser, "newline"):
        call skip_newlines(parser)
    elif not check_kind(parser, "eof"):
        call fail_at(parser, current(parser), "E1201", "unexpected token after statement", "start a new statement on the next line")
    end
end

function consume_colon_line(parser):
    call match(parser, ":")
    if not check_kind(parser, "newline") and not check_kind(parser, "eof"):
        call fail_at(parser, current(parser), "E1202", "expected end of block header", "move the block body to the next line")
    end
    call skip_newlines(parser)
end

function block(parser, terminators):
    parser[5] += 1
    if parser[5] > 256:
        call fail_at(parser, current(parser), "E1200", "block nesting exceeds 256 levels", "split the program into functions")
    end
    statements = []
    call skip_newlines(parser)
    while not check_kind(parser, "eof"):
        if check_kind(parser, "name") and current(parser)["value"] in terminators:
            break
        end
        statements.append(parse_statement(parser))
        call skip_newlines(parser)
    end
    parser[5] -= 1
    return statements
end

function parse_function(parser, opening):
    name = expect_kind(parser, "name", "E1203", "expected function name")
    call expect(parser, "(", "E1204", "expected parameter list")
    parameters = []
    if not match(parser, ")"):
        loop:
            parameter = expect_kind(parser, "name", "E1205", "expected parameter name")
            parameters.append(parameter["value"])
            if len(parameters) > 256:
                call fail_at(parser, parameter, "E1233", "function has more than 256 parameters", "split the interface into structured values")
            end
            if match(parser, ")"):
                break
            end
            call expect(parser, ",", "E1206", "expected comma between parameters")
        end
    end
    call consume_colon_line(parser)
    body = block(parser, ["end"])
    call expect(parser, "end", "E1207", "function block has no end")
    call consume_line_end(parser)
    result = node("function", opening)
    result["name"] = name["value"]
    result["parameters"] = parameters
    result["body"] = body
    return finish_node(result, parser)
end

function parse_if(parser, opening):
    branches = []
    condition = parse_expression(parser)
    call consume_colon_line(parser)
    branches.append([condition, block(parser, ["elif", "else", "end"])])
    while match(parser, "elif"):
        condition = parse_expression(parser)
        call consume_colon_line(parser)
        branches.append([condition, block(parser, ["elif", "else", "end"])])
    end
    otherwise = []
    if match(parser, "else"):
        call consume_colon_line(parser)
        otherwise = block(parser, ["end"])
    end
    call expect(parser, "end", "E1208", "if block has no end")
    call consume_line_end(parser)
    result = node("if", opening)
    result["branches"] = branches
    result["otherwise"] = otherwise
    return finish_node(result, parser)
end

function parse_loop_block(parser, opening, kind):
    result = node(kind, opening)
    if kind == "while":
        result["condition"] = parse_expression(parser)
    elif kind == "for":
        name = expect_kind(parser, "name", "E1209", "expected loop variable")
        call expect(parser, "in", "E1210", "expected in after loop variable")
        result["name"] = name["value"]
        result["iterable"] = parse_expression(parser)
    end
    call consume_colon_line(parser)
    result["body"] = block(parser, ["end"])
    call expect(parser, "end", "E1211", kind + " block has no end")
    call consume_line_end(parser)
    return finish_node(result, parser)
end

function parse_try_block(parser, opening, safe_mode):
    call consume_colon_line(parser)
    terminators = ["end"]
    if not safe_mode:
        terminators = ["else", "end"]
    end
    body = block(parser, terminators)
    otherwise = []
    if not safe_mode:
        if match(parser, "else"):
            call consume_colon_line(parser)
            otherwise = block(parser, ["end"])
        end
    end
    call expect(parser, "end", "E1227", "error-handling block has no end")
    call consume_line_end(parser)
    result = node("safe", opening)
    if not safe_mode:
        result["kind"] = "try"
    end
    result["body"] = body
    result["otherwise"] = otherwise
    return finish_node(result, parser)
end

function parse_error_statement(parser, opening):
    call expect(parser, "(", "E1228", "expected Error(kind: message)")
    kind = expect_kind(parser, "name", "E1229", "expected error kind")
    call expect(parser, ":", "E1230", "expected colon after error kind")
    message = parse_expression(parser)
    call expect(parser, ")", "E1231", "unclosed Error statement")
    call consume_line_end(parser)
    result = node("error", opening)
    result["error_kind"] = kind["value"]
    result["message"] = message
    return finish_node(result, parser)
end

function parse_class(parser, opening):
    name = expect_kind(parser, "name", "E1212", "expected class name")
    condition = None
    parent = None
    if match(parser, "("):
        class_argument = parse_expression(parser)
        call expect(parser, ")", "E1213", "unclosed class condition")
        # `class Child(Parent)` is single inheritance. Keep the historical
        # `class Name(True)` conditional spelling working while existing source
        # migrates to the simpler `class Name:` form.
        if class_argument["kind"] == "literal" and class_argument["literal_kind"] == "name":
            condition = class_argument
        else:
            parent = class_argument
        end
    end
    call consume_colon_line(parser)
    body = block(parser, ["end"])
    call expect(parser, "end", "E1214", "class block has no end")
    call consume_line_end(parser)
    result = node("class", opening)
    result["name"] = name["value"]
    result["condition"] = condition
    result["parent"] = parent
    result["body"] = body
    return finish_node(result, parser)
end

function parse_statement(parser):
    opening = current(parser)
    if match(parser, "function"):
        return parse_function(parser, opening)
    elif match(parser, "if"):
        return parse_if(parser, opening)
    elif match(parser, "while"):
        return parse_loop_block(parser, opening, "while")
    elif match(parser, "for"):
        return parse_loop_block(parser, opening, "for")
    elif match(parser, "loop"):
        return parse_loop_block(parser, opening, "loop")
    elif match(parser, "class"):
        return parse_class(parser, opening)
    elif match(parser, "safe"):
        return parse_try_block(parser, opening, True)
    elif match(parser, "try"):
        return parse_try_block(parser, opening, False)
    elif match(parser, "Error"):
        return parse_error_statement(parser, opening)
    elif match(parser, "print") or match(parser, "printl"):
        formatted = opening["value"] == "printl"
        expressions = []
        if not check_kind(parser, "newline") and not check_kind(parser, "eof"):
            loop:
                expressions.append(parse_expression(parser))
                if len(expressions) > 1024:
                    call fail_at(parser, current(parser), "E1234", "print statement has more than 1024 values", "split the output into multiple statements")
                end
                if not match(parser, ","):
                    break
                end
            end
        end
        if formatted and len(expressions) == 1 and expressions[0]["kind"] == "literal" and expressions[0]["literal_kind"] == "string":
            expressions[0] = interpolation_value(parser, expressions[0]["value"], expressions[0])
            formatted = False
        end
        call consume_line_end(parser)
        result = node("print", opening)
        result["formatted"] = formatted
        result["expressions"] = expressions
        return finish_node(result, parser)
    elif match(parser, "return"):
        expression = None
        if not check_kind(parser, "newline") and not check_kind(parser, "eof"):
            expression = parse_expression(parser)
        end
        call consume_line_end(parser)
        result = node("return", opening)
        result["expression"] = expression
        return finish_node(result, parser)
    elif match(parser, "break") or match(parser, "continue"):
        call consume_line_end(parser)
        return node(opening["value"], opening)
    elif match(parser, "load"):
        module = expect_kind(parser, "name", "E1215", "expected module name")
        name = module["value"]
        components = 1
        while match(parser, "."):
            name += "." + expect_kind(parser, "name", "E1216", "expected module path component")["value"]
            components += 1
            if components > 64 or len(name) > 1024:
                call fail_at(parser, current(parser), "E1235", "module path is too long", "use at most 64 components and 1024 characters")
            end
        end
        module_parts = name.split(".")
        alias = module_parts[len(module_parts) - 1]
        if match(parser, "as"):
            alias = expect_kind(parser, "name", "E1232", "expected module alias")["value"]
        end
        call consume_line_end(parser)
        result = node("load", opening)
        result["module"] = name
        result["symbol"] = None
        result["alias"] = alias
        return result
    elif match(parser, "from"):
        module = expect_kind(parser, "name", "E1217", "expected module name")
        name = module["value"]
        components = 1
        while match(parser, "."):
            name += "." + expect_kind(parser, "name", "E1218", "expected module path component")["value"]
            components += 1
            if components > 64 or len(name) > 1024:
                call fail_at(parser, current(parser), "E1235", "module path is too long", "use at most 64 components and 1024 characters")
            end
        end
        call expect(parser, "load", "E1219", "expected load in selective import")
        symbol = expect_kind(parser, "name", "E1220", "expected imported symbol")
        alias = symbol["value"]
        if match(parser, "as"):
            alias = expect_kind(parser, "name", "E1221", "expected import alias")["value"]
        end
        call consume_line_end(parser)
        result = node("load", opening)
        result["module"] = name
        result["symbol"] = symbol["value"]
        result["alias"] = alias
        return result
    elif match(parser, "ctype"):
        visibility = expect_kind(parser, "name", "E1222", "expected Public or Private")
        if visibility["value"] != "Public" and visibility["value"] != "Private":
            call fail_at(parser, visibility, "E1223", "invalid class visibility", "use ctype Public or ctype Private")
        end
        call consume_line_end(parser)
        result = node("ctype", opening)
        result["visibility"] = visibility["value"]
        return result
    elif match(parser, "del"):
        call expect(parser, "(", "E1224", "expected parenthesized del target")
        target = parse_expression(parser)
        call expect(parser, ")", "E1225", "unclosed del target")
        call consume_line_end(parser)
        result = node("delete", opening)
        result["target"] = target
        return result
    elif check(parser, "end") or check(parser, "elif") or check(parser, "else"):
        call fail_at(parser, opening, "E1226", "unexpected block terminator", "remove it or add its opening block")
    end

    call_prefix = match(parser, "call")
    left = parse_expression(parser)
    operator = current(parser)["value"]
    if operator == "=" or operator == "+=" or operator == "-=" or operator == "*=" or operator == "/=" or operator == "%=" or operator == "&=" or operator == "|=" or operator == "~=" or operator == "<<=" or operator == ">>=":
        call advance(parser)
        value = parse_expression(parser)
        call consume_line_end(parser)
        result = node("assign", opening)
        result["target"] = left
        result["operator"] = operator
        result["value"] = value
        return finish_node(result, parser)
    end
    call consume_line_end(parser)
    result = node("expression", opening)
    result["expression"] = left
    result["discard"] = call_prefix
    return finish_node(result, parser)
end

function parse(path, source):
    parser = state(path, source)
    program = block(parser, [])
    if not check_kind(parser, "eof"):
        call fail_at(parser, current(parser), "E1299", "unexpected token at top level", "check block nesting")
    end
    return program
end
