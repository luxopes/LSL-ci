# Token-span recursive-descent parser for the direct compiler.

load diagnostics
load lexer

function state(path, source):
    return [lexer.tokenize(path, source), 0, path, source.split(chr(10))]
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
    if line < 1 or line > len(parser[3]):
        return ""
    end
    return parser[3][line - 1]
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

function parse_primary(parser):
    token = advance(parser)
    kind = token["kind"]
    value = token["value"]
    if kind == "string" or kind == "number":
        result = node("literal", token)
        result["literal_kind"] = kind
        result["value"] = value
    elif value == "True" or value == "False" or value == "None":
        result = node("literal", token)
        result["literal_kind"] = "name"
        result["value"] = value
    elif kind == "name":
        result = node("name", token)
        result["name"] = value
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
            if match(parser, ":"):
                index_node["start"] = None
                if check(parser, "]"):
                    index_node["stop"] = None
                else:
                    index_node["stop"] = parse_expression(parser)
                end
                index_node["kind"] = "slice"
            else:
                start = parse_expression(parser)
                if match(parser, ":"):
                    index_node["kind"] = "slice"
                    index_node["start"] = start
                    if check(parser, "]"):
                        index_node["stop"] = None
                    else:
                        index_node["stop"] = parse_expression(parser)
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
    if match(parser, "not") or match(parser, "-") or match(parser, "+"):
        result = node("unary", token)
        result["operator"] = token["value"]
        result["operand"] = parse_unary(parser)
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
    if match(parser, "**"):
        return binary_node("**", left, parse_power(parser))
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

function parse_compare(parser):
    operands = [parse_term(parser)]
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
        operands.append(parse_term(parser))
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
    return parse_or(parser)
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
    statements = []
    call skip_newlines(parser)
    while not check_kind(parser, "eof"):
        if check_kind(parser, "name") and current(parser)["value"] in terminators:
            break
        end
        statements.append(parse_statement(parser))
        call skip_newlines(parser)
    end
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
    if match(parser, "("):
        condition = parse_expression(parser)
        call expect(parser, ")", "E1213", "unclosed class condition")
    end
    call consume_colon_line(parser)
    body = block(parser, ["end"])
    call expect(parser, "end", "E1214", "class block has no end")
    call consume_line_end(parser)
    result = node("class", opening)
    result["name"] = name["value"]
    result["condition"] = condition
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
                if not match(parser, ","):
                    break
                end
            end
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
        while match(parser, "."):
            name += "." + expect_kind(parser, "name", "E1216", "expected module path component")["value"]
        end
        call consume_line_end(parser)
        result = node("load", opening)
        result["module"] = name
        result["symbol"] = None
        result["alias"] = None
        return result
    elif match(parser, "from"):
        module = expect_kind(parser, "name", "E1217", "expected module name")
        name = module["value"]
        while match(parser, "."):
            name += "." + expect_kind(parser, "name", "E1218", "expected module path component")["value"]
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
    if operator == "=" or operator == "+=" or operator == "-=" or operator == "*=" or operator == "/=" or operator == "%=":
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
