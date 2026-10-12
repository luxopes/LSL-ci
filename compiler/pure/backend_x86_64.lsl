# Instrukční backend x86_64: registry, zásobník a společný objekt programu.

load abi_x86_64
load assembler_x86_64 as assembler
load bytes
load object_code
load relocations_x86_64
load runtime
load semantic
load validation
load value_abi
load x86_64

function label_name(generator, prefix):
    counter = generator["counter"]
    generator["counter"] = counter + 1
    return prefix + "_" + String(counter)
end

function comparison_opcode(operator):
    if operator == "==" or operator == "is":
        return 148
    elif operator == "!=" or operator == "is not":
        return 149
    elif operator == "<":
        return 156
    elif operator == "<=":
        return 158
    elif operator == ">":
        return 159
    elif operator == ">=":
        return 157
    end
    return -1
end

function align_data(generator):
    data = ByteArray(generator["data"])
    while len(data) % 8 != 0:
        call data.append(0)
    end
end

function emit_string_pointer(generator, text):
    if text in generator["string_offsets"]:
        offset = generator["string_offsets"][text]
    else:
        call align_data(generator)
        offset = len(generator["data"])
        payload = bytes.utf8(text)
        data = ByteArray(generator["data"])
        call bytes.extend(data, bytes.little(1, 8))
        call bytes.extend(data, bytes.little(len(payload), 8))
        call bytes.extend(data, payload)
        call data.append(0)
        generator["string_offsets"][text] = offset
    end
    lea_start = assembler.position(generator["builder"])
    call assembler.emit(generator["builder"], x86_64.lea_rip(0, 0))
    generator["relocations"].append([lea_start + 3, lea_start + 7, offset])
    call assembler.emit(generator["builder"], x86_64.move_reg_reg(7, 0))
    call assembler.relative(generator["builder"], [232], "runtime_string_clone")
end

function float_bits(text):
    # Parse via the runtime Float path (hardware doubles) and read the IEEE-754
    # bit pattern. The old exact-integer algorithm overflowed Int64 for large
    # exponents (e.g. 1e20 looped forever, 1e300 gave 0); doubles handle the
    # full range including Infinity for overflow.
    return __lsl_float_bits(__lsl_parse_float(text))
end

function emit_truth(generator):
    call assembler.emit(generator["builder"], x86_64.move_reg_reg(7, 0))
    call assembler.relative(generator["builder"], [232], "runtime_truth")
end

function maybe_collection(value_type):
    return value_type == "List" or value_type == "Tuple" or value_type == "RealArray" or value_type == "IntArray" or value_type == "FloatArray" or value_type == "ByteArray" or value_type == "Dictionary" or value_type == "Set" or value_type == "Any"
end

function emit_condition(generator, syntax):
    # Skip runtime_truth (a call + is_heap_object probe) when the expression
    # already yields a 0/1 Bool.
    call emit_expression(generator, syntax)
    if not semantic.condition_is_bool(syntax):
        if semantic.infer_expression_type(syntax, generator["types"], generator["function_returns"]) == "Bool":
            # Preserve the following basic-block addresses while replacing the
            # old mov+runtime_truth call. On Zen, shifting densely generated
            # branch targets proved more expensive than one architectural NOP.
            call assembler.emit(generator["builder"], [15, 31, 132, 0, 0, 0, 0, 0])
        else:
            call emit_truth(generator)
        end
    end
end

function power_of_two_exponent(syntax):
    # k if syntax is a positive power-of-two Int literal (2^k), else -1.
    if syntax["kind"] != "literal":
        return -1
    end
    if syntax["literal_kind"] != "number":
        return -1
    end
    value = syntax["value"]
    if value.find(".") >= 0 or value.find("e") >= 0 or value.find("E") >= 0:
        return -1
    end
    number = semantic.integer_literal(syntax)
    if number <= 0:
        return -1
    end
    exponent = 0
    while number > 1:
        if number % 2 != 0:
            return -1
        end
        number = number // 2
        exponent += 1
    end
    return exponent
end

function magic_signed(divisor):
    return semantic.magic_signed(divisor)
end

function inverted_branch(operator):
    # jcc bytes that jump when the comparison is FALSE.
    if operator == "==" or operator == "is":
        return [15, 133]
    elif operator == "!=" or operator == "is not":
        return [15, 132]
    elif operator == "<":
        return [15, 141]
    elif operator == "<=":
        return [15, 143]
    elif operator == ">":
        return [15, 142]
    elif operator == ">=":
        return [15, 140]
    end
    return []
end

function direct_branch(operator):
    # jcc bytes that jump when the comparison is TRUE.
    if operator == "==" or operator == "is":
        return [15, 132]
    elif operator == "!=" or operator == "is not":
        return [15, 133]
    elif operator == "<":
        return [15, 140]
    elif operator == "<=":
        return [15, 142]
    elif operator == ">":
        return [15, 143]
    elif operator == ">=":
        return [15, 141]
    end
    return []
end

function direct_scalar_equality(left_type, right_type):
    return left_type == right_type and (left_type == "Int" or left_type == "Bool" or left_type == "None")
end

function emit_compare_branch(generator, syntax, target_label, branch_when_true):
    # Static scalar comparisons branch directly on flags, skipping the
    # setcc/movzx/cmp-0 materialization of an intermediate Bool.
    if syntax["kind"] != "compare":
        return False
    end
    if len(syntax["operators"]) != 1:
        return False
    end
    operator = syntax["operators"][0]
    ordered = operator == "<" or operator == "<=" or operator == ">" or operator == ">="
    equality = operator == "==" or operator == "!=" or operator == "is" or operator == "is not"
    if not ordered and not equality:
        return False
    end
    left = syntax["operands"][0]
    right = syntax["operands"][1]
    left_type = semantic.infer_expression_type(left, generator["types"], generator["function_returns"])
    right_type = semantic.infer_expression_type(right, generator["types"], generator["function_returns"])
    if equality:
        if not direct_scalar_equality(left_type, right_type):
            return False
        end
    elif left_type == "Float" or right_type == "Float" or left_type == "Any" or right_type == "Any":
        return False
    end
    output = generator["builder"]
    right_constant = semantic.constant_int_expression(right)
    if right_constant[0] and x86_64.fits_signed32(right_constant[1]):
        call emit_expression(generator, left)
        call assembler.emit(output, x86_64.cmp_reg_imm32(0, right_constant[1]))
        if branch_when_true:
            call assembler.relative(output, direct_branch(operator), target_label)
        else:
            call assembler.relative(output, inverted_branch(operator), target_label)
        end
        return True
    elif is_int_leaf(generator, right):
        call emit_expression(generator, left)
        call emit_int_leaf(generator, right, 6)
    elif is_int_leaf(generator, left):
        call emit_expression(generator, right)
        call assembler.emit(output, x86_64.move_reg_reg(6, 0))
        call emit_int_leaf(generator, left, 0)
    else:
        call emit_expression(generator, left)
        call assembler.emit(output, x86_64.push(0))
        call emit_expression(generator, right)
        call assembler.emit(output, x86_64.move_reg_reg(6, 0))
        call assembler.emit(output, x86_64.pop(0))
    end
    call assembler.emit(output, x86_64.cmp_reg_reg(0, 6))
    if branch_when_true:
        call assembler.relative(output, direct_branch(operator), target_label)
    else:
        call assembler.relative(output, inverted_branch(operator), target_label)
    end
    return True
end

function emit_branch_when(generator, syntax, target_label, branch_when_true):
    # Lower short-circuit Boolean trees as control flow. Previously an `and`
    # or `or` in an if/while materialized one or more temporary 0/1 values with
    # setcc and then compared the final value with zero. Move generators and
    # parsers spend much of their time in exactly these compound conditions.
    constant = semantic.constant_truth_expression(syntax)
    if constant[0]:
        if constant[1] == branch_when_true:
            call assembler.relative(generator["builder"], [233], target_label)
        end
        return
    end
    kind = syntax["kind"]
    if kind == "unary" and syntax["operator"] == "not":
        call emit_branch_when(generator, syntax["operand"], target_label, not branch_when_true)
        return
    elif kind == "binary" and syntax["operator"] == "and":
        if branch_when_true:
            skip_label = label_name(generator, "and_branch_skip")
            call emit_branch_when(generator, syntax["left"], skip_label, False)
            call emit_branch_when(generator, syntax["right"], target_label, True)
            call assembler.label(generator["builder"], skip_label)
        else:
            call emit_branch_when(generator, syntax["left"], target_label, False)
            call emit_branch_when(generator, syntax["right"], target_label, False)
        end
        return
    elif kind == "binary" and syntax["operator"] == "or":
        if branch_when_true:
            call emit_branch_when(generator, syntax["left"], target_label, True)
            call emit_branch_when(generator, syntax["right"], target_label, True)
        else:
            skip_label = label_name(generator, "or_branch_skip")
            call emit_branch_when(generator, syntax["left"], skip_label, True)
            call emit_branch_when(generator, syntax["right"], target_label, False)
            call assembler.label(generator["builder"], skip_label)
        end
        return
    end
    if emit_compare_branch(generator, syntax, target_label, branch_when_true):
        return
    end
    call emit_condition(generator, syntax)
    call assembler.emit(generator["builder"], x86_64.cmp_reg_imm8(0, 0))
    if branch_when_true:
        call assembler.relative(generator["builder"], [15, 133], target_label)
    else:
        call assembler.relative(generator["builder"], [15, 132], target_label)
    end
end

function emit_branch_if_false(generator, syntax, target_label):
    call emit_branch_when(generator, syntax, target_label, False)
    return True
end

function is_int_leaf(generator, syntax):
    return semantic.integer_leaf(generator, syntax)
end

function is_fast_int_index(generator, syntax):
    return semantic.fast_integer_index(generator, syntax)
end

function is_fast_int_value(generator, syntax):
    return semantic.fast_integer_value(generator, syntax)
end

function count_fast_intarray_targets(generator, syntax, counts):
    if syntax == None:
        return
    end
    kind = syntax["kind"]
    if kind == "index":
        target = syntax["target"]
        if target["kind"] == "name" and semantic.infer_expression_type(target, generator["types"], generator["function_returns"]) == "IntArray" and is_fast_int_index(generator, syntax["index"]):
            name = target["name"]
            counts[name] = counts.get(name, 0) + 1
        end
    elif kind == "binary":
        call count_fast_intarray_targets(generator, syntax["left"], counts)
        call count_fast_intarray_targets(generator, syntax["right"], counts)
    elif kind == "unary":
        call count_fast_intarray_targets(generator, syntax["operand"], counts)
    end
end

function repeated_fast_intarray(generator, syntax):
    counts = {}
    call count_fast_intarray_targets(generator, syntax, counts)
    selected = ""
    selected_count = 1
    for name in counts.keys():
        if counts[name] > selected_count:
            selected = name
            selected_count = counts[name]
        end
    end
    return selected
end

function local_register(generator, name):
    # Register-resident locals map to callee-saved r12-r15; -1 otherwise.
    registers = generator.get("register_locals", {})
    if name in registers:
        return registers[name]
    end
    return -1
end

function emit_load_local(generator, register, name, syntax=None):
    # Named variable read: register home, stack slot, or a global in the
    # state block (rbx-relative; globals no longer pin r12).
    home = local_register(generator, name)
    if home >= 0:
        if home != register:
            call assembler.emit(generator["builder"], x86_64.move_reg_reg(register, home))
        end
    elif name in generator["variables"]:
        call assembler.emit(generator["builder"], x86_64.load_stack(register, generator["variables"][name]))
    else:
        # A function can run before module initialization (also via callbacks).
        # Locals are proved statically; global reads need a guard at the actual
        # read, not at function entry where an untaken branch could reject it.
        if name in generator.get("global_reads", {}):
            failure = label_name(generator, "uninitialized_global")
            call assembler.emit(generator["builder"], x86_64.cmp_memory_imm8(3, generator["global_flags"][name], 0))
            call assembler.relative(generator["builder"], [15, 132], failure)
            location = syntax
            if location == None:
                location = generator["global_reads"][name]
            end
            generator["global_handlers"].append([failure, location, generator["error_label"]])
        end
        call assembler.emit(generator["builder"], x86_64.load_memory(register, 3, generator["global_variables"][name]))
    end
end

function emit_store_local(generator, name, register, initialize=False):
    home = local_register(generator, name)
    if home >= 0:
        if home != register:
            call assembler.emit(generator["builder"], x86_64.move_reg_reg(home, register))
        end
    elif name in generator["variables"]:
        call assembler.emit(generator["builder"], x86_64.store_stack(generator["variables"][name], register))
    else:
        call assembler.emit(generator["builder"], x86_64.store_memory(3, generator["global_variables"][name], register))
        if initialize or name in generator.get("mutable_globals", {}):
            call assembler.emit(generator["builder"], x86_64.store_memory_imm32(3, generator["global_flags"][name], 1))
        end
    end
end

function scan_local_uses(node, counts, excluded, weight, ranges, clock):
    # Weighted name use counts, the names codegen addresses by stack slot
    # directly (class slots and deleted names), and live
    # intervals ranges[name] = [first, last] over a statement clock (clock[0]
    # advances per statement; names used inside a loop are widened to the
    # whole loop so a register can only be shared by disjoint lifetimes).
    if node == None:
        return
    end
    if type(node) == "List":
        for item in node:
            call scan_local_uses(item, counts, excluded, weight, ranges, clock)
        end
        return
    end
    if type(node) != "Dictionary":
        return
    end
    kind = node.get("kind", "")
    if kind == "name":
        name = node["name"]
        counts[name] = counts.get(name, 0) + weight
        now = clock[0]
        if name in ranges:
            if now > ranges[name][1]:
                ranges[name][1] = now
            end
        else:
            ranges[name] = [now, now]
        end
        return
    end
    if kind == "literal":
        return
    end
    is_statement = kind == "assign" or kind == "expression" or kind == "return" or kind == "if" or kind == "while" or kind == "loop" or kind == "for" or kind == "try" or kind == "safe" or kind == "unsafe" or kind == "error" or kind == "delete" or kind == "print" or kind == "class" or kind == "break" or kind == "continue"
    if is_statement:
        clock[0] = clock[0] + 1
    end
    loop_start = clock[0]
    body_weight = weight
    if kind == "while" or kind == "loop" or kind == "for":
        body_weight = weight * 4
        if kind == "for":
            for_is_range = False
            for_iterable = node["iterable"]
            if for_iterable["kind"] == "call":
                if for_iterable["target"]["kind"] == "name":
                    if for_iterable["target"]["name"] == "rang" or for_iterable["target"]["name"] == "range":
                        for_is_range = True
                    end
                end
            end
            if for_is_range:
                # These accesses are synthesized by emit_statements and do
                # not otherwise appear as name nodes in the source AST.
                call scan_local_uses({"kind": "name", "name": node["name"]}, counts, excluded, body_weight * 3, ranges, clock)
                call scan_local_uses({"kind": "name", "name": node["iterator_name"]}, counts, excluded, body_weight, ranges, clock)
                if len(for_iterable["arguments"]) == 3:
                    call scan_local_uses({"kind": "name", "name": node["index_name"]}, counts, excluded, body_weight * 2, ranges, clock)
                end
            else:
                # Collection objects must remain visible to the stack-scanning
                # GC. Their unboxed index and item value are safe in registers.
                excluded[node["iterator_name"]] = True
                call scan_local_uses({"kind": "name", "name": node["index_name"]}, counts, excluded, body_weight * 4, ranges, clock)
                call scan_local_uses({"kind": "name", "name": node["name"]}, counts, excluded, body_weight, ranges, clock)
            end
        end
    elif kind == "class":
        excluded[node["name"]] = True
    elif kind == "delete":
        if node["target"]["kind"] == "name":
            excluded[node["target"]["name"]] = True
        end
    end
    # A compound assignment reads and then writes its target. Count that
    # second access so a loop-carried accumulator reaches the same register
    # threshold as the equivalent `value = value + expression` form.
    if kind == "assign" and node["operator"] != "=":
        call scan_local_uses(node["target"], counts, excluded, weight, ranges, clock)
    end
    for field in ["target", "value", "condition", "expression", "iterable", "left", "right", "operand", "index", "start", "stop", "step", "message", "parent"]:
        if field in node:
            call scan_local_uses(node[field], counts, excluded, weight, ranges, clock)
        end
    end
    for field in ["arguments", "items", "operands", "expressions", "entries", "otherwise"]:
        if field in node:
            call scan_local_uses(node[field], counts, excluded, weight, ranges, clock)
        end
    end
    if "body" in node:
        call scan_local_uses(node["body"], counts, excluded, body_weight, ranges, clock)
    end
    if kind == "comprehension":
        call scan_local_uses(node["result"], counts, excluded, weight, ranges, clock)
    end
    if "branches" in node:
        for branch in node["branches"]:
            call scan_local_uses(branch[0], counts, excluded, weight, ranges, clock)
            call scan_local_uses(branch[1], counts, excluded, weight, ranges, clock)
        end
    end
    if kind == "while" or kind == "loop" or kind == "for":
        # Widen every name touched inside the loop to the loop's full span.
        clock[0] = clock[0] + 1
        loop_end = clock[0]
        for name in ranges.keys():
            interval = ranges[name]
            if interval[1] >= loop_start and interval[0] <= loop_end:
                if interval[0] > loop_start:
                    interval[0] = loop_start
                end
                if interval[1] < loop_end:
                    interval[1] = loop_end
                end
            end
        end
    end
end

function choose_register_locals(declaration, variables, types):
    # Statically Int/Bool locals (parameters included) with weighted use count
    # >= 8 get r12-r15; a register is shared by locals whose live
    # intervals (statement clock, loops widened) do not overlap, hottest
    # first.
    counts = {}
    excluded = {}
    ranges = {}
    clock = [0]
    for parameter in declaration["parameters"]:
        ranges[parameter] = [0, 0]
    end
    call scan_local_uses(declaration["body"], counts, excluded, 1, ranges, clock)
    candidates = []
    for name in variables.keys():
        if name in excluded or name not in counts or name not in types or name not in ranges:
            continue
        end
        if types[name] != "Int" and types[name] != "Bool":
            continue
        end
        # Below this weight the save/restore in the prologue costs more than
        # the register saves; loop-carried locals score 4+ per use.
        if counts[name] < 8:
            continue
        end
        candidates.append([counts[name], name])
    end
    chosen = {}
    occupancy = {}
    for register in abi_x86_64.LOCAL_REGISTERS:
        occupancy[register] = []
    end
    while len(candidates) > 0:
        best = 0
        index = 1
        while index < len(candidates):
            if candidates[index][0] > candidates[best][0]:
                best = index
            end
            index += 1
        end
        name = candidates[best][1]
        call candidates.pop(best)
        interval = ranges[name]
        for register in abi_x86_64.LOCAL_REGISTERS:
            if name in chosen:
                break
            end
            free = True
            for other in occupancy[register]:
                if interval[0] <= other[1] and other[0] <= interval[1]:
                    free = False
                end
            end
            if free:
                chosen[name] = register
                occupancy[register].append([interval[0], interval[1]])
            end
        end
    end
    return chosen
end

function pure_int_literal(syntax):
    return syntax["kind"] == "literal" and syntax["literal_kind"] == "number" and syntax["value"].find(".") < 0 and syntax["value"].find("e") < 0 and syntax["value"].find("E") < 0
end

function pure_int_immediate(syntax):
    # Literal usable as an imm32 operand (and/or/xor/add/sub/imul forms).
    return pure_int_literal(syntax) and x86_64.fits_signed32(semantic.integer_literal(syntax))
end

function pure_int_need(generator, syntax):
    # Register need of a pure Int expression tree (Sethi-Ullman), or -1 when
    # the tree is not pure: literals, Int names, unchecked IntArray reads and
    # + - * & | ~ << >> plus unary -/~, all without calls or dynamic values.
    kind = syntax["kind"]
    if kind == "literal":
        if pure_int_literal(syntax):
            return 1
        end
        return -1
    elif kind == "name":
        if is_int_leaf(generator, syntax) and semantic.infer_expression_type(syntax, generator["types"], generator["function_returns"]) == "Int":
            return 1
        end
        return -1
    elif kind == "index":
        if not generator.get("unchecked_intarray", False):
            return -1
        end
        target = syntax["target"]
        if target["kind"] != "name" or not is_int_leaf(generator, target):
            return -1
        end
        if semantic.infer_expression_type(target, generator["types"], generator["function_returns"]) != "IntArray":
            return -1
        end
        index_need = pure_int_need(generator, syntax["index"])
        if index_need < 0:
            return -1
        end
        if pure_int_literal(syntax["index"]) and x86_64.fits_signed32(semantic.integer_literal(syntax["index"]) * 8):
            return 1
        end
        return index_need + 1
    elif kind == "unary":
        if syntax["operator"] != "-" and syntax["operator"] != "~":
            return -1
        end
        return pure_int_need(generator, syntax["operand"])
    elif kind == "binary":
        operator = syntax["operator"]
        if operator != "+" and operator != "-" and operator != "*" and operator != "&" and operator != "|" and operator != "~" and operator != "<<" and operator != ">>":
            return -1
        end
        left = syntax["left"]
        right = syntax["right"]
        left_need = pure_int_need(generator, left)
        if left_need < 0:
            return -1
        end
        if operator == "<<" or operator == ">>":
            if pure_int_literal(right):
                count = semantic.integer_literal(right)
                if count < 0 or count > 63:
                    return -1
                end
                return left_need
            end
            # Variable count: the count needs rcx on top of the value. A
            # constant negative count (unary minus on a literal) stays on the
            # generic path so it is still rejected at compile time.
            if right["kind"] == "unary" and pure_int_literal(right["operand"]):
                return -1
            end
            right_need = pure_int_need(generator, right)
            if right_need < 0:
                return -1
            end
            if left_need > right_need + 1:
                return left_need
            end
            return right_need + 1
        end
        if pure_int_immediate(right):
            return left_need
        end
        right_need = pure_int_need(generator, right)
        if right_need < 0:
            return -1
        end
        if pure_int_immediate(left) and operator != "-":
            return right_need
        end
        if left_need == right_need:
            return left_need + 1
        end
        if left_need > right_need:
            return left_need
        end
        return right_need
    end
    return -1
end

function power_of_two_shift(value):
    # log2(value) for positive powers of two, else -1.
    if value <= 0 or (value & (value - 1)) != 0:
        return -1
    end
    shift = 0
    while (1 << shift) != value:
        shift += 1
    end
    return shift
end

function emit_pure_int_immediate(generator, operator, target, value):
    output = generator["builder"]
    if operator == "+":
        call assembler.emit(output, x86_64.add_reg_imm32(target, value))
    elif operator == "-":
        call assembler.emit(output, x86_64.sub_reg_imm(target, value))
    elif operator == "*":
        shift = power_of_two_shift(value)
        if shift >= 0:
            call assembler.emit(output, x86_64.shift_left_imm(target, shift))
        else:
            call assembler.emit(output, x86_64.imul_reg_imm(target, target, value))
        end
    elif operator == "&":
        call assembler.emit(output, x86_64.logic_reg_imm(4, target, value))
    elif operator == "|":
        call assembler.emit(output, x86_64.logic_reg_imm(1, target, value))
    elif operator == "~":
        call assembler.emit(output, x86_64.logic_reg_imm(6, target, value))
    elif operator == "<<":
        call assembler.emit(output, x86_64.shift_left_imm(target, value))
    else:
        call assembler.emit(output, x86_64.shift_right_arithmetic_imm(target, value))
    end
end

function emit_pure_int_operation(generator, operator, target, source):
    output = generator["builder"]
    if operator == "+":
        call assembler.emit(output, x86_64.add_reg_reg(target, source))
    elif operator == "-":
        call assembler.emit(output, x86_64.sub_reg_reg(target, source))
    elif operator == "*":
        call assembler.emit(output, x86_64.imul_reg_reg(target, source))
    elif operator == "&":
        call assembler.emit(output, x86_64.and_reg_reg(target, source))
    elif operator == "|":
        call assembler.emit(output, x86_64.or_reg_reg(target, source))
    else:
        call assembler.emit(output, x86_64.xor_reg_reg(target, source))
    end
end

function emit_pure_int(generator, syntax, target, pool):
    # Emit a pure Int tree into register target using the scratch registers
    # in pool (never rax unless it is the target); no push/pop, no runtime.
    output = generator["builder"]
    kind = syntax["kind"]
    if kind == "literal":
        call assembler.emit(output, x86_64.mov_imm64(target, semantic.integer_literal(syntax)))
    elif kind == "name":
        call emit_int_leaf(generator, syntax, target)
    elif kind == "index":
        if generator.get("pure_hoist_name", "") == syntax["target"]["name"]:
            pointer = generator["pure_hoist_register"]
        else:
            pointer = pool[0]
            call emit_int_leaf(generator, syntax["target"], pointer)
            call assembler.emit(output, x86_64.load_memory(pointer, pointer, 24))
        end
        if pure_int_literal(syntax["index"]) and x86_64.fits_signed32(semantic.integer_literal(syntax["index"]) * 8):
            call assembler.emit(output, x86_64.load_memory(target, pointer, semantic.integer_literal(syntax["index"]) * 8))
        else:
            call emit_pure_int(generator, syntax["index"], target, pool[1:len(pool)])
            call assembler.emit(output, x86_64.load_indexed(target, pointer, target, 3))
        end
    elif kind == "unary":
        call emit_pure_int(generator, syntax["operand"], target, pool)
        if syntax["operator"] == "-":
            call assembler.emit(output, x86_64.neg_reg(target))
        else:
            call assembler.emit(output, x86_64.not_reg(target))
        end
    else:
        operator = syntax["operator"]
        left = syntax["left"]
        right = syntax["right"]
        if operator == "<<" or operator == ">>":
            if pure_int_literal(right):
                call emit_pure_int(generator, left, target, pool)
                call emit_pure_int_immediate(generator, operator, target, semantic.integer_literal(right))
            else:
                call emit_pure_int_shift(generator, syntax, target, pool)
            end
            return
        end
        if pure_int_immediate(right):
            call emit_pure_int(generator, left, target, pool)
            call emit_pure_int_immediate(generator, operator, target, semantic.integer_literal(right))
            return
        end
        if pure_int_immediate(left) and operator != "-":
            call emit_pure_int(generator, right, target, pool)
            call emit_pure_int_immediate(generator, operator, target, semantic.integer_literal(left))
            return
        end
        scratch = pool[0]
        rest = pool[1:len(pool)]
        if pure_int_need(generator, right) > pure_int_need(generator, left):
            call emit_pure_int(generator, right, target, pool)
            call emit_pure_int(generator, left, scratch, rest)
            if operator == "-":
                call assembler.emit(output, x86_64.sub_reg_reg(scratch, target))
                call assembler.emit(output, x86_64.move_reg_reg(target, scratch))
            else:
                call emit_pure_int_operation(generator, operator, target, scratch)
            end
        else:
            call emit_pure_int(generator, left, target, pool)
            call emit_pure_int(generator, right, scratch, rest)
            call emit_pure_int_operation(generator, operator, target, scratch)
        end
    end
end

function count_pure_index_targets(syntax, counts):
    kind = syntax["kind"]
    if kind == "index":
        name = syntax["target"]["name"]
        counts[name] = counts.get(name, 0) + 1
        call count_pure_index_targets(syntax["index"], counts)
    elif kind == "unary":
        call count_pure_index_targets(syntax["operand"], counts)
    elif kind == "binary":
        call count_pure_index_targets(syntax["left"], counts)
        call count_pure_index_targets(syntax["right"], counts)
    end
end

function emit_pure_int_expression(generator, syntax, target, pool):
    # Emit a pure Int tree into target; when one IntArray is indexed more than
    # once, its data pointer is hoisted into the last pool register first.
    counts = {}
    call count_pure_index_targets(syntax, counts)
    hoisted = ""
    hoisted_count = 1
    for name in counts.keys():
        if counts[name] > hoisted_count:
            hoisted = name
            hoisted_count = counts[name]
        end
    end
    if hoisted != "" and len(pool) >= 2:
        pointer = pool[len(pool) - 1]
        call emit_int_leaf(generator, {"kind": "name", "name": hoisted}, pointer)
        call assembler.emit(generator["builder"], x86_64.load_memory(pointer, pointer, 24))
        generator["pure_hoist_name"] = hoisted
        generator["pure_hoist_register"] = pointer
        call emit_pure_int(generator, syntax, target, pool[0:len(pool) - 1])
        generator["pure_hoist_name"] = ""
    else:
        call emit_pure_int(generator, syntax, target, pool)
    end
end

function emit_pure_int_shift(generator, syntax, target, pool):
    # value << count / value >> count with a variable count: count in rcx,
    # one unsigned range check (count > 63 covers negatives) on the hot
    # path; negatives raise ValueError, wide left shifts give 0 and wide
    # right shifts saturate at 63 like the generic emitter.
    output = generator["builder"]
    operator = syntax["operator"]
    rest = []
    for register in pool:
        if register != 1:
            rest.append(register)
        end
    end
    if target == 1:
        # rcx is the shift count register; build the value elsewhere first.
        other = rest[0]
        call emit_pure_int_shift(generator, syntax, other, rest)
        call assembler.emit(output, x86_64.move_reg_reg(1, other))
        return
    end
    call emit_pure_int(generator, syntax["left"], target, rest)
    call emit_pure_int(generator, syntax["right"], 1, rest)
    shift_fast = label_name(generator, "pshift_fast")
    shift_done = label_name(generator, "pshift_done")
    shift_slow = label_name(generator, "pshift_slow")
    call assembler.emit(output, x86_64.cmp_reg_imm8(1, 63))
    call assembler.relative(output, [15, 135], shift_slow)
    call assembler.label(output, shift_fast)
    if operator == "<<":
        call assembler.emit(output, x86_64.shift_left_cl(target))
    else:
        call assembler.emit(output, x86_64.shift_right_arithmetic_cl(target))
    end
    call assembler.label(output, shift_done)
    # Cold path placed after the function's normal flow would be nicer, but
    # the emitter is single-pass; a forward jump over it keeps the hot path
    # straight.
    shift_after = label_name(generator, "pshift_after")
    call assembler.relative(output, [233], shift_after)
    call assembler.label(output, shift_slow)
    shift_wide = label_name(generator, "pshift_wide")
    call assembler.emit(output, x86_64.test_reg_reg(1, 1))
    call assembler.relative(output, [15, 137], shift_wide)
    shift_source_path = syntax.get("path", generator["path"])
    call emit_runtime_raise(generator, "ValueError: negative shift count at " + shift_source_path + ":" + String(syntax["line"]))
    call assembler.label(output, shift_wide)
    if operator == "<<":
        call assembler.emit(output, x86_64.xor_reg_reg(target, target))
    else:
        call assembler.emit(output, x86_64.mov_imm64(1, 63))
        call assembler.emit(output, x86_64.shift_right_arithmetic_cl(target))
    end
    call assembler.label(output, shift_after)
end

function pure_int_pool():
    # r10/r11 stay out: the unchecked IntArray store and atomic builtins keep
    # the array/index pair there while the value expression is emitted.
    return abi_x86_64.SCRATCH_REGISTERS
end

function pure_tree_reads_name(syntax, name):
    kind = syntax["kind"]
    if kind == "name":
        return syntax["name"] == name
    elif kind == "index":
        return pure_tree_reads_name(syntax["target"], name) or pure_tree_reads_name(syntax["index"], name)
    elif kind == "unary":
        return pure_tree_reads_name(syntax["operand"], name)
    elif kind == "binary":
        return pure_tree_reads_name(syntax["left"], name) or pure_tree_reads_name(syntax["right"], name)
    end
    return False
end

function emit_int_leaf(generator, syntax, register):
    output = generator["builder"]
    if syntax["kind"] == "literal":
        call assembler.emit(output, x86_64.mov_imm64(register, semantic.integer_literal(syntax)))
    else:
        name = syntax["name"]
        call emit_load_local(generator, register, name, syntax)
    end
end

function runtime_scalar_tag(value_type):
    return value_abi.scalar_tag(value_type)
end

function emit_collection_box(generator, syntax):
    value_type = semantic.infer_expression_type(syntax, generator["types"], generator["function_returns"])
    if value_type == "Bool":
        if generator["internal_abi"]:
            return
        end
        call assembler.emit(generator["builder"], x86_64.move_reg_reg(7, 0))
        call assembler.relative(generator["builder"], [232], "runtime_box_bool")
    elif value_type == "Int":
        # The self-host compiler is a typed trust core: its byte, token, index,
        # register and offset Lists keep Ints raw. Public programs still use the
        # unambiguous boxed dynamic ABI at call/collection boundaries.
        if generator["internal_abi"]:
            return
        end
        call assembler.emit(generator["builder"], x86_64.move_reg_reg(7, 0))
        # A statically known Int is raw by construction. Do not probe it as a
        # possible heap object: its bits may legitimately equal the address of
        # a live boxed Int, in which case probing would substitute that box's
        # payload before the new value is tagged.
        call assembler.relative(generator["builder"], [232], "runtime_box_int")
    elif value_type == "Function":
        # Function boxes carry the statically known return scalar tag so an
        # indirect call can re-establish the tagged Any result ABI.
        if not generator["internal_abi"]:
            return_type = "Any"
            if syntax["kind"] == "name" and syntax["name"] in generator["function_returns"]:
                return_type = generator["function_returns"][syntax["name"]]
            end
            call assembler.emit(generator["builder"], x86_64.mov_imm64(6, runtime_scalar_tag(return_type)))
            call assembler.emit(generator["builder"], x86_64.move_reg_reg(7, 0))
            call assembler.relative(generator["builder"], [232], "runtime_box_dynamic_function")
        end
    elif value_type == "Any" and syntax["kind"] == "binary" and syntax["operator"] != "and" and syntax["operator"] != "or":
        if generator["internal_abi"]:
            return
        end
        call assembler.emit(generator["builder"], x86_64.move_reg_reg(7, 0))
        call assembler.relative(generator["builder"], [232], "runtime_box_dynamic_int")
    elif value_type == "None":
        if generator["internal_abi"]:
            return
        end
        call assembler.relative(generator["builder"], [232], "runtime_box_none")
    end
end

function emit_dynamic_boundary_box(generator, syntax):
    if not generator["internal_abi"]:
        call emit_collection_box(generator, syntax)
    end
end

function emit_direct_call_boundary_box(generator, syntax, public_callee):
    if not public_callee:
        call emit_collection_box(generator, syntax)
        return
    end
    # compiler/pure tools use a raw whole-program ABI internally, but linked
    # stdlib and user functions retain the public tagged Any ABI. Temporarily
    # select it while materializing a direct argument at that boundary.
    old_internal = generator["internal_abi"]
    generator["internal_abi"] = False
    call emit_collection_box(generator, syntax)
    generator["internal_abi"] = old_internal
end

function emit_dictionary_key_box(generator, syntax):
    key_type = semantic.infer_expression_type(syntax, generator["types"], generator["function_returns"])
    if emit_validation_error(generator, syntax, "dictionary_key"):
        return
    end
    call emit_collection_box(generator, syntax)
    if key_type == "Any" and not generator["internal_abi"]:
        call assembler.emit(generator["builder"], x86_64.move_reg_reg(7, 0))
        call assembler.relative(generator["builder"], [232], "function___lsl_check_set_key")
        call emit_pending_error(generator)
    end
end

function dynamic_numeric_runtime(generator, name):
    if generator["internal_abi"]:
        return name + "_raw"
    end
    return name
end

function emit_uncaught_runtime_error(generator):
    call assembler.relative(generator["builder"], [233], "runtime_uncaught_error")
end

function emit_pending_error(generator):
    call runtime.thread_compare(generator["runtime"], generator["builder"], runtime.ERROR_FLAG, 0)
    if generator["error_label"] != "":
        call assembler.relative(generator["builder"], [15, 133], generator["error_label"])
    else:
        pending_error_clear = label_name(generator, "pending_error_clear")
        call assembler.relative(generator["builder"], [15, 132], pending_error_clear)
        call emit_uncaught_runtime_error(generator)
        call assembler.label(generator["builder"], pending_error_clear)
    end
end

function emit_runtime_raise(generator, message):
    call emit_string_pointer(generator, message)
    call runtime.thread_store(generator["runtime"], generator["builder"], runtime.ERROR, 0)
    call runtime.thread_store_immediate(generator["runtime"], generator["builder"], runtime.ERROR_FLAG, 1)
    if generator["error_label"] != "":
        call assembler.relative(generator["builder"], [233], generator["error_label"])
    else:
        call emit_uncaught_runtime_error(generator)
    end
end

# Rozhodnutí vzniká při překladu; úspěšná volání nemají novou runtime kontrolu.
function emit_source_raise(generator, syntax, error_type, message):
    location = syntax.get("path", generator["path"]) + ":" + String(syntax.get("line", 1)) + ":" + String(syntax.get("column", 1))
    call emit_runtime_raise(generator, error_type + ": " + message + " at " + location)
end

function emit_dynamic_numeric_value_guard(generator, int_only):
    # rax contains the public Any value. The shared runtime returns it unchanged
    # or records a catchable TypeError before an arithmetic helper sees it.
    call assembler.emit(generator["builder"], x86_64.move_reg_reg(7, 0))
    if int_only:
        call assembler.emit(generator["builder"], x86_64.mov_imm64(6, 1))
    else:
        call assembler.emit(generator["builder"], x86_64.mov_imm64(6, 0))
    end
    call assembler.relative(generator["builder"], [232], "runtime_require_numeric_value")
    call emit_pending_error(generator)
end

function emit_dynamic_numeric_pair_guard(generator, mode):
    # rdi/rsi contain the original operands. Mode 1 also permits String+String;
    # mode 2 restricts the right operand to Int/Bool (for exponentiation).
    call assembler.emit(generator["builder"], x86_64.mov_imm64(2, mode))
    call assembler.relative(generator["builder"], [232], "runtime_require_numeric_pair")
    call emit_pending_error(generator)
end

# Frontend určil chybu; backend zde pouze zachovává její místo ve vyhodnocení.
function emit_validation_error(generator, syntax, rule):
    error = validation.error_for(generator, syntax, rule)
    if error == None:
        return False
    end
    call emit_source_raise(generator, syntax, error[0], error[1])
    return True
end

function checked_index_node(generator, syntax):
    if syntax != None and semantic.infer_expression_type(syntax, generator["types"], generator["function_returns"]) == "Any" and not generator["internal_abi"] and not generator.get("current_internal_function", False):
        return {"kind": "call", "line": syntax["line"], "column": syntax["column"], "end_column": syntax["end_column"], "target": {"kind": "name", "name": "__lsl_checked_index"}, "arguments": [syntax]}
    end
    return syntax
end

function checked_string_node(generator, syntax):
    value_type = semantic.infer_expression_type(syntax, generator["types"], generator["function_returns"])
    if emit_validation_error(generator, syntax, "string_value"):
        return syntax
    end
    if value_type == "Any" and not generator["internal_abi"] and not generator.get("current_internal_function", False):
        return {"kind": "call", "line": syntax["line"], "column": syntax["column"], "end_column": syntax["end_column"], "target": {"kind": "name", "name": "__lsl_require_string_value"}, "arguments": [syntax]}
    end
    return syntax
end

function checked_list_node(generator, syntax):
    value_type = semantic.infer_expression_type(syntax, generator["types"], generator["function_returns"])
    if emit_validation_error(generator, syntax, "list_value"):
        return syntax
    end
    if value_type == "Any" and not generator["internal_abi"] and not generator.get("current_internal_function", False):
        return {"kind": "call", "line": syntax["line"], "column": syntax["column"], "end_column": syntax["end_column"], "target": {"kind": "name", "name": "__lsl_require_list"}, "arguments": [syntax]}
    end
    return syntax
end

function checked_byte_sequence_node(generator, syntax):
    value_type = semantic.infer_expression_type(syntax, generator["types"], generator["function_returns"])
    if emit_validation_error(generator, syntax, "byte_sequence"):
        return syntax
    end
    if value_type == "Any" and not generator["internal_abi"] and not generator.get("current_internal_function", False):
        return {"kind": "call", "line": syntax["line"], "column": syntax["column"], "end_column": syntax["end_column"], "target": {"kind": "name", "name": "__lsl_require_byte_sequence"}, "arguments": [syntax]}
    end
    return syntax
end

function emit_checked_int_expression(generator, syntax, purpose):
    value_type = semantic.infer_expression_type(syntax, generator["types"], generator["function_returns"])
    if emit_validation_error(generator, syntax, "integer_value"):
        return
    end
    call emit_expression(generator, syntax)
    if value_type == "Any":
        if not generator["internal_abi"] and not generator.get("current_internal_function", False):
            call emit_dynamic_numeric_value_guard(generator, True)
        end
        call assembler.emit(generator["builder"], x86_64.move_reg_reg(7, 0))
        call assembler.relative(generator["builder"], [232], "runtime_unbox_dynamic_int")
    end
end

function emit_bounds_check(generator, syntax, target_type, force):
    if not force and target_type == "IntArray" and generator.get("unchecked_intarray", False):
        return
    end
    source_path = syntax.get("path", generator["path"])
    bounds_nonnegative = label_name(generator, "bounds_nonnegative")
    bounds_ok = label_name(generator, "bounds_ok")
    call assembler.emit(generator["builder"], x86_64.push(7))
    call assembler.emit(generator["builder"], x86_64.push(6))
    if target_type == "List" or target_type == "Tuple" or target_type == "RealArray" or target_type == "IntArray" or target_type == "FloatArray" or target_type == "ByteArray":
        call assembler.emit(generator["builder"], x86_64.load_memory(0, 7, 8))
    else:
        call assembler.relative(generator["builder"], [232], "runtime_length")
    end
    call assembler.emit(generator["builder"], x86_64.move_reg_reg(8, 0))
    call assembler.emit(generator["builder"], x86_64.pop(6))
    call assembler.emit(generator["builder"], x86_64.pop(7))
    call assembler.emit(generator["builder"], x86_64.cmp_reg_imm8(6, 0))
    call assembler.relative(generator["builder"], [15, 141], bounds_nonnegative)
    call assembler.emit(generator["builder"], x86_64.add_reg_reg(6, 8))
    call assembler.label(generator["builder"], bounds_nonnegative)
    call assembler.emit(generator["builder"], x86_64.cmp_reg_imm8(6, 0))
    bounds_error = label_name(generator, "bounds_error")
    call assembler.relative(generator["builder"], [15, 140], bounds_error)
    call assembler.emit(generator["builder"], x86_64.cmp_reg_reg(6, 8))
    call assembler.relative(generator["builder"], [15, 140], bounds_ok)
    call assembler.label(generator["builder"], bounds_error)
    message = "IndexError: index out of range at " + source_path + ":" + String(syntax["line"])
    call emit_runtime_raise(generator, message)
    call assembler.label(generator["builder"], bounds_ok)
end

function emit_float_expression(generator, syntax):
    call emit_expression(generator, syntax)
    value_type = semantic.infer_expression_type(syntax, generator["types"], generator["function_returns"])
    if value_type == "Any":
        if not generator["internal_abi"] and not generator.get("current_internal_function", False):
            call emit_dynamic_numeric_value_guard(generator, False)
        end
        call assembler.emit(generator["builder"], x86_64.move_reg_reg(7, 0))
        call assembler.relative(generator["builder"], [232], "runtime_coerce_float")
    elif value_type != "Float":
        call assembler.emit(generator["builder"], x86_64.move_reg_reg(7, 0))
        call assembler.relative(generator["builder"], [232], "runtime_float_from_int")
    end
end

function bit_operand_node(generator, syntax):
    # Bitwise lowering works on raw Int bits. Statically known Int/Bool operands
    # already are raw; an Any operand is routed through the dynamic helper so a
    # boxed Float or a live pointer raises TypeError instead of being read as
    # bits. Anything else is a compile-time mistake.
    operand_type = semantic.infer_expression_type(syntax, generator["types"], generator["function_returns"])
    if operand_type == "Int" or operand_type == "Bool":
        return syntax
    end
    if emit_validation_error(generator, syntax, "bit_operand"):
        return syntax
    end
    coerce = {"kind": "call", "line": syntax["line"], "column": syntax["column"], "end_column": syntax["end_column"]}
    coerce["target"] = {"kind": "name", "name": "__lsl_bit_operand"}
    coerce["arguments"] = [syntax]
    return coerce
end

function emit_shift(generator, syntax, left, right):
    output = generator["builder"]
    operator = syntax["operator"]
    count = semantic.constant_int_expression(right)
    if emit_validation_error(generator, syntax, "negative_shift"):
        return
    end
    if count[0] and count[1] >= 0 and count[1] <= 63:
        call emit_expression(generator, left)
        if operator == "<<":
            call assembler.emit(output, x86_64.shift_left_imm(0, count[1]))
        else:
            call assembler.emit(output, x86_64.shift_right_arithmetic_imm(0, count[1]))
        end
        return
    end
    if is_int_leaf(generator, right):
        call emit_expression(generator, left)
        call emit_int_leaf(generator, right, 1)
    else:
        call emit_expression(generator, left)
        call assembler.emit(output, x86_64.push(0))
        call emit_expression(generator, right)
        call assembler.emit(output, x86_64.move_reg_reg(1, 0))
        call assembler.emit(output, x86_64.pop(0))
    end
    # reg0 = value, reg1 = count. SHL/SAR mask the count to 6 bits, so both the
    # negative and the >= 64 case are decided here rather than by the CPU.
    shift_ready = label_name(generator, "shift_ready")
    call assembler.emit(output, x86_64.cmp_reg_imm8(1, 0))
    call assembler.relative(output, [15, 141], shift_ready)
    shift_source_path = syntax.get("path", generator["path"])
    shift_message = "ValueError: negative shift count at " + shift_source_path + ":" + String(syntax["line"])
    call emit_runtime_raise(generator, shift_message)
    call assembler.label(output, shift_ready)
    if operator == ">>":
        # Saturating the count at 63 gives Python's answer for wide shifts:
        # 0 for a non-negative value and -1 for a negative one.
        shift_clamped = label_name(generator, "shift_clamped")
        call assembler.emit(output, x86_64.cmp_reg_imm8(1, 63))
        call assembler.relative(output, [15, 142], shift_clamped)
        call assembler.emit(output, x86_64.mov_imm64(1, 63))
        call assembler.label(output, shift_clamped)
        call assembler.emit(output, x86_64.shift_right_arithmetic_cl(0))
        return
    end
    shift_wide = label_name(generator, "shift_wide")
    shift_done = label_name(generator, "shift_done")
    call assembler.emit(output, x86_64.cmp_reg_imm8(1, 64))
    call assembler.relative(output, [15, 141], shift_wide)
    call assembler.emit(output, x86_64.shift_left_cl(0))
    call assembler.relative(output, [233], shift_done)
    call assembler.label(output, shift_wide)
    call assembler.emit(output, x86_64.mov_imm64(0, 0))
    call assembler.label(output, shift_done)
end

function emit_bitwise(generator, syntax):
    output = generator["builder"]
    operator = syntax["operator"]
    left = bit_operand_node(generator, syntax["left"])
    right = bit_operand_node(generator, syntax["right"])
    if operator == "<<" or operator == ">>":
        call emit_shift(generator, syntax, left, right)
        return
    end
    # &, | and ~ are commutative, so either leaf ordering keeps the operands'
    # single evaluation and avoids the stack spill.
    if is_int_leaf(generator, right):
        call emit_expression(generator, left)
        call emit_int_leaf(generator, right, 1)
    elif is_int_leaf(generator, left):
        call emit_expression(generator, right)
        call emit_int_leaf(generator, left, 1)
    else:
        call emit_expression(generator, left)
        call assembler.emit(output, x86_64.push(0))
        call emit_expression(generator, right)
        call assembler.emit(output, x86_64.move_reg_reg(1, 0))
        call assembler.emit(output, x86_64.pop(0))
    end
    if operator == "&":
        call assembler.emit(output, x86_64.and_reg_reg(0, 1))
    elif operator == "|":
        call assembler.emit(output, x86_64.or_reg_reg(0, 1))
    else:
        call assembler.emit(output, x86_64.xor_reg_reg(0, 1))
    end
end

function bind_arguments(generator, syntax, declaration, skip):
    if emit_validation_error(generator, syntax, "arguments"):
        return None
    end
    return validation.arguments(generator, syntax, declaration, skip)
end

function emit_expression(generator, syntax):
    output = generator["builder"]
    kind = syntax["kind"]
    if kind == "binary" or kind == "unary":
        constant_string = semantic.constant_string_expression(syntax)
        if constant_string[0]:
            call emit_string_pointer(generator, constant_string[1])
            return
        end
        constant_integer = semantic.constant_int_expression(syntax)
        if constant_integer[0]:
            call assembler.emit(output, x86_64.mov_imm64(0, constant_integer[1]))
            return
        end
    elif kind == "compare":
        constant_truth = semantic.constant_truth_expression(syntax)
        if constant_truth[0]:
            truth_value = 0
            if constant_truth[1]:
                truth_value = 1
            end
            call assembler.emit(output, x86_64.mov_imm64(0, truth_value))
            return
        end
    end
    if (kind == "binary" or kind == "index" or kind == "unary") and generator.get("fast_intarray_name", "") == "":
        need = pure_int_need(generator, syntax)
        if need >= 1 and need <= 6:
            call emit_pure_int_expression(generator, syntax, 0, pure_int_pool())
            return
        end
    end
    if kind == "binary" and generator.get("unchecked_intarray", False) and generator.get("fast_intarray_name", "") == "" and is_fast_int_value(generator, syntax):
        repeated_array = repeated_fast_intarray(generator, syntax)
        if repeated_array != "":
            # Hoist one repeated IntArray data-pointer load for this pure
            # scalar expression. The restricted tree does not clobber r8.
            call emit_load_local(generator, 0, repeated_array)
            call assembler.emit(output, x86_64.load_memory(8, 0, 24))
            generator["fast_intarray_name"] = repeated_array
            call emit_expression(generator, syntax)
            generator["fast_intarray_name"] = ""
            return
        end
    end
    if kind == "literal":
        value = syntax["value"]
        if syntax["literal_kind"] == "string":
            call emit_string_pointer(generator, value)
        elif syntax["literal_kind"] == "number":
            if value.find(".") >= 0 or value.find("e") >= 0 or value.find("E") >= 0:
                call assembler.emit(output, x86_64.mov_imm64(7, float_bits(value)))
                call assembler.relative(output, [232], "runtime_float_new")
            else:
                call assembler.emit(output, x86_64.mov_imm64(0, semantic.integer_literal(syntax)))
            end
        elif value == "True":
            call assembler.emit(output, x86_64.mov_imm64(0, 1))
        elif value == "False" or value == "None":
            call assembler.emit(output, x86_64.mov_imm64(0, 0))
        else:
            Error(CompileError: "invalid analyzed program")
        end
    elif kind == "name":
        name = syntax["name"]
        if name in generator["variables"] or name in generator["global_variables"]:
            call emit_load_local(generator, 0, name, syntax)
        elif name in generator["functions"]:
            if lazy_runtime(name):
                generator["lazy_used"][name] = True
            end
            call assembler.relative(output, x86_64.lea_rip_prefix(0), "function_" + name)
        else:
            if generator["error_label"] != "":
                call emit_validation_error(generator, syntax, "unknown_variable")
                return
            end
            Error(CompileError: "invalid analyzed program")
        end
    elif kind == "comprehension":
        call semantic.collect_types(syntax["body"], generator["types"], generator["function_returns"])
        call emit_statements(generator, syntax["body"], "", "", "")
        call emit_expression(generator, syntax["result"])
    elif kind == "real_array":
        array_values = {"kind": "list", "line": syntax["line"], "column": syntax["column"], "end_column": syntax["end_column"], "items": syntax["items"]}
        array_call = {"kind": "call", "line": syntax["line"], "column": syntax["column"], "end_column": syntax["end_column"], "target": {"kind": "name", "name": "__lsl_real_array"}, "arguments": [array_values]}
        call emit_expression(generator, array_call)
        call assembler.emit(output, x86_64.store_memory_imm32(0, abi_x86_64.OBJECT_TAG, value_abi.TAG_REAL_ARRAY))
    elif kind == "list" or kind == "tuple":
        call assembler.emit(output, x86_64.mov_imm64(7, 0))
        call assembler.emit(output, x86_64.mov_imm64(6, 0))
        call assembler.relative(output, [232], "runtime_list_new")
        call assembler.emit(output, x86_64.push(0))
        for item in syntax["items"]:
            call emit_expression(generator, item)
            call emit_collection_box(generator, item)
            call assembler.emit(output, x86_64.move_reg_reg(6, 0))
            call assembler.emit(output, x86_64.load_memory(7, 4, 0))
            call assembler.relative(output, [232], "runtime_list_append")
        end
        call assembler.emit(output, x86_64.pop(0))
        if kind == "tuple":
            call assembler.emit(output, x86_64.store_memory_imm32(0, abi_x86_64.OBJECT_TAG, value_abi.TAG_TUPLE))
        end
    elif kind == "dictionary":
        call assembler.relative(output, [232], "runtime_dict_new")
        call assembler.emit(output, x86_64.push(0))
        for entry in syntax["entries"]:
            call emit_expression(generator, entry[0])
            call emit_dictionary_key_box(generator, entry[0])
            call assembler.emit(output, x86_64.push(0))
            call emit_expression(generator, entry[1])
            call emit_collection_box(generator, entry[1])
            call assembler.emit(output, x86_64.move_reg_reg(2, 0))
            call assembler.emit(output, x86_64.pop(6))
            call assembler.emit(output, x86_64.load_memory(7, 4, 0))
            call assembler.relative(output, [232], "runtime_dict_set")
        end
        call assembler.emit(output, x86_64.pop(0))
    elif kind == "member":
        target_type = semantic.infer_expression_type(syntax["target"], generator["types"], generator["function_returns"])
        if target_type.startswith("Class:") or target_type.startswith("Instance:") or target_type == "Dictionary":
            call emit_expression(generator, syntax["target"])
            call assembler.emit(output, x86_64.push(0))
            call emit_string_pointer(generator, syntax["name"])
            call assembler.emit(output, x86_64.move_reg_reg(6, 0))
            call assembler.emit(output, x86_64.pop(7))
            call assembler.relative(output, [232], "runtime_dict_get")
            call emit_pending_error(generator)
        else:
            if generator["error_label"] != "":
                call emit_validation_error(generator, syntax, "member_value")
                return
            end
            Error(CompileError: "invalid analyzed program")
        end
    elif kind == "slice":
        target_slice_type = semantic.infer_expression_type(syntax["target"], generator["types"], generator["function_returns"])
        if emit_validation_error(generator, syntax, "slice_target"):
            return
        end
        for slice_bound in [syntax["start"], syntax["stop"], syntax.get("step", None)]:
            if slice_bound != None:
                if emit_validation_error(generator, slice_bound, "slice_bound"):
                    return
                end
            end
        end
        if syntax.get("step", None) != None or target_slice_type == "ByteArray" or (target_slice_type == "Any" and not generator["internal_abi"]):
            # Strided slice via pure-LSL helper (Python step semantics).
            zero_literal = {"kind": "literal", "literal_kind": "number", "value": "0", "integer_value": 0, "line": syntax["line"], "column": syntax["column"], "end_column": syntax["end_column"]}
            one_literal = {"kind": "literal", "literal_kind": "number", "value": "1", "integer_value": 1, "line": syntax["line"], "column": syntax["column"], "end_column": syntax["end_column"]}
            true_literal = {"kind": "literal", "literal_kind": "name", "value": "True", "line": syntax["line"], "column": syntax["column"], "end_column": syntax["end_column"]}
            false_literal = {"kind": "literal", "literal_kind": "name", "value": "False", "line": syntax["line"], "column": syntax["column"], "end_column": syntax["end_column"]}
            start_arg = zero_literal
            has_start = false_literal
            if syntax["start"] != None:
                start_arg = checked_index_node(generator, syntax["start"])
                has_start = true_literal
            end
            stop_arg = zero_literal
            has_stop = false_literal
            if syntax["stop"] != None:
                stop_arg = checked_index_node(generator, syntax["stop"])
                has_stop = true_literal
            end
            step_arg = one_literal
            if syntax.get("step", None) != None:
                step_arg = checked_index_node(generator, syntax["step"])
            end
            slice_call = {"kind": "call", "line": syntax["line"], "column": syntax["column"], "end_column": syntax["end_column"], "target": {"kind": "name", "name": "__lsl_slice3"}, "arguments": [syntax["target"], start_arg, has_start, stop_arg, has_stop, step_arg]}
            call emit_expression(generator, slice_call)
            target_slice_type = semantic.infer_expression_type(syntax["target"], generator["types"], generator["function_returns"])
            if target_slice_type == "Tuple":
                call assembler.emit(output, x86_64.store_memory_imm32(0, abi_x86_64.OBJECT_TAG, value_abi.TAG_TUPLE))
            elif target_slice_type == "RealArray":
                call assembler.emit(output, x86_64.store_memory_imm32(0, abi_x86_64.OBJECT_TAG, value_abi.TAG_REAL_ARRAY))
            elif target_slice_type == "IntArray":
                call assembler.emit(output, x86_64.store_memory_imm32(0, abi_x86_64.OBJECT_TAG, value_abi.TAG_INT_ARRAY))
            elif target_slice_type == "FloatArray":
                call assembler.emit(output, x86_64.store_memory_imm32(0, abi_x86_64.OBJECT_TAG, value_abi.TAG_FLOAT_ARRAY))
            end
            return
        end
        call emit_expression(generator, syntax["target"])
        call assembler.emit(output, x86_64.push(0))
        if syntax["start"] == None:
            call assembler.emit(output, x86_64.mov_imm64(0, 0))
        else:
            call emit_expression(generator, syntax["start"])
            if semantic.infer_expression_type(syntax["start"], generator["types"], generator["function_returns"]) == "Any":
                call assembler.emit(output, x86_64.move_reg_reg(7, 0))
                if not generator["internal_abi"] and not generator.get("current_internal_function", False):
                    call assembler.relative(output, [232], "runtime_checked_index")
                    call emit_pending_error(generator)
                else:
                    call assembler.relative(output, [232], "runtime_unbox_dynamic_int")
                end
            end
        end
        call assembler.emit(output, x86_64.push(0))
        if syntax["stop"] == None:
            call assembler.emit(output, x86_64.load_memory(7, 4, 8))
            call assembler.relative(output, [232], "runtime_length")
        else:
            call emit_expression(generator, syntax["stop"])
            if semantic.infer_expression_type(syntax["stop"], generator["types"], generator["function_returns"]) == "Any":
                call assembler.emit(output, x86_64.move_reg_reg(7, 0))
                if not generator["internal_abi"] and not generator.get("current_internal_function", False):
                    call assembler.relative(output, [232], "runtime_checked_index")
                    call emit_pending_error(generator)
                else:
                    call assembler.relative(output, [232], "runtime_unbox_dynamic_int")
                end
            end
        end
        call assembler.emit(output, x86_64.move_reg_reg(2, 0))
        call assembler.emit(output, x86_64.pop(6))
        call assembler.emit(output, x86_64.pop(7))
        call assembler.relative(output, [232], "runtime_slice")
        target_slice_type = semantic.infer_expression_type(syntax["target"], generator["types"], generator["function_returns"])
        if target_slice_type == "Tuple":
            call assembler.emit(output, x86_64.store_memory_imm32(0, abi_x86_64.OBJECT_TAG, value_abi.TAG_TUPLE))
        elif target_slice_type == "RealArray":
            call assembler.emit(output, x86_64.store_memory_imm32(0, abi_x86_64.OBJECT_TAG, value_abi.TAG_REAL_ARRAY))
        elif target_slice_type == "IntArray":
            call assembler.emit(output, x86_64.store_memory_imm32(0, abi_x86_64.OBJECT_TAG, value_abi.TAG_INT_ARRAY))
        elif target_slice_type == "FloatArray":
            call assembler.emit(output, x86_64.store_memory_imm32(0, abi_x86_64.OBJECT_TAG, value_abi.TAG_FLOAT_ARRAY))
        end
    elif kind == "index":
        target_type = semantic.infer_expression_type(syntax["target"], generator["types"], generator["function_returns"])
        index_type = semantic.infer_expression_type(syntax["index"], generator["types"], generator["function_returns"])
        if emit_validation_error(generator, syntax, "index_target"):
            return
        elif emit_validation_error(generator, syntax["index"], "index_value"):
            return
        end
        if target_type == "IntArray" and generator.get("unchecked_intarray", False) and is_fast_int_index(generator, syntax["index"]):
            # The unchecked numeric hot path can keep both operands in their
            # final ABI registers. A leaf index cannot call or clobber rdi, so
            # avoid the generic target push/pop sequence entirely.
            cached_array = syntax["target"]["kind"] == "name" and syntax["target"]["name"] == generator.get("fast_intarray_name", "")
            if not cached_array:
                call emit_expression(generator, syntax["target"])
                call assembler.emit(output, x86_64.move_reg_reg(7, 0))
            end
            if is_int_leaf(generator, syntax["index"]):
                call emit_int_leaf(generator, syntax["index"], 6)
            else:
                call emit_expression(generator, syntax["index"])
                call assembler.emit(output, x86_64.move_reg_reg(6, 0))
            end
            if cached_array:
                call assembler.emit(output, x86_64.load_indexed(0, 8, 6, 3))
            else:
                call assembler.emit(output, x86_64.load_memory(0, 7, 24))
                call assembler.emit(output, x86_64.load_indexed(0, 0, 6, 3))
            end
            return
        end
        call emit_expression(generator, syntax["target"])
        call assembler.emit(output, x86_64.push(0))
        call emit_expression(generator, syntax["index"])
        if target_type == "Dictionary" or (target_type == "Any" and not generator["internal_abi"]):
            call emit_dictionary_key_box(generator, syntax["index"])
        elif index_type == "Any":
            call assembler.emit(output, x86_64.move_reg_reg(7, 0))
            if not generator["internal_abi"] and not generator.get("current_internal_function", False):
                call assembler.relative(output, [232], "runtime_checked_index")
                call emit_pending_error(generator)
            else:
                call assembler.relative(output, [232], "runtime_unbox_dynamic_int")
            end
        end
        call assembler.emit(output, x86_64.move_reg_reg(6, 0))
        call assembler.emit(output, x86_64.pop(7))
        if target_type == "Dictionary":
            call assembler.relative(output, [232], "runtime_dict_get")
        else:
            if target_type == "String" or target_type == "List" or target_type == "Tuple" or target_type == "RealArray" or target_type == "IntArray" or target_type == "FloatArray" or target_type == "ByteArray":
                call emit_bounds_check(generator, syntax, target_type, False)
            end
            if target_type == "ByteArray":
                call assembler.relative(output, [232], "runtime_byte_array_get")
            elif target_type == "IntArray":
                # Bounds normalization leaves the collection in rdi and the
                # normalized index in rsi. IntArray stores raw Int64 slots, so
                # avoid a runtime helper call on this numeric hot path.
                call assembler.emit(output, x86_64.load_memory(0, 7, 24))
                call assembler.emit(output, x86_64.load_indexed(0, 0, 6, 3))
            elif target_type == "List" or target_type == "Tuple" or target_type == "RealArray" or target_type == "FloatArray":
                call assembler.relative(output, [232], "runtime_list_get")
                if target_type == "FloatArray":
                    call assembler.emit(output, x86_64.move_reg_reg(7, 0))
                    call assembler.relative(output, [232], "runtime_float_new")
                end
            else:
                if target_type == "Any" and not generator["internal_abi"]:
                    if generator.get("current_internal_function", False):
                        call assembler.relative(output, [232], "runtime_iter_get")
                    else:
                        call assembler.relative(output, [232], "runtime_dynamic_get")
                    end
                else:
                    call assembler.relative(output, [232], "runtime_get")
                end
            end
        end
        call emit_pending_error(generator)
    elif kind == "unary":
        if syntax["operator"] == "~":
            call emit_expression(generator, bit_operand_node(generator, syntax["operand"]))
            call assembler.emit(output, x86_64.not_reg(0))
            return
        end
        operand_type = semantic.infer_expression_type(syntax["operand"], generator["types"], generator["function_returns"])
        if emit_validation_error(generator, syntax, "unary_numeric"):
            return
        end
        call emit_expression(generator, syntax["operand"])
        if syntax["operator"] == "-":
            if operand_type == "Float":
                call assembler.emit(output, x86_64.load_memory(7, 0, 8))
                call assembler.emit(output, x86_64.mov_imm64(1, -9223372036854775808))
                call assembler.emit(output, x86_64.add_reg_reg(7, 1))
                call assembler.relative(output, [232], "runtime_float_new")
            elif operand_type == "Any":
                if not generator["internal_abi"] and not generator.get("current_internal_function", False):
                    call emit_dynamic_numeric_value_guard(generator, False)
                end
                call assembler.emit(output, x86_64.move_reg_reg(7, 0))
                call assembler.relative(output, [232], dynamic_numeric_runtime(generator, "runtime_neg_any"))
            else:
                call assembler.emit(output, x86_64.neg_reg(0))
            end
        elif syntax["operator"] == "not":
            call emit_truth(generator)
            call assembler.emit(output, x86_64.cmp_reg_imm8(0, 0))
            call assembler.emit(output, x86_64.set_condition(148))
        end
    elif kind == "binary":
        operator = syntax["operator"]
        expression_type = semantic.infer_expression_type(syntax, generator["types"], generator["function_returns"])
        binary_left_type = semantic.infer_expression_type(syntax["left"], generator["types"], generator["function_returns"])
        binary_right_type = semantic.infer_expression_type(syntax["right"], generator["types"], generator["function_returns"])
        if operator == "+":
            if emit_validation_error(generator, syntax, "add_operands"):
                return
            end
        elif operator == "*":
            if emit_validation_error(generator, syntax, "multiply_operands"):
                return
            end
        elif operator == "-" or operator == "/" or operator == "//" or operator == "%":
            if emit_validation_error(generator, syntax, "numeric_operands"):
                return
            end
        elif operator == "^":
            if emit_validation_error(generator, syntax, "exponent_operands"):
                return
            end
        end
        if (operator == "//" or operator == "%") and (expression_type == "Float" or expression_type == "Any"):
            # Float floor-division/modulo, or dynamic Int/Float dispatch when both
            # operands are Any. Must precede the Float +-*/ block (which rejects
            # // and %).
            floor_left_type = semantic.infer_expression_type(syntax["left"], generator["types"], generator["function_returns"])
            floor_right_type = semantic.infer_expression_type(syntax["right"], generator["types"], generator["function_returns"])
            if emit_validation_error(generator, syntax, "floor_operands"):
                return
            end
            if operator == "%":
                floor_target = "__lsl_fmod"
                if expression_type == "Any":
                    floor_target = "__lsl_mod_dyn"
                    if not generator["internal_abi"] and not generator.get("current_internal_function", False):
                        floor_target = "__lsl_public_mod_dyn"
                    end
                end
            else:
                floor_target = "__lsl_ffloordiv"
                if expression_type == "Any":
                    floor_target = "__lsl_floordiv_dyn"
                    if not generator["internal_abi"] and not generator.get("current_internal_function", False):
                        floor_target = "__lsl_public_floordiv_dyn"
                    end
                end
            end
            floor_call = {"kind": "call", "line": syntax["line"], "column": syntax["column"], "end_column": syntax["end_column"], "target": {"kind": "name", "name": floor_target}, "arguments": [syntax["left"], syntax["right"]]}
            call emit_expression(generator, floor_call)
            return
        end
        if expression_type == "Float":
            if operator == "^":
                exponent_type = semantic.infer_expression_type(syntax["right"], generator["types"], generator["function_returns"])
                if emit_validation_error(generator, syntax, "float_exponent"):
                    return
                end
                call emit_float_expression(generator, syntax["left"])
                call assembler.emit(output, x86_64.push(0))
                call emit_expression(generator, syntax["right"])
                if exponent_type == "Any":
                    call assembler.emit(output, x86_64.move_reg_reg(7, 0))
                    if not generator["internal_abi"] and not generator.get("current_internal_function", False):
                        call assembler.relative(output, [232], "runtime_checked_index")
                        call emit_pending_error(generator)
                    else:
                        call assembler.relative(output, [232], "runtime_unbox_dynamic_int")
                    end
                end
                call assembler.emit(output, x86_64.move_reg_reg(6, 0))
                call assembler.emit(output, x86_64.pop(7))
                call assembler.relative(output, [232], "runtime_float_power")
                return
            end
            call emit_float_expression(generator, syntax["left"])
            call assembler.emit(output, x86_64.push(0))
            call emit_float_expression(generator, syntax["right"])
            call assembler.emit(output, x86_64.move_reg_reg(6, 0))
            call assembler.emit(output, x86_64.pop(7))
            if operator == "+":
                call assembler.relative(output, [232], "runtime_float_add")
            elif operator == "-":
                call assembler.relative(output, [232], "runtime_float_sub")
            elif operator == "*":
                call assembler.relative(output, [232], "runtime_float_mul")
            elif operator == "/":
                call assembler.relative(output, [232], "runtime_float_div")
            else:
                Error(CompileError: "invalid analyzed program")
            end
            return
        elif operator == "+" and expression_type == "List":
            concat_call = {"kind": "call", "line": syntax["line"], "column": syntax["column"], "end_column": syntax["end_column"], "target": {"kind": "name", "name": "__lsl_list_concat"}, "arguments": [syntax["left"], syntax["right"]]}
            call emit_expression(generator, concat_call)
            return
        elif operator == "*" and expression_type == "String":
            left_type = semantic.infer_expression_type(syntax["left"], generator["types"], generator["function_returns"])
            if left_type == "String":
                repeat_call = {"kind": "call", "line": syntax["line"], "column": syntax["column"], "end_column": syntax["end_column"], "target": {"kind": "name", "name": "__lsl_str_repeat"}, "arguments": [syntax["left"], syntax["right"]]}
            else:
                repeat_call = {"kind": "call", "line": syntax["line"], "column": syntax["column"], "end_column": syntax["end_column"], "target": {"kind": "name", "name": "__lsl_str_repeat"}, "arguments": [syntax["right"], syntax["left"]]}
            end
            call emit_expression(generator, repeat_call)
            return
        elif operator == "+" and (expression_type == "String" or expression_type == "Any"):
            if expression_type == "Any" and not generator["internal_abi"] and not generator.get("current_internal_function", False):
                public_add_call = {"kind": "call", "line": syntax["line"], "column": syntax["column"], "end_column": syntax["end_column"], "target": {"kind": "name", "name": "__lsl_public_add"}, "arguments": [syntax["left"], syntax["right"]]}
                call emit_expression(generator, public_add_call)
                return
            end
            public_dynamic_add = (binary_left_type == "Any" or binary_right_type == "Any") and not generator["internal_abi"] and not generator.get("current_internal_function", False)
            call emit_expression(generator, syntax["left"])
            if expression_type == "Any" or public_dynamic_add:
                call emit_dynamic_boundary_box(generator, syntax["left"])
            end
            call assembler.emit(output, x86_64.push(0))
            call emit_expression(generator, syntax["right"])
            if expression_type == "Any" or public_dynamic_add:
                call emit_dynamic_boundary_box(generator, syntax["right"])
            end
            call assembler.emit(output, x86_64.move_reg_reg(6, 0))
            call assembler.emit(output, x86_64.pop(7))
            if expression_type == "String" and not public_dynamic_add:
                call assembler.relative(output, [232], "runtime_string_concat")
            else:
                if not generator["internal_abi"] and not generator.get("current_internal_function", False):
                    call emit_dynamic_numeric_pair_guard(generator, 1)
                end
                call assembler.relative(output, [232], dynamic_numeric_runtime(generator, "runtime_add_any"))
            end
            return
        elif (operator == "-" or operator == "*") and expression_type == "Any":
            # Dynamic - / * : dispatch Int vs boxed Float at runtime.
            if operator == "*" and not generator["internal_abi"] and not generator.get("current_internal_function", False):
                public_multiply_call = {"kind": "call", "line": syntax["line"], "column": syntax["column"], "end_column": syntax["end_column"], "target": {"kind": "name", "name": "__lsl_public_multiply"}, "arguments": [syntax["left"], syntax["right"]]}
                call emit_expression(generator, public_multiply_call)
                return
            end
            call emit_expression(generator, syntax["left"])
            call emit_dynamic_boundary_box(generator, syntax["left"])
            call assembler.emit(output, x86_64.push(0))
            call emit_expression(generator, syntax["right"])
            call emit_dynamic_boundary_box(generator, syntax["right"])
            call assembler.emit(output, x86_64.move_reg_reg(6, 0))
            call assembler.emit(output, x86_64.pop(7))
            if operator == "-":
                if not generator["internal_abi"] and not generator.get("current_internal_function", False):
                    call emit_dynamic_numeric_pair_guard(generator, 0)
                end
                call assembler.relative(output, [232], dynamic_numeric_runtime(generator, "runtime_sub_any"))
            else:
                if not generator["internal_abi"] and not generator.get("current_internal_function", False):
                    call emit_dynamic_numeric_pair_guard(generator, 0)
                end
                call assembler.relative(output, [232], dynamic_numeric_runtime(generator, "runtime_mul_any"))
            end
            return
        elif operator == "^" and expression_type == "Any":
            # Dynamic ^ : base may be boxed Float or raw Int; Int exponent.
            if emit_validation_error(generator, syntax, "int_exponent"):
                return
            end
            call emit_expression(generator, syntax["left"])
            call emit_dynamic_boundary_box(generator, syntax["left"])
            call assembler.emit(output, x86_64.push(0))
            call emit_expression(generator, syntax["right"])
            call emit_dynamic_boundary_box(generator, syntax["right"])
            call assembler.emit(output, x86_64.move_reg_reg(6, 0))
            call assembler.emit(output, x86_64.pop(7))
            if not generator["internal_abi"] and not generator.get("current_internal_function", False):
                call emit_dynamic_numeric_pair_guard(generator, 2)
            end
            call assembler.relative(output, [232], dynamic_numeric_runtime(generator, "runtime_pow_any"))
            call emit_pending_error(generator)
            return
        elif operator == "&" or operator == "|" or operator == "~" or operator == "<<" or operator == ">>":
            call emit_bitwise(generator, syntax)
            return
        elif operator == "and" or operator == "or":
            short_label = label_name(generator, "bool_short")
            done_label = label_name(generator, "bool_done")
            call emit_expression(generator, syntax["left"])
            call emit_truth(generator)
            call assembler.emit(output, x86_64.cmp_reg_imm8(0, 0))
            if operator == "and":
                call assembler.relative(output, [15, 132], short_label)
            else:
                call assembler.relative(output, [15, 133], short_label)
            end
            call emit_expression(generator, syntax["right"])
            call emit_truth(generator)
            call assembler.emit(output, x86_64.cmp_reg_imm8(0, 0))
            call assembler.emit(output, x86_64.set_condition(149))
            call assembler.relative(output, [233], done_label)
            call assembler.label(output, short_label)
            if operator == "and":
                call assembler.emit(output, x86_64.mov_imm64(0, 0))
            else:
                call assembler.emit(output, x86_64.mov_imm64(0, 1))
            end
            call assembler.label(output, done_label)
            return
        end
        # Int arithmetic path (Float/String/List handled above). Fold constant
        # subtrees into immediate operations while preserving evaluation of the
        # non-constant side. This makes mechanically generated or noisy source
        # as cheap as the direct spelling without reordering side effects.
        right_constant = semantic.constant_int_expression(syntax["right"])
        left_constant = semantic.constant_int_expression(syntax["left"])
        if right_constant[0] and x86_64.fits_signed32(right_constant[1]) and (operator == "+" or operator == "-" or operator == "*"):
            immediate = right_constant[1]
            call emit_expression(generator, syntax["left"])
            if operator == "+" and immediate != 0:
                call assembler.emit(output, x86_64.add_reg_imm32(0, immediate))
            elif operator == "-" and immediate != 0:
                call assembler.emit(output, x86_64.sub_reg_imm(0, immediate))
            elif operator == "*":
                if immediate == 0:
                    call assembler.emit(output, x86_64.mov_imm64(0, 0))
                elif immediate == -1:
                    call assembler.emit(output, x86_64.neg_reg(0))
                elif immediate != 1:
                    call assembler.emit(output, x86_64.imul_reg_imm(0, 0, immediate))
                end
            end
            return
        elif left_constant[0] and x86_64.fits_signed32(left_constant[1]) and (operator == "+" or operator == "*"):
            immediate = left_constant[1]
            call emit_expression(generator, syntax["right"])
            if operator == "+" and immediate != 0:
                call assembler.emit(output, x86_64.add_reg_imm32(0, immediate))
            elif operator == "*":
                if immediate == 0:
                    call assembler.emit(output, x86_64.mov_imm64(0, 0))
                elif immediate == -1:
                    call assembler.emit(output, x86_64.neg_reg(0))
                elif immediate != 1:
                    call assembler.emit(output, x86_64.imul_reg_imm(0, 0, immediate))
                end
            end
            return
        elif operator == "^" and right_constant[0] and right_constant[1] >= 0 and right_constant[1] <= 4:
            # Small fixed powers are cheaper inline than the generic
            # exponentiation-by-squaring call. Evaluate the base exactly once.
            small_power = right_constant[1]
            call emit_expression(generator, syntax["left"])
            if small_power == 0:
                call assembler.emit(output, x86_64.mov_imm64(0, 1))
            elif small_power == 2:
                call assembler.emit(output, x86_64.imul_reg_reg(0, 0))
            elif small_power == 3:
                call assembler.emit(output, x86_64.move_reg_reg(1, 0))
                call assembler.emit(output, x86_64.imul_reg_reg(0, 0))
                call assembler.emit(output, x86_64.imul_reg_reg(0, 1))
            elif small_power == 4:
                call assembler.emit(output, x86_64.imul_reg_reg(0, 0))
                call assembler.emit(output, x86_64.imul_reg_reg(0, 0))
            end
            return
        end
        # Avoid the push/pop spill when an operand is a literal or variable leaf.
        if is_int_leaf(generator, syntax["right"]):
            call emit_expression(generator, syntax["left"])
            call emit_int_leaf(generator, syntax["right"], 1)
        elif (operator == "+" or operator == "*") and is_int_leaf(generator, syntax["left"]):
            call emit_expression(generator, syntax["right"])
            call emit_int_leaf(generator, syntax["left"], 1)
        else:
            call emit_expression(generator, syntax["left"])
            call assembler.emit(output, x86_64.push(0))
            call emit_expression(generator, syntax["right"])
            call assembler.emit(output, x86_64.move_reg_reg(1, 0))
            call assembler.emit(output, x86_64.pop(0))
        end
        if operator == "+":
            call assembler.emit(output, x86_64.add_reg_reg(0, 1))
        elif operator == "-":
            call assembler.emit(output, x86_64.sub_reg_reg(0, 1))
        elif operator == "*":
            call assembler.emit(output, x86_64.imul_reg_reg(0, 1))
        elif operator == "^":
            power_ready = label_name(generator, "power_ready")
            call assembler.emit(output, x86_64.cmp_reg_imm8(1, 0))
            call assembler.relative(output, [15, 141], power_ready)
            power_source_path = syntax.get("path", generator["path"])
            power_message = "ValueError: negative Int exponent at " + power_source_path + ":" + String(syntax["line"])
            call emit_runtime_raise(generator, power_message)
            call assembler.label(output, power_ready)
            call assembler.emit(output, x86_64.move_reg_reg(7, 0))
            call assembler.emit(output, x86_64.move_reg_reg(6, 1))
            call assembler.relative(output, [232], "runtime_int_power")
        elif (operator == "//" or operator == "%") and power_of_two_exponent(syntax["right"]) >= 0:
            # Strength reduction: a % 2^k == a & (2^k-1), a // 2^k == a >> k
            # (arithmetic), exact under Python floor semantics for every a
            # including negatives and INT64_MIN. No idiv, no -1/overflow guard.
            power_exponent = power_of_two_exponent(syntax["right"])
            if operator == "%":
                call assembler.emit(output, x86_64.mov_imm64(1, semantic.integer_literal(syntax["right"]) - 1))
                call assembler.emit(output, x86_64.and_reg_reg(0, 1))
            else:
                call assembler.emit(output, x86_64.shift_right_arithmetic_imm(0, power_exponent))
            end
        elif (operator == "//" or operator == "%") and syntax["right"]["kind"] == "literal" and syntax["right"]["literal_kind"] == "number" and syntax["right"]["value"].find(".") < 0 and syntax["right"]["value"].find("e") < 0 and syntax["right"]["value"].find("E") < 0 and semantic.integer_literal(syntax["right"]) >= 3 and semantic.integer_literal(syntax["right"]) < 2147483648 and power_of_two_exponent(syntax["right"]) < 0:
            # Magic-number division: replace idiv by a signed high-multiply.
            # n is already in reg0. quotient q = floor(n/d); remainder via
            # n - q*d. d is a positive non-power-of-two constant in [3, 2^31).
            divisor_value = semantic.integer_literal(syntax["right"])
            magic_pair = magic_signed(divisor_value)
            magic_number = magic_pair[0]
            magic_shift = magic_pair[1]
            floor_done = label_name(generator, "magic_floor_done")
            call assembler.emit(output, x86_64.move_reg_reg(6, 0))
            call assembler.emit(output, x86_64.mov_imm64(1, magic_number))
            call assembler.emit(output, x86_64.imul_high_reg(1))
            if magic_number < 0:
                call assembler.emit(output, x86_64.add_reg_reg(2, 6))
            end
            if magic_shift > 0:
                call assembler.emit(output, x86_64.shift_right_arithmetic_imm(2, magic_shift))
            end
            call assembler.emit(output, x86_64.move_reg_reg(8, 6))
            call assembler.emit(output, x86_64.shift_right_logical_imm(8, 63))
            call assembler.emit(output, x86_64.add_reg_reg(2, 8))
            # reg2 = trunc(n/d). Convert to Python floor via the remainder.
            call assembler.emit(output, x86_64.mov_imm64(1, divisor_value))
            call assembler.emit(output, x86_64.move_reg_reg(9, 2))
            call assembler.emit(output, x86_64.imul_reg_reg(9, 1))
            call assembler.emit(output, x86_64.move_reg_reg(0, 6))
            call assembler.emit(output, x86_64.sub_reg_reg(0, 9))
            # reg0 = C remainder (sign of n). d>0, so if remainder<0 floor-correct.
            call assembler.emit(output, x86_64.cmp_reg_imm8(0, 0))
            call assembler.relative(output, [15, 141], floor_done)
            call assembler.emit(output, x86_64.decrement(2))
            call assembler.emit(output, x86_64.add_reg_reg(0, 1))
            call assembler.label(output, floor_done)
            if operator == "//":
                call assembler.emit(output, x86_64.move_reg_reg(0, 2))
            end
        elif operator == "//" or operator == "%":
            division_ready = label_name(generator, "division_ready")
            call assembler.emit(output, x86_64.cmp_reg_imm8(1, 0))
            call assembler.relative(output, [15, 133], division_ready)
            zero_source_path = syntax.get("path", generator["path"])
            zero_message = "ZeroDivisionError: integer division or modulo by zero at " + zero_source_path + ":" + String(syntax["line"])
            call emit_runtime_raise(generator, zero_message)
            call assembler.label(output, division_ready)
            # Divisor -1 overflows idiv on INT64_MIN (#DE/SIGFPE). a // -1 == -a
            # and a % -1 == 0 for all representable a; INT64_MIN wraps like other
            # Int overflow instead of crashing.
            division_neg_one = label_name(generator, "division_neg_one")
            division_computed = label_name(generator, "division_computed")
            call assembler.emit(output, x86_64.cmp_reg_imm8(1, -1))
            call assembler.relative(output, [15, 132], division_neg_one)
            call assembler.emit(output, x86_64.cqo())
            call assembler.emit(output, x86_64.idiv_reg(1))
            division_floor_done = label_name(generator, "division_floor_done")
            call assembler.emit(output, x86_64.cmp_reg_imm8(2, 0))
            call assembler.relative(output, [15, 132], division_floor_done)
            call assembler.emit(output, x86_64.move_reg_reg(8, 2))
            call assembler.emit(output, x86_64.xor_reg_reg(8, 1))
            call assembler.emit(output, x86_64.cmp_reg_imm8(8, 0))
            call assembler.relative(output, [15, 141], division_floor_done)
            call assembler.emit(output, x86_64.decrement(0))
            call assembler.emit(output, x86_64.add_reg_reg(2, 1))
            call assembler.label(output, division_floor_done)
            call assembler.relative(output, [233], division_computed)
            call assembler.label(output, division_neg_one)
            call assembler.emit(output, x86_64.neg_reg(0))
            call assembler.emit(output, x86_64.xor_reg_reg(2, 2))
            call assembler.label(output, division_computed)
            if operator == "%":
                call assembler.emit(output, x86_64.move_reg_reg(0, 2))
            end
        elif operator == "and" or operator == "or":
            call assembler.emit(output, x86_64.cmp_reg_imm8(0, 0))
            call assembler.emit(output, x86_64.set_condition(149))
            call assembler.emit(output, x86_64.push(0))
            call assembler.emit(output, x86_64.move_reg_reg(0, 1))
            call assembler.emit(output, x86_64.cmp_reg_imm8(0, 0))
            call assembler.emit(output, x86_64.set_condition(149))
            call assembler.emit(output, x86_64.move_reg_reg(1, 0))
            call assembler.emit(output, x86_64.pop(0))
            if operator == "and":
                call assembler.emit(output, x86_64.and_reg_reg(0, 1))
            else:
                call assembler.emit(output, x86_64.or_reg_reg(0, 1))
            end
        else:
            Error(CompileError: "invalid analyzed program")
        end
    elif kind == "call":
        target = syntax["target"]
        if target["kind"] == "name":
            if target["name"] == "help" or help_family(target["name"]):
                generator["help_used"] = True
            end
            if lazy_runtime(target["name"]):
                generator["lazy_used"][target["name"]] = True
            end
            if emit_validation_error(generator, syntax, "call_keywords"):
                return
            end
            if emit_validation_error(generator, syntax, "help_arity"):
                return
            end
            if emit_validation_error(generator, syntax, "builtin_arity"):
                return
            end
            if emit_validation_error(generator, syntax, "array_arity"):
                return
            end
            if target["name"].startswith("__lsl_declared_"):
                declared = target["name"][15:len(target["name"])]
                value = syntax["arguments"][0]
                actual = semantic.infer_expression_type(value, generator["types"], generator["function_returns"])
                if actual == declared:
                    call emit_expression(generator, value)
                    return
                end
                required = {"kind": "literal", "literal_kind": "string", "value": declared, "line": syntax["line"], "column": syntax["column"], "end_column": syntax["end_column"]}
                check_call = {"kind": "call", "target": {"kind": "name", "name": "__lsl_require_declared"}, "arguments": [value, required], "line": syntax["line"], "column": syntax["column"], "end_column": syntax["end_column"]}
                call emit_expression(generator, check_call)
                if declared == "Int" or declared == "Bool":
                    call assembler.emit(output, x86_64.move_reg_reg(7, 0))
                    if declared == "Int":
                        call assembler.relative(output, [232], "runtime_unbox_dynamic_int")
                    else:
                        call assembler.relative(output, [232], "runtime_unbox_bool")
                    end
                end
                return
            elif target["name"] == "sorted" or target["name"] == "dedup" or target["name"] == "set":
                collection_arguments = syntax["arguments"]
                if len(collection_arguments) == 0:
                    collection_arguments = [{"kind": "list", "items": [], "line": syntax["line"], "column": syntax["column"], "end_column": syntax["end_column"]}]
                end
                collection_call = {"kind": "call", "line": syntax["line"], "column": syntax["column"], "end_column": syntax["end_column"], "target": {"kind": "name", "name": "__lsl_" + target["name"]}, "arguments": collection_arguments}
                call emit_expression(generator, collection_call)
                return
            elif target["name"] == "__lsl_new_set":
                call assembler.emit(output, x86_64.mov_imm64(7, 0))
                call assembler.emit(output, x86_64.mov_imm64(6, 0))
                call assembler.relative(output, [232], "runtime_list_new")
                call assembler.emit(output, x86_64.store_memory_imm32(0, abi_x86_64.OBJECT_TAG, value_abi.TAG_SET))
                return
            elif target["name"] == "__lsl_set_append" or target["name"] == "__lsl_set_store":
                call emit_expression(generator, syntax["arguments"][0])
                call assembler.emit(output, x86_64.push(0))
                if target["name"] == "__lsl_set_store":
                    call emit_expression(generator, syntax["arguments"][1])
                    call assembler.emit(output, x86_64.move_reg_reg(7, 0))
                    call assembler.relative(output, [232], "runtime_unbox_dynamic_int")
                    call assembler.emit(output, x86_64.push(0))
                end
                call emit_expression(generator, syntax["arguments"][len(syntax["arguments"]) - 1])
                call emit_collection_box(generator, syntax["arguments"][len(syntax["arguments"]) - 1])
                if target["name"] == "__lsl_set_append":
                    call assembler.emit(output, x86_64.move_reg_reg(6, 0))
                    call assembler.emit(output, x86_64.pop(7))
                    call assembler.relative(output, [232], "runtime_list_append")
                else:
                    call assembler.emit(output, x86_64.pop(6))
                    call assembler.emit(output, x86_64.pop(7))
                    call assembler.emit(output, x86_64.load_memory(7, 7, 24))
                    call assembler.emit(output, x86_64.store_indexed(7, 6, 3, 0))
                end
                call assembler.emit(output, x86_64.mov_imm64(0, 0))
                return
            elif target["name"] == "IntArray" or target["name"] == "FloatArray" or target["name"] == "ByteArray":
                expected_array_code = 13
                if target["name"] == "FloatArray":
                    expected_array_code = 14
                elif target["name"] == "ByteArray":
                    expected_array_code = 15
                end
                if len(syntax["arguments"]) == 0:
                    if target["name"] == "ByteArray":
                        call assembler.relative(output, [232], "runtime_byte_array_new")
                    else:
                        call assembler.emit(output, x86_64.mov_imm64(7, 0))
                        call assembler.emit(output, x86_64.mov_imm64(6, 0))
                        call assembler.relative(output, [232], "runtime_list_new")
                        call assembler.emit(output, x86_64.store_memory_imm32(0, 0, expected_array_code))
                    end
                    return
                end
                array_cast_ok = label_name(generator, "array_cast_ok")
                call emit_expression(generator, syntax["arguments"][0])
                call assembler.emit(output, x86_64.push(0))
                call assembler.emit(output, x86_64.move_reg_reg(7, 0))
                call assembler.relative(output, [232], "runtime_type_code")
                call assembler.emit(output, x86_64.cmp_reg_imm8(0, expected_array_code))
                call assembler.relative(output, [15, 132], array_cast_ok)
                call assembler.emit(output, x86_64.pop(0))
                call emit_runtime_raise(generator, "TypeError: " + target["name"] + "(value) only converts an existing " + target["name"] + "; create an empty one with " + target["name"] + "() and add items with append")
                call assembler.label(output, array_cast_ok)
                call assembler.emit(output, x86_64.pop(0))
                return
            elif target["name"] == "float_zeros":
                if emit_validation_error(generator, syntax["arguments"][0], "float_zeros"):
                    return
                end
                call emit_expression(generator, syntax["arguments"][0])
                zeros_size_ok = label_name(generator, "zeros_size_ok")
                call assembler.emit(output, x86_64.cmp_reg_imm8(0, 0))
                call assembler.relative(output, [15, 141], zeros_size_ok)
                call emit_runtime_raise(generator, "ValueError: float_zeros size cannot be negative")
                call assembler.label(output, zeros_size_ok)
                call assembler.emit(output, x86_64.move_reg_reg(7, 0))
                call assembler.emit(output, x86_64.xor_reg_reg(6, 6))
                call assembler.relative(output, [232], "runtime_list_new")
                call assembler.emit(output, x86_64.store_memory_imm32(0, abi_x86_64.OBJECT_TAG, value_abi.TAG_FLOAT_ARRAY))
                return
            elif target["name"] == "__lsl_floatarray_bytes":
                if emit_validation_error(generator, syntax["arguments"][0], "floatarray_bytes"):
                    return
                end
                call emit_expression(generator, syntax["arguments"][0])
                call assembler.emit(output, x86_64.move_reg_reg(7, 0))
                call assembler.relative(output, [232], "runtime_float_array_bytes")
                return
            elif target["name"] == "__lsl_text_byte_length":
                if emit_validation_error(generator, syntax["arguments"][0], "text_byte_length"):
                    return
                end
                call emit_expression(generator, syntax["arguments"][0])
                call assembler.emit(output, x86_64.load_memory(0, 0, 8))
                return
            elif target["name"] == "__lsl_floatarray_from_bytes":
                if emit_validation_error(generator, syntax["arguments"][0], "floatarray_from_bytes"):
                    return
                end
                call emit_expression(generator, syntax["arguments"][0])
                call assembler.emit(output, x86_64.move_reg_reg(7, 0))
                call assembler.relative(output, [232], "runtime_float_array_from_bytes")
                return
            elif target["name"] == "__lsl_int_zeros":
                call emit_expression(generator, syntax["arguments"][0])
                if semantic.infer_expression_type(syntax["arguments"][0], generator["types"], generator["function_returns"]) == "Any":
                    call assembler.emit(output, x86_64.move_reg_reg(7, 0))
                    call assembler.relative(output, [232], "runtime_unbox_dynamic_int")
                end
                int_zeros_size_ok = label_name(generator, "int_zeros_size_ok")
                call assembler.emit(output, x86_64.cmp_reg_imm8(0, 0))
                call assembler.relative(output, [15, 141], int_zeros_size_ok)
                call emit_runtime_raise(generator, "ValueError: IntArray size cannot be negative")
                call assembler.label(output, int_zeros_size_ok)
                call assembler.emit(output, x86_64.move_reg_reg(7, 0))
                call assembler.emit(output, x86_64.xor_reg_reg(6, 6))
                call assembler.relative(output, [232], "runtime_list_new")
                call assembler.emit(output, x86_64.store_memory_imm32(0, abi_x86_64.OBJECT_TAG, value_abi.TAG_INT_ARRAY))
                return
            elif target["name"] == "__lsl_byte_zeros":
                call emit_expression(generator, syntax["arguments"][0])
                if semantic.infer_expression_type(syntax["arguments"][0], generator["types"], generator["function_returns"]) == "Any":
                    call assembler.emit(output, x86_64.move_reg_reg(7, 0))
                    call assembler.relative(output, [232], "runtime_unbox_dynamic_int")
                end
                byte_zeros_size_ok = label_name(generator, "byte_zeros_size_ok")
                call assembler.emit(output, x86_64.cmp_reg_imm8(0, 0))
                call assembler.relative(output, [15, 141], byte_zeros_size_ok)
                call emit_runtime_raise(generator, "ValueError: ByteArray size cannot be negative")
                call assembler.label(output, byte_zeros_size_ok)
                call assembler.emit(output, x86_64.move_reg_reg(7, 0))
                call assembler.relative(output, [232], "runtime_byte_array_zeros")
                return
            elif target["name"] == "__lsl_raster_pack" or target["name"] == "__lsl_raster_copy" or target["name"] == "__lsl_byte_copy":
                # (array, array, off, off, count): arrays stay boxed object
                # pointers, the three scalars go through the dynamic unboxer
                # (a no-op for raw Ints). The runtime type-checks and clamps.
                call emit_expression(generator, syntax["arguments"][0])
                call assembler.emit(output, x86_64.push(0))
                call emit_expression(generator, syntax["arguments"][1])
                call assembler.emit(output, x86_64.push(0))
                call emit_expression(generator, syntax["arguments"][2])
                call assembler.emit(output, x86_64.move_reg_reg(7, 0))
                call assembler.relative(output, [232], "runtime_unbox_dynamic_int")
                call assembler.emit(output, x86_64.push(0))
                call emit_expression(generator, syntax["arguments"][3])
                call assembler.emit(output, x86_64.move_reg_reg(7, 0))
                call assembler.relative(output, [232], "runtime_unbox_dynamic_int")
                call assembler.emit(output, x86_64.push(0))
                call emit_expression(generator, syntax["arguments"][4])
                call assembler.emit(output, x86_64.move_reg_reg(7, 0))
                call assembler.relative(output, [232], "runtime_unbox_dynamic_int")
                call assembler.emit(output, x86_64.move_reg_reg(8, 0))
                call assembler.emit(output, x86_64.pop(1))
                call assembler.emit(output, x86_64.pop(2))
                call assembler.emit(output, x86_64.pop(6))
                call assembler.emit(output, x86_64.pop(7))
                if target["name"] == "__lsl_raster_pack":
                    call assembler.relative(output, [232], "runtime_raster_pack")
                elif target["name"] == "__lsl_byte_copy":
                    call assembler.relative(output, [232], "runtime_byte_copy")
                else:
                    call assembler.relative(output, [232], "runtime_raster_copy")
                end
                return
            elif target["name"] == "__lsl_raster_fill":
                call emit_expression(generator, syntax["arguments"][0])
                call assembler.emit(output, x86_64.push(0))
                call emit_expression(generator, syntax["arguments"][1])
                call assembler.emit(output, x86_64.move_reg_reg(7, 0))
                call assembler.relative(output, [232], "runtime_unbox_dynamic_int")
                call assembler.emit(output, x86_64.push(0))
                call emit_expression(generator, syntax["arguments"][2])
                call assembler.emit(output, x86_64.move_reg_reg(7, 0))
                call assembler.relative(output, [232], "runtime_unbox_dynamic_int")
                call assembler.emit(output, x86_64.push(0))
                call emit_expression(generator, syntax["arguments"][3])
                call assembler.emit(output, x86_64.move_reg_reg(7, 0))
                call assembler.relative(output, [232], "runtime_unbox_dynamic_int")
                call assembler.emit(output, x86_64.move_reg_reg(1, 0))
                call assembler.emit(output, x86_64.pop(2))
                call assembler.emit(output, x86_64.pop(6))
                call assembler.emit(output, x86_64.pop(7))
                call assembler.relative(output, [232], "runtime_raster_fill")
                return
            elif target["name"] == "float_fill":
                if emit_validation_error(generator, syntax, "float_fill"):
                    return
                end
                call emit_expression(generator, syntax["arguments"][0])
                call assembler.emit(output, x86_64.push(0))
                call emit_expression(generator, syntax["arguments"][1])
                call assembler.emit(output, x86_64.load_memory(6, 0, 8))
                call assembler.emit(output, x86_64.pop(7))
                call assembler.relative(output, [232], "runtime_float_array_fill")
                return
            elif target["name"] == "float_sum":
                if emit_validation_error(generator, syntax["arguments"][0], "float_sum"):
                    return
                end
                call emit_expression(generator, syntax["arguments"][0])
                call assembler.emit(output, x86_64.move_reg_reg(7, 0))
                call assembler.relative(output, [232], "runtime_float_array_sum")
                return
            elif target["name"] == "float_dot":
                if emit_validation_error(generator, syntax, "float_dot"):
                    return
                end
                call emit_expression(generator, syntax["arguments"][0])
                call assembler.emit(output, x86_64.push(0))
                call emit_expression(generator, syntax["arguments"][1])
                call assembler.emit(output, x86_64.move_reg_reg(6, 0))
                call assembler.emit(output, x86_64.pop(7))
                dot_lengths_ok = label_name(generator, "dot_lengths_ok")
                call assembler.emit(output, x86_64.load_memory(1, 7, 8))
                call assembler.emit(output, x86_64.load_memory(2, 6, 8))
                call assembler.emit(output, x86_64.cmp_reg_reg(1, 2))
                call assembler.relative(output, [15, 132], dot_lengths_ok)
                call emit_runtime_raise(generator, "ValueError: float_dot requires equal lengths")
                call assembler.label(output, dot_lengths_ok)
                call assembler.relative(output, [232], "runtime_float_array_dot")
                return
            elif target["name"] == "float_matmul":
                if emit_validation_error(generator, syntax, "float_matmul"):
                    return
                end
                for argument in syntax["arguments"]:
                    call emit_expression(generator, argument)
                    call assembler.emit(output, x86_64.push(0))
                end
                call assembler.emit(output, x86_64.pop(8))
                call assembler.emit(output, x86_64.pop(1))
                call assembler.emit(output, x86_64.pop(2))
                call assembler.emit(output, x86_64.pop(6))
                call assembler.emit(output, x86_64.pop(7))
                matmul_shape_error = label_name(generator, "matmul_shape_error")
                matmul_shape_ok = label_name(generator, "matmul_shape_ok")
                call assembler.emit(output, x86_64.cmp_reg_imm8(2, 0))
                call assembler.relative(output, [15, 140], matmul_shape_error)
                call assembler.emit(output, x86_64.cmp_reg_imm8(1, 0))
                call assembler.relative(output, [15, 140], matmul_shape_error)
                call assembler.emit(output, x86_64.cmp_reg_imm8(8, 0))
                call assembler.relative(output, [15, 140], matmul_shape_error)
                call assembler.emit(output, x86_64.move_reg_reg(9, 2))
                call assembler.emit(output, x86_64.imul_reg_reg(9, 1))
                call assembler.emit(output, x86_64.load_memory(10, 7, 8))
                call assembler.emit(output, x86_64.cmp_reg_reg(9, 10))
                call assembler.relative(output, [15, 133], matmul_shape_error)
                call assembler.emit(output, x86_64.move_reg_reg(9, 1))
                call assembler.emit(output, x86_64.imul_reg_reg(9, 8))
                call assembler.emit(output, x86_64.load_memory(10, 6, 8))
                call assembler.emit(output, x86_64.cmp_reg_reg(9, 10))
                call assembler.relative(output, [15, 132], matmul_shape_ok)
                call assembler.label(output, matmul_shape_error)
                call emit_runtime_raise(generator, "ValueError: float_matmul shape does not match array lengths")
                call assembler.label(output, matmul_shape_ok)
                call assembler.relative(output, [232], "runtime_float_array_matmul")
                return
            elif target["name"] == "float_axpy":
                if emit_validation_error(generator, syntax, "float_axpy"):
                    return
                end
                call emit_expression(generator, syntax["arguments"][0])
                call assembler.emit(output, x86_64.load_memory(0, 0, 8))
                call assembler.emit(output, x86_64.push(0))
                call emit_expression(generator, syntax["arguments"][1])
                call assembler.emit(output, x86_64.push(0))
                call emit_expression(generator, syntax["arguments"][2])
                call assembler.emit(output, x86_64.move_reg_reg(2, 0))
                call assembler.emit(output, x86_64.pop(6))
                call assembler.emit(output, x86_64.pop(7))
                axpy_lengths_ok = label_name(generator, "axpy_lengths_ok")
                call assembler.emit(output, x86_64.load_memory(1, 6, 8))
                call assembler.emit(output, x86_64.load_memory(8, 2, 8))
                call assembler.emit(output, x86_64.cmp_reg_reg(1, 8))
                call assembler.relative(output, [15, 132], axpy_lengths_ok)
                call emit_runtime_raise(generator, "ValueError: float_axpy requires equal lengths")
                call assembler.label(output, axpy_lengths_ok)
                call assembler.relative(output, [232], "runtime_float_array_axpy")
                return
            elif target["name"] == "Bool":
                call emit_expression(generator, syntax["arguments"][0])
                call emit_truth(generator)
                call assembler.emit(output, x86_64.cmp_reg_imm8(0, 0))
                call assembler.emit(output, x86_64.set_condition(149))
                return
            elif target["name"] == "check":
                check_ok = label_name(generator, "check_ok")
                call emit_expression(generator, syntax["arguments"][0])
                call emit_truth(generator)
                call assembler.emit(output, x86_64.cmp_reg_imm8(0, 0))
                call assembler.relative(output, [15, 133], check_ok)
                call emit_expression(generator, syntax["arguments"][1])
                call runtime.thread_store(generator["runtime"], output, runtime.ERROR, 0)
                call runtime.thread_store_immediate(generator["runtime"], output, runtime.ERROR_FLAG, 1)
                if generator["error_label"] != "":
                    call assembler.relative(output, [233], generator["error_label"])
                else:
                    call emit_static_write_fd(generator, "LSL runtime error: CheckError" + chr(10), 2)
                    call runtime.release_input(generator["runtime"], output)
                    call assembler.emit(output, x86_64.mov_imm64(7, 1))
                    call runtime.emit_exit(generator["runtime"], output)
                end
                call assembler.label(output, check_ok)
                call assembler.emit(output, x86_64.mov_imm64(0, 0))
                return
            elif target["name"] == "List" or target["name"] == "Tuple" or target["name"] == "RealArray":
                conversion_target = "__lsl_list"
                if target["name"] == "RealArray":
                    conversion_target = "__lsl_real_array"
                end
                conversion_call = {"kind": "call", "line": syntax["line"], "column": syntax["column"], "end_column": syntax["end_column"], "target": {"kind": "name", "name": conversion_target}, "arguments": syntax["arguments"]}
                call emit_expression(generator, conversion_call)
                if target["name"] == "Tuple":
                    call assembler.emit(output, x86_64.store_memory_imm32(0, abi_x86_64.OBJECT_TAG, value_abi.TAG_TUPLE))
                elif target["name"] == "RealArray":
                    call assembler.emit(output, x86_64.store_memory_imm32(0, abi_x86_64.OBJECT_TAG, value_abi.TAG_REAL_ARRAY))
                end
                return
            elif target["name"] == "Dictionary":
                dictionary_call = {"kind": "call", "line": syntax["line"], "column": syntax["column"], "end_column": syntax["end_column"], "target": {"kind": "name", "name": "__lsl_dictionary"}, "arguments": syntax["arguments"]}
                call emit_expression(generator, dictionary_call)
                return
            elif target["name"] == "sum":
                sum_target = "__lsl_sum"
                if not generator["internal_abi"] and not generator.get("current_internal_function", False):
                    sum_target = "__lsl_public_sum"
                end
                sum_call = {"kind": "call", "line": syntax["line"], "column": syntax["column"], "end_column": syntax["end_column"], "target": {"kind": "name", "name": sum_target}, "arguments": syntax["arguments"]}
                call emit_expression(generator, sum_call)
                return
            elif target["name"] == "__lsl_float_accumulate":
                call emit_expression(generator, syntax["arguments"][0])
                call assembler.emit(output, x86_64.push(0))
                call emit_expression(generator, syntax["arguments"][1])
                if semantic.infer_expression_type(syntax["arguments"][1], generator["types"], generator["function_returns"]) == "Any":
                    call assembler.emit(output, x86_64.move_reg_reg(7, 0))
                    call assembler.relative(output, [232], "runtime_unbox_dynamic_int")
                end
                call assembler.emit(output, x86_64.move_reg_reg(6, 0))
                call assembler.emit(output, x86_64.pop(7))
                call assembler.relative(output, [232], "runtime_float_accumulate")
                return
            elif target["name"] == "__lsl_float_candidate_bits":
                for argument in syntax["arguments"]:
                    call emit_expression(generator, argument)
                    if semantic.infer_expression_type(argument, generator["types"], generator["function_returns"]) == "Any":
                        call assembler.emit(output, x86_64.move_reg_reg(7, 0))
                        call assembler.relative(output, [232], "runtime_unbox_dynamic_int")
                    end
                    call assembler.emit(output, x86_64.push(0))
                end
                call assembler.emit(output, x86_64.pop(2))
                call assembler.emit(output, x86_64.pop(6))
                call assembler.emit(output, x86_64.pop(7))
                call assembler.relative(output, [232], "runtime_float_candidate_bits")
                return
            elif target["name"] == "__lsl_float_from_decimal":
                for argument in syntax["arguments"]:
                    call emit_expression(generator, argument)
                    if semantic.infer_expression_type(argument, generator["types"], generator["function_returns"]) == "Any":
                        call assembler.emit(output, x86_64.move_reg_reg(7, 0))
                        call assembler.relative(output, [232], "runtime_unbox_dynamic_int")
                    end
                    call assembler.emit(output, x86_64.push(0))
                end
                call assembler.emit(output, x86_64.pop(6))
                call assembler.emit(output, x86_64.pop(7))
                call assembler.relative(output, [232], "runtime_decimal_bits")
                return
            elif target["name"] == "__lsl_decimal_compare":
                for argument in syntax["arguments"]:
                    call emit_expression(generator, argument)
                    if semantic.infer_expression_type(argument, generator["types"], generator["function_returns"]) == "Any":
                        call assembler.emit(output, x86_64.move_reg_reg(7, 0))
                        call assembler.relative(output, [232], "runtime_unbox_dynamic_int")
                    end
                    call assembler.emit(output, x86_64.push(0))
                end
                call assembler.emit(output, x86_64.pop(1))
                call assembler.emit(output, x86_64.pop(2))
                call assembler.emit(output, x86_64.pop(6))
                call assembler.emit(output, x86_64.pop(7))
                call assembler.relative(output, [232], "runtime_decimal_compare")
                return
            elif target["name"] == "__lsl_float_nearer_upper":
                for argument in syntax["arguments"]:
                    call emit_expression(generator, argument)
                    if semantic.infer_expression_type(argument, generator["types"], generator["function_returns"]) == "Any":
                        call assembler.emit(output, x86_64.move_reg_reg(7, 0))
                        call assembler.relative(output, [232], "runtime_unbox_dynamic_int")
                    end
                    call assembler.emit(output, x86_64.push(0))
                end
                call assembler.emit(output, x86_64.pop(1))
                call assembler.emit(output, x86_64.pop(2))
                call assembler.emit(output, x86_64.pop(6))
                call assembler.emit(output, x86_64.pop(7))
                call assembler.relative(output, [232], "runtime_float_nearer_upper")
                return
            elif target["name"] == "__lsl_decimal_digits_compare":
                # První argument je ByteArray číslic (objekt, nerozbaluje se).
                call emit_expression(generator, syntax["arguments"][0])
                call assembler.emit(output, x86_64.push(0))
                for argument in syntax["arguments"][1:]:
                    call emit_expression(generator, argument)
                    if semantic.infer_expression_type(argument, generator["types"], generator["function_returns"]) == "Any":
                        call assembler.emit(output, x86_64.move_reg_reg(7, 0))
                        call assembler.relative(output, [232], "runtime_unbox_dynamic_int")
                    end
                    call assembler.emit(output, x86_64.push(0))
                end
                call assembler.emit(output, x86_64.pop(8))
                call assembler.emit(output, x86_64.pop(1))
                call assembler.emit(output, x86_64.pop(2))
                call assembler.emit(output, x86_64.pop(6))
                call assembler.emit(output, x86_64.pop(7))
                call assembler.relative(output, [232], "runtime_decimal_digits_compare")
                return
            elif target["name"] == "__lsl_float_string":
                call emit_expression(generator, syntax["arguments"][0])
                call assembler.emit(output, x86_64.move_reg_reg(7, 0))
                call assembler.relative(output, [232], "runtime_float_to_string")
                return
            elif target["name"] == "__lsl_float_from_int":
                call emit_expression(generator, syntax["arguments"][0])
                call assembler.emit(output, x86_64.move_reg_reg(7, 0))
                call assembler.relative(output, [232], "runtime_float_from_int")
                return
            elif target["name"] == "__lsl_float_to_int":
                call emit_expression(generator, syntax["arguments"][0])
                call assembler.emit(output, x86_64.move_reg_reg(7, 0))
                call assembler.relative(output, [232], "runtime_float_to_int")
                return
            elif target["name"] == "__lsl_float_bits":
                call emit_expression(generator, syntax["arguments"][0])
                call assembler.emit(output, x86_64.load_memory(0, 0, 8))
                return
            elif target["name"] == "__lsl_float_from_bits":
                call emit_expression(generator, syntax["arguments"][0])
                call assembler.emit(output, x86_64.move_reg_reg(7, 0))
                call assembler.relative(output, [232], "runtime_float_new")
                return
            elif target["name"] == "__lsl_raw_equal":
                call emit_expression(generator, syntax["arguments"][0])
                call assembler.emit(output, x86_64.push(0))
                call emit_expression(generator, syntax["arguments"][1])
                call assembler.emit(output, x86_64.move_reg_reg(6, 0))
                call assembler.emit(output, x86_64.pop(7))
                call assembler.relative(output, [232], "runtime_equal_any")
                return
            elif target["name"] == "__lsl_is_heap":
                call emit_expression(generator, syntax["arguments"][0])
                call assembler.emit(output, x86_64.move_reg_reg(7, 0))
                call assembler.relative(output, [232], "runtime_is_heap_object")
                return
            elif target["name"] == "__lsl_test_small_tables":
                call assembler.relative(output, [232], "runtime_test_small_tables")
                return
            elif target["name"] == "__lsl_test_fd_fault":
                call emit_expression(generator, syntax["arguments"][0])
                call assembler.emit(output, x86_64.move_reg_reg(7, 0))
                call assembler.relative(output, [232], "runtime_test_fd_fault")
                return
            elif target["name"] == "__lsl_object_table_mask":
                call assembler.relative(output, [232], "runtime_object_table_mask")
                return
            elif target["name"] == "__lsl_intern_table_mask":
                call assembler.relative(output, [232], "runtime_intern_table_mask")
                return
            elif target["name"] == "__lsl_address":
                # Test/audit intrinsic: expose object bits as a statically typed
                # Int to prove that every dynamic boundary boxes the collision.
                call emit_expression(generator, syntax["arguments"][0])
                return
            elif target["name"] == "__lsl_raw_int":
                # Identity that types the value as Int, so a known-raw-Int Any
                # takes the static Int path without the is_heap/type_code probe
                # in Int() (which errors on raw 0, whose type code reads as None).
                call emit_expression(generator, syntax["arguments"][0])
                return
            elif target["name"] == "__lsl_typed_int":
                call emit_expression(generator, syntax["arguments"][0])
                call assembler.emit(output, x86_64.move_reg_reg(7, 0))
                call assembler.relative(output, [232], "runtime_unbox_dynamic_int")
                return
            elif target["name"] == "__lsl_checked_index":
                call emit_expression(generator, syntax["arguments"][0])
                call assembler.emit(output, x86_64.move_reg_reg(7, 0))
                call assembler.relative(output, [232], "runtime_checked_index")
                call emit_pending_error(generator)
                return
            elif target["name"] == "__lsl_parse_literal_int":
                call emit_expression(generator, syntax["arguments"][0])
                call assembler.emit(output, x86_64.move_reg_reg(7, 0))
                call assembler.relative(output, [232], "runtime_parse_literal_int")
                return
            elif target["name"] == "__lsl_string_chars":
                call emit_expression(generator, syntax["arguments"][0])
                call assembler.emit(output, x86_64.move_reg_reg(7, 0))
                call assembler.relative(output, [232], "runtime_string_chars")
                return
            elif target["name"] == "__lsl_type_code":
                call emit_expression(generator, syntax["arguments"][0])
                call assembler.emit(output, x86_64.move_reg_reg(7, 0))
                call assembler.relative(output, [232], "runtime_type_code")
                return
            elif target["name"] == "__lsl_box_bool":
                call emit_expression(generator, syntax["arguments"][0])
                call assembler.emit(output, x86_64.move_reg_reg(7, 0))
                call assembler.relative(output, [232], "runtime_box_bool")
                return
            elif target["name"] == "__lsl_box_int":
                call emit_expression(generator, syntax["arguments"][0])
                call assembler.emit(output, x86_64.move_reg_reg(7, 0))
                call assembler.relative(output, [232], "runtime_box_int")
                return
            elif target["name"] == "__lsl_box_function":
                call emit_expression(generator, syntax["arguments"][0])
                call assembler.emit(output, x86_64.mov_imm64(6, -1))
                call assembler.emit(output, x86_64.move_reg_reg(7, 0))
                call assembler.relative(output, [232], "runtime_box_function")
                return
            elif target["name"] == "__lsl_box_none":
                call assembler.relative(output, [232], "runtime_box_none")
                return
            elif target["name"] == "__lsl_unbox_bool":
                call emit_expression(generator, syntax["arguments"][0])
                call assembler.emit(output, x86_64.move_reg_reg(7, 0))
                call assembler.relative(output, [232], "runtime_unbox_bool")
                return
            elif target["name"] == "__lsl_unbox_int":
                call emit_expression(generator, syntax["arguments"][0])
                call assembler.emit(output, x86_64.move_reg_reg(7, 0))
                call assembler.relative(output, [232], "runtime_unbox_int")
                return
            elif target["name"] == "__lsl_pop_last":
                call emit_expression(generator, syntax["arguments"][0])
                call assembler.emit(output, x86_64.move_reg_reg(7, 0))
                call assembler.relative(output, [232], "runtime_list_pop_last")
                return
            elif target["name"] == "len":
                length_type = semantic.infer_expression_type(syntax["arguments"][0], generator["types"], generator["function_returns"])
                if emit_validation_error(generator, syntax["arguments"][0], "length_target"):
                    return
                end
                call emit_expression(generator, syntax["arguments"][0])
                call assembler.emit(output, x86_64.move_reg_reg(7, 0))
                if length_type == "Any" and not generator["internal_abi"]:
                    call assembler.relative(output, [232], "runtime_dynamic_length")
                    call emit_pending_error(generator)
                else:
                    call assembler.relative(output, [232], "runtime_length")
                end
                return
            elif target["name"] == "Int":
                argument_type = semantic.infer_expression_type(syntax["arguments"][0], generator["types"], generator["function_returns"])
                if argument_type == "String":
                    parse_int_call = {"kind": "call", "line": syntax["line"], "column": syntax["column"], "end_column": syntax["end_column"], "target": {"kind": "name", "name": "__lsl_parse_int"}, "arguments": syntax["arguments"]}
                    call emit_expression(generator, parse_int_call)
                elif argument_type == "Any":
                    int_any_call = {"kind": "call", "line": syntax["line"], "column": syntax["column"], "end_column": syntax["end_column"], "target": {"kind": "name", "name": "__lsl_int_any"}, "arguments": syntax["arguments"]}
                    call emit_expression(generator, int_any_call)
                elif argument_type == "Float":
                    call emit_expression(generator, syntax["arguments"][0])
                    call assembler.emit(output, x86_64.move_reg_reg(7, 0))
                    call assembler.relative(output, [232], "runtime_float_to_int")
                else:
                    call emit_expression(generator, syntax["arguments"][0])
                end
                return
            elif target["name"] == "Float":
                argument_type = semantic.infer_expression_type(syntax["arguments"][0], generator["types"], generator["function_returns"])
                if argument_type == "String":
                    parse_float_call = {"kind": "call", "line": syntax["line"], "column": syntax["column"], "end_column": syntax["end_column"], "target": {"kind": "name", "name": "__lsl_parse_float"}, "arguments": syntax["arguments"]}
                    call emit_expression(generator, parse_float_call)
                elif argument_type == "Any":
                    float_any_call = {"kind": "call", "line": syntax["line"], "column": syntax["column"], "end_column": syntax["end_column"], "target": {"kind": "name", "name": "__lsl_float_any"}, "arguments": syntax["arguments"]}
                    call emit_expression(generator, float_any_call)
                else:
                    call emit_float_expression(generator, syntax["arguments"][0])
                end
                return
            elif target["name"] == "String":
                argument_type = semantic.infer_expression_type(syntax["arguments"][0], generator["types"], generator["function_returns"])
                if argument_type == "String":
                    call emit_expression(generator, syntax["arguments"][0])
                elif argument_type == "Float":
                    format_float_call = {"kind": "call", "line": syntax["line"], "column": syntax["column"], "end_column": syntax["end_column"], "target": {"kind": "name", "name": "__lsl_format_float"}, "arguments": syntax["arguments"]}
                    call emit_expression(generator, format_float_call)
                    # Root the returned String while a post-format pressure
                    # poll reclaims formatter temporaries at a safe boundary.
                    call assembler.emit(output, x86_64.push(0))
                    call emit_gc_poll(generator)
                    call assembler.emit(output, x86_64.pop(0))
                elif argument_type == "Int":
                    call emit_expression(generator, syntax["arguments"][0])
                    call assembler.emit(output, x86_64.move_reg_reg(7, 0))
                    call assembler.relative(output, [232], "runtime_int_to_string")
                elif argument_type == "Bool":
                    # Static Bool is a raw 0/1, which __lsl_str_value would
                    # misread as Int; select the String literal directly.
                    bool_false = label_name(generator, "string_bool_false")
                    bool_done = label_name(generator, "string_bool_done")
                    call emit_expression(generator, syntax["arguments"][0])
                    call assembler.emit(output, x86_64.cmp_reg_imm8(0, 0))
                    call assembler.relative(output, [15, 132], bool_false)
                    call emit_string_pointer(generator, "True")
                    call assembler.relative(output, [233], bool_done)
                    call assembler.label(output, bool_false)
                    call emit_string_pointer(generator, "False")
                    call assembler.label(output, bool_done)
                elif argument_type == "None":
                    call emit_string_pointer(generator, "None")
                else:
                    str_value_call = {"kind": "call", "line": syntax["line"], "column": syntax["column"], "end_column": syntax["end_column"], "target": {"kind": "name", "name": "__lsl_str_value"}, "arguments": syntax["arguments"]}
                    call emit_expression(generator, str_value_call)
                end
                return
            elif target["name"] == "chr":
                call emit_checked_int_expression(generator, syntax["arguments"][0], "chr argument")
                call assembler.emit(output, x86_64.move_reg_reg(7, 0))
                call assembler.relative(output, [232], "runtime_chr")
                return
            elif target["name"] == "ord":
                call emit_expression(generator, checked_string_node(generator, syntax["arguments"][0]))
                call assembler.emit(output, x86_64.move_reg_reg(7, 0))
                call assembler.relative(output, [232], "runtime_ord")
                return
            elif target["name"] == "arg":
                argument_missing = label_name(generator, "argument_missing")
                argument_done = label_name(generator, "argument_done")
                call emit_checked_int_expression(generator, syntax["arguments"][0], "arg index")
                call assembler.emit(output, x86_64.move_reg_reg(6, 0))
                call assembler.emit(output, x86_64.cmp_reg_imm8(6, 0))
                call assembler.relative(output, [15, 140], argument_missing)
                call assembler.emit(output, x86_64.load_memory(11, 3, 120))
                call assembler.emit(output, x86_64.load_memory(1, 11, 0))
                call assembler.emit(output, x86_64.cmp_reg_reg(6, 1))
                call assembler.relative(output, [15, 141], argument_missing)
                call assembler.emit(output, x86_64.lea_base(7, 11, 8))
                call assembler.emit(output, x86_64.load_indexed(7, 7, 6, 3))
                call assembler.relative(output, [232], "runtime_from_cstring")
                call assembler.relative(output, [233], argument_done)
                call assembler.label(output, argument_missing)
                call assembler.emit(output, x86_64.mov_imm64(0, 0))
                call assembler.label(output, argument_done)
                return
            elif target["name"] == "arg_count":
                call assembler.emit(output, x86_64.load_memory(0, 3, 120))
                call assembler.emit(output, x86_64.load_memory(0, 0, 0))
                return
            elif target["name"] == "gc":
                call assembler.relative(output, [232], "runtime_gc")
                return
            elif target["name"] == "atomic_add" or target["name"] == "atomic_xchg":
                # Lock-free RMW over a bounds-checked IntArray slot; the result
                # is the previous slot value. Keep the array rooted while the
                # index/value expressions run, and only load its backing pointer
                # after all potentially allocating expressions have completed.
                if emit_validation_error(generator, syntax["arguments"][0], "atomic_target"):
                    return
                end
                if emit_validation_error(generator, syntax["arguments"][1], "atomic_index"):
                    return
                end
                if emit_validation_error(generator, syntax["arguments"][2], "atomic_value"):
                    return
                end
                call emit_expression(generator, syntax["arguments"][0])
                call assembler.emit(output, x86_64.push(0))
                if is_int_leaf(generator, syntax["arguments"][1]):
                    call emit_int_leaf(generator, syntax["arguments"][1], 6)
                else:
                    call emit_expression(generator, syntax["arguments"][1])
                    call assembler.emit(output, x86_64.move_reg_reg(6, 0))
                end
                call assembler.emit(output, x86_64.pop(7))
                call emit_bounds_check(generator, syntax, "IntArray", True)
                call assembler.emit(output, x86_64.push(7))
                call assembler.emit(output, x86_64.push(6))
                if is_int_leaf(generator, syntax["arguments"][2]):
                    call emit_int_leaf(generator, syntax["arguments"][2], 0)
                else:
                    call emit_expression(generator, syntax["arguments"][2])
                end
                call assembler.emit(output, x86_64.pop(6))
                call assembler.emit(output, x86_64.pop(7))
                call assembler.emit(output, x86_64.load_memory(10, 7, 24))
                if target["name"] == "atomic_add":
                    call assembler.emit(output, x86_64.lock_xadd_indexed(10, 6, 3, 0))
                else:
                    call assembler.emit(output, x86_64.lock_xchg_indexed(10, 6, 3, 0))
                end
                return
            elif target["name"] == "atomic_cas":
                # Compare-exchange: RAX holds the expected value and RCX the
                # desired one. The slot's previous value always ends up in RAX,
                # so the caller compares it with the expected value.
                if emit_validation_error(generator, syntax["arguments"][0], "cas_target"):
                    return
                end
                if emit_validation_error(generator, syntax["arguments"][1], "cas_index"):
                    return
                end
                if emit_validation_error(generator, syntax["arguments"][2], "cas_expected"):
                    return
                end
                if emit_validation_error(generator, syntax["arguments"][3], "cas_desired"):
                    return
                end
                call emit_expression(generator, syntax["arguments"][0])
                call assembler.emit(output, x86_64.push(0))
                if is_int_leaf(generator, syntax["arguments"][1]):
                    call emit_int_leaf(generator, syntax["arguments"][1], 6)
                else:
                    call emit_expression(generator, syntax["arguments"][1])
                    call assembler.emit(output, x86_64.move_reg_reg(6, 0))
                end
                call assembler.emit(output, x86_64.pop(7))
                call emit_bounds_check(generator, syntax, "IntArray", True)
                call assembler.emit(output, x86_64.push(7))
                call assembler.emit(output, x86_64.push(6))
                call emit_expression(generator, syntax["arguments"][2])
                call assembler.emit(output, x86_64.push(0))
                if is_int_leaf(generator, syntax["arguments"][3]):
                    call emit_int_leaf(generator, syntax["arguments"][3], 1)
                else:
                    call emit_expression(generator, syntax["arguments"][3])
                    call assembler.emit(output, x86_64.move_reg_reg(1, 0))
                end
                call assembler.emit(output, x86_64.pop(0))
                call assembler.emit(output, x86_64.pop(6))
                call assembler.emit(output, x86_64.pop(7))
                call assembler.emit(output, x86_64.load_memory(10, 7, 24))
                call assembler.emit(output, x86_64.lock_cmpxchg_indexed(10, 6, 3, 1))
                return
            elif target["name"] == "atomic_pause":
                call assembler.emit(output, x86_64.pause())
                call assembler.emit(output, x86_64.xor_reg_reg(0, 0))
                return
            elif target["name"] == "popcount" or target["name"] == "trailing_zeros":
                # Bit builtins over raw Int: popcnt / tzcnt on the value.
                if emit_validation_error(generator, syntax["arguments"][0], "integer_builtin"):
                    return
                end
                call emit_expression(generator, syntax["arguments"][0])
                if target["name"] == "popcount":
                    call assembler.emit(output, x86_64.popcount_reg(0, 0))
                else:
                    call assembler.emit(output, x86_64.trailing_zeros_reg(0, 0))
                end
                return
            elif target["name"] == "cpu_count":
                # Usable CPUs for this process (sched_getaffinity popcount).
                call assembler.relative(output, [232], "runtime_cpu_count")
                return
            elif target["name"] == "thread_spawn":
                # Spawn a shared-memory worker running the given Function.
                # Workers share globals; pass data through them. The builtin
                # returns the logical tid (or -1 when the table is full).
                spawn_type = semantic.infer_expression_type(syntax["arguments"][0], generator["types"], generator["function_returns"])
                if emit_validation_error(generator, syntax["arguments"][0], "thread_function"):
                    return
                end
                call emit_expression(generator, syntax["arguments"][0])
                call assembler.emit(output, x86_64.move_reg_reg(7, 0))
                if spawn_type == "Function":
                    call assembler.relative(output, [232], "runtime_box_dynamic_function")
                    call assembler.emit(output, x86_64.move_reg_reg(7, 0))
                end
                call assembler.relative(output, [232], "runtime_thread_spawn")
                return
            elif target["name"] == "thread_join":
                # Block until the worker with this logical tid exits.
                call emit_checked_int_expression(generator, syntax["arguments"][0], "thread_join tid")
                call assembler.emit(output, x86_64.move_reg_reg(7, 0))
                call assembler.relative(output, [232], "runtime_thread_join")
                return
            elif target["name"] == "__lsl_entry_source":
                # CLI předává pouze cestu skriptu; obsah .env se čte až za běhu.
                call emit_string_pointer(generator, generator["entry_source"])
                return
            elif target["name"] == "executable_path":
                call assembler.relative(output, [232], "runtime_executable_path")
                call emit_pending_error(generator)
                return
            elif target["name"] == "__lsl_getenv":
                call emit_expression(generator, syntax["arguments"][0])
                call assembler.emit(output, x86_64.move_reg_reg(7, 0))
                call assembler.relative(output, [232], "runtime_getenv")
                return
            elif target["name"] == "run" or target["name"] == "__lsl_run" or target["name"] == "run_clean" or target["name"] == "__lsl_run_clean" or target["name"] == "capture" or target["name"] == "__lsl_capture" or target["name"] == "capture_clean" or target["name"] == "__lsl_capture_clean" or target["name"] == "capture_stream" or target["name"] == "capture_stream_clean" or target["name"] == "capture_input" or target["name"] == "capture_input_clean" or target["name"] == "capture_input_stream" or target["name"] == "capture_input_stream_clean":
                call emit_expression(generator, checked_string_node(generator, syntax["arguments"][0]))
                call assembler.emit(output, x86_64.push(0))
                call emit_expression(generator, checked_list_node(generator, syntax["arguments"][1]))
                call assembler.emit(output, x86_64.push(0))
                if target["name"] == "capture_input_stream" or target["name"] == "capture_input_stream_clean":
                    call emit_expression(generator, checked_string_node(generator, syntax["arguments"][2]))
                    call assembler.emit(output, x86_64.push(0))
                    call emit_expression(generator, syntax["arguments"][3])
                    call emit_collection_box(generator, syntax["arguments"][3])
                    call assembler.emit(output, x86_64.move_reg_reg(2, 0))
                    call assembler.emit(output, x86_64.pop(1))
                elif target["name"] == "capture_stream" or target["name"] == "capture_stream_clean":
                    call emit_expression(generator, syntax["arguments"][2])
                    call emit_collection_box(generator, syntax["arguments"][2])
                    call assembler.emit(output, x86_64.move_reg_reg(2, 0))
                    call assembler.emit(output, x86_64.xor_reg_reg(1, 1))
                elif target["name"] == "capture_input" or target["name"] == "capture_input_clean":
                    call emit_expression(generator, checked_string_node(generator, syntax["arguments"][2]))
                    call assembler.emit(output, x86_64.move_reg_reg(1, 0))
                    call assembler.emit(output, x86_64.xor_reg_reg(2, 2))
                else:
                    call assembler.emit(output, x86_64.xor_reg_reg(2, 2))
                    call assembler.emit(output, x86_64.xor_reg_reg(1, 1))
                end
                call assembler.emit(output, x86_64.pop(6))
                call assembler.emit(output, x86_64.pop(7))
                if target["name"] == "run_clean" or target["name"] == "__lsl_run_clean" or target["name"] == "capture_clean" or target["name"] == "__lsl_capture_clean" or target["name"] == "capture_stream_clean" or target["name"] == "capture_input_clean" or target["name"] == "capture_input_stream_clean":
                    call assembler.emit(output, x86_64.mov_imm64(8, 1))
                else:
                    call assembler.emit(output, x86_64.xor_reg_reg(8, 8))
                end
                if target["name"] == "run" or target["name"] == "__lsl_run" or target["name"] == "run_clean" or target["name"] == "__lsl_run_clean":
                    call assembler.relative(output, [232], "runtime_run")
                else:
                    call assembler.relative(output, [232], "runtime_capture")
                    call emit_pending_error(generator)
                end
                return
            elif target["name"] == "native_open":
                call emit_expression(generator, checked_string_node(generator, syntax["arguments"][0]))
                call assembler.emit(output, x86_64.move_reg_reg(7, 0))
                call assembler.relative(output, [232], "runtime_native_open")
                return
            elif target["name"] == "native_size":
                call emit_expression(generator, syntax["arguments"][0])
                call assembler.emit(output, x86_64.move_reg_reg(7, 0))
                call assembler.relative(output, [232], "runtime_native_size")
                return
            elif target["name"] == "native_u64" or target["name"] == "native_function" or target["name"] == "native_call":
                call emit_expression(generator, syntax["arguments"][0])
                call assembler.emit(output, x86_64.push(0))
                call emit_expression(generator, syntax["arguments"][1])
                if target["name"] == "native_u64" or target["name"] == "native_function":
                    call assembler.emit(output, x86_64.move_reg_reg(7, 0))
                    call assembler.relative(output, [232], "runtime_unbox_dynamic_int")
                end
                call assembler.emit(output, x86_64.move_reg_reg(6, 0))
                call assembler.emit(output, x86_64.pop(7))
                if target["name"] == "native_u64":
                    call assembler.relative(output, [232], "runtime_native_u64")
                elif target["name"] == "native_function":
                    call assembler.relative(output, [232], "runtime_native_function")
                else:
                    call assembler.relative(output, [232], "runtime_native_call")
                    call emit_pending_error(generator)
                end
                return
            elif target["name"] == "native_name_equal":
                call emit_expression(generator, syntax["arguments"][0])
                call assembler.emit(output, x86_64.push(0))
                call emit_expression(generator, syntax["arguments"][1])
                call assembler.emit(output, x86_64.move_reg_reg(7, 0))
                call assembler.relative(output, [232], "runtime_unbox_dynamic_int")
                call assembler.emit(output, x86_64.push(0))
                call emit_expression(generator, syntax["arguments"][2])
                call assembler.emit(output, x86_64.move_reg_reg(2, 0))
                call assembler.emit(output, x86_64.pop(6))
                call assembler.emit(output, x86_64.pop(7))
                call assembler.relative(output, [232], "runtime_native_name_equal")
                return
            elif target["name"] == "native_close":
                call emit_expression(generator, syntax["arguments"][0])
                call assembler.emit(output, x86_64.move_reg_reg(7, 0))
                call assembler.relative(output, [232], "runtime_native_close")
                return
            elif target["name"] == "__lsl_fd_open":
                call emit_expression(generator, syntax["arguments"][0])
                call assembler.emit(output, x86_64.push(0))
                call emit_expression(generator, syntax["arguments"][1])
                call assembler.emit(output, x86_64.move_reg_reg(7, 0))
                call assembler.relative(output, [232], "runtime_unbox_dynamic_int")
                call assembler.emit(output, x86_64.move_reg_reg(6, 0))
                call assembler.emit(output, x86_64.pop(7))
                call assembler.relative(output, [232], "runtime_fd_open")
                return
            elif target["name"] == "__lsl_fd_socket":
                call emit_expression(generator, syntax["arguments"][0])
                call assembler.emit(output, x86_64.move_reg_reg(7, 0))
                call assembler.relative(output, [232], "runtime_unbox_dynamic_int")
                call assembler.emit(output, x86_64.push(0))
                call emit_expression(generator, syntax["arguments"][1])
                call assembler.emit(output, x86_64.move_reg_reg(7, 0))
                call assembler.relative(output, [232], "runtime_unbox_dynamic_int")
                call assembler.emit(output, x86_64.move_reg_reg(6, 0))
                call assembler.emit(output, x86_64.pop(7))
                call assembler.relative(output, [232], "runtime_fd_socket")
                return
            elif target["name"] == "__lsl_fd_read" or target["name"] == "__lsl_fd_write" or target["name"] == "__lsl_fd_connect" or target["name"] == "__lsl_fd_ioctl":
                call emit_expression(generator, syntax["arguments"][0])
                call assembler.emit(output, x86_64.move_reg_reg(7, 0))
                call assembler.relative(output, [232], "runtime_unbox_dynamic_int")
                call assembler.emit(output, x86_64.push(0))
                call emit_expression(generator, syntax["arguments"][1])
                call assembler.emit(output, x86_64.push(0))
                call emit_expression(generator, syntax["arguments"][2])
                call assembler.emit(output, x86_64.move_reg_reg(7, 0))
                call assembler.relative(output, [232], "runtime_unbox_dynamic_int")
                call assembler.emit(output, x86_64.move_reg_reg(2, 0))
                call assembler.emit(output, x86_64.pop(6))
                call assembler.emit(output, x86_64.pop(7))
                if target["name"] == "__lsl_fd_read":
                    call assembler.relative(output, [232], "runtime_fd_read")
                elif target["name"] == "__lsl_fd_connect":
                    call assembler.relative(output, [232], "runtime_fd_connect")
                elif target["name"] == "__lsl_fd_ioctl":
                    call assembler.relative(output, [232], "runtime_fd_ioctl")
                else:
                    call assembler.relative(output, [232], "runtime_fd_write")
                end
                return
            elif target["name"] == "__lsl_data_address":
                call emit_expression(generator, syntax["arguments"][0])
                call assembler.emit(output, x86_64.move_reg_reg(7, 0))
                call assembler.relative(output, [232], "runtime_data_address")
                return
            elif target["name"] == "__lsl_fd_mmap":
                call emit_expression(generator, syntax["arguments"][0])
                call assembler.emit(output, x86_64.move_reg_reg(7, 0))
                call assembler.relative(output, [232], "runtime_unbox_dynamic_int")
                call assembler.emit(output, x86_64.push(0))
                call emit_expression(generator, syntax["arguments"][1])
                call assembler.emit(output, x86_64.move_reg_reg(7, 0))
                call assembler.relative(output, [232], "runtime_unbox_dynamic_int")
                call assembler.emit(output, x86_64.push(0))
                call emit_expression(generator, syntax["arguments"][2])
                call assembler.emit(output, x86_64.move_reg_reg(7, 0))
                call assembler.relative(output, [232], "runtime_unbox_dynamic_int")
                call assembler.emit(output, x86_64.move_reg_reg(2, 0))
                call assembler.emit(output, x86_64.pop(6))
                call assembler.emit(output, x86_64.pop(7))
                call assembler.relative(output, [232], "runtime_fd_mmap")
                return
            elif target["name"] == "__lsl_fd_snapshot":
                call emit_expression(generator, syntax["arguments"][0])
                call assembler.emit(output, x86_64.move_reg_reg(7, 0))
                call assembler.relative(output, [232], "runtime_unbox_dynamic_int")
                call assembler.emit(output, x86_64.push(0))
                call emit_expression(generator, syntax["arguments"][1])
                call assembler.emit(output, x86_64.move_reg_reg(7, 0))
                call assembler.relative(output, [232], "runtime_unbox_dynamic_int")
                call assembler.emit(output, x86_64.push(0))
                call emit_expression(generator, syntax["arguments"][2])
                call assembler.emit(output, x86_64.move_reg_reg(7, 0))
                call assembler.relative(output, [232], "runtime_unbox_dynamic_int")
                call assembler.emit(output, x86_64.move_reg_reg(2, 0))
                call assembler.emit(output, x86_64.pop(6))
                call assembler.emit(output, x86_64.pop(7))
                call assembler.relative(output, [232], "runtime_fd_snapshot")
                return
            elif target["name"] == "__lsl_mem_pack":
                call emit_expression(generator, syntax["arguments"][0])
                call assembler.emit(output, x86_64.move_reg_reg(7, 0))
                call assembler.relative(output, [232], "runtime_unbox_dynamic_int")
                call assembler.emit(output, x86_64.push(0))
                call emit_expression(generator, syntax["arguments"][1])
                call assembler.emit(output, x86_64.push(0))
                call emit_expression(generator, syntax["arguments"][2])
                call assembler.emit(output, x86_64.move_reg_reg(7, 0))
                call assembler.relative(output, [232], "runtime_unbox_dynamic_int")
                call assembler.emit(output, x86_64.push(0))
                call emit_expression(generator, syntax["arguments"][3])
                call assembler.emit(output, x86_64.move_reg_reg(7, 0))
                call assembler.relative(output, [232], "runtime_unbox_dynamic_int")
                call assembler.emit(output, x86_64.push(0))
                call emit_expression(generator, syntax["arguments"][4])
                call assembler.emit(output, x86_64.move_reg_reg(7, 0))
                call assembler.relative(output, [232], "runtime_unbox_dynamic_int")
                call assembler.emit(output, x86_64.move_reg_reg(8, 0))
                call assembler.emit(output, x86_64.pop(1))
                call assembler.emit(output, x86_64.pop(2))
                call assembler.emit(output, x86_64.pop(6))
                call assembler.emit(output, x86_64.pop(7))
                call assembler.relative(output, [232], "runtime_mem_pack")
                return
            elif target["name"] == "__lsl_mem_unpack":
                call emit_expression(generator, syntax["arguments"][0])
                call assembler.emit(output, x86_64.push(0))
                call emit_expression(generator, syntax["arguments"][1])
                call assembler.emit(output, x86_64.move_reg_reg(7, 0))
                call assembler.relative(output, [232], "runtime_unbox_dynamic_int")
                call assembler.emit(output, x86_64.push(0))
                call emit_expression(generator, syntax["arguments"][2])
                call assembler.emit(output, x86_64.move_reg_reg(7, 0))
                call assembler.relative(output, [232], "runtime_unbox_dynamic_int")
                call assembler.emit(output, x86_64.push(0))
                call emit_expression(generator, syntax["arguments"][3])
                call assembler.emit(output, x86_64.move_reg_reg(7, 0))
                call assembler.relative(output, [232], "runtime_unbox_dynamic_int")
                call assembler.emit(output, x86_64.move_reg_reg(1, 0))
                call assembler.emit(output, x86_64.pop(2))
                call assembler.emit(output, x86_64.pop(6))
                call assembler.emit(output, x86_64.pop(7))
                call assembler.relative(output, [232], "runtime_mem_unpack")
                return
            elif target["name"] == "__lsl_text_byte":
                call emit_expression(generator, syntax["arguments"][0])
                call assembler.emit(output, x86_64.push(0))
                call emit_expression(generator, syntax["arguments"][1])
                call assembler.emit(output, x86_64.move_reg_reg(7, 0))
                call assembler.relative(output, [232], "runtime_unbox_dynamic_int")
                call assembler.emit(output, x86_64.move_reg_reg(6, 0))
                call assembler.emit(output, x86_64.pop(7))
                call assembler.relative(output, [232], "runtime_text_byte")
                return
            elif target["name"] == "__lsl_text_scan_digits" or target["name"] == "__lsl_text_split_byte":
                generator["lazy_used"]["__lsl_text_helpers"] = True
                call emit_expression(generator, syntax["arguments"][0])
                call assembler.emit(output, x86_64.push(0))
                call emit_expression(generator, syntax["arguments"][1])
                call assembler.emit(output, x86_64.move_reg_reg(7, 0))
                call assembler.relative(output, [232], "runtime_unbox_dynamic_int")
                call assembler.emit(output, x86_64.move_reg_reg(6, 0))
                call assembler.emit(output, x86_64.pop(7))
                if target["name"] == "__lsl_text_split_byte":
                    call assembler.relative(output, [232], "runtime_text_split_byte")
                else:
                    call assembler.relative(output, [232], "runtime_text_scan_digits")
                end
                return
            elif target["name"] == "__lsl_text_piece" or target["name"] == "__lsl_text_digits":
                generator["lazy_used"]["__lsl_text_helpers"] = True
                call emit_expression(generator, syntax["arguments"][0])
                call assembler.emit(output, x86_64.push(0))
                call emit_expression(generator, syntax["arguments"][1])
                call assembler.emit(output, x86_64.move_reg_reg(7, 0))
                call assembler.relative(output, [232], "runtime_unbox_dynamic_int")
                call assembler.emit(output, x86_64.push(0))
                call emit_expression(generator, syntax["arguments"][2])
                call assembler.emit(output, x86_64.move_reg_reg(7, 0))
                call assembler.relative(output, [232], "runtime_unbox_dynamic_int")
                call assembler.emit(output, x86_64.move_reg_reg(2, 0))
                call assembler.emit(output, x86_64.pop(6))
                call assembler.emit(output, x86_64.pop(7))
                if target["name"] == "__lsl_text_piece":
                    call assembler.relative(output, [232], "runtime_text_piece")
                else:
                    call assembler.relative(output, [232], "runtime_text_digits")
                end
                return
            elif target["name"] == "__lsl_text_from_bytes":
                call emit_expression(generator, syntax["arguments"][0])
                call assembler.emit(output, x86_64.push(0))
                call emit_expression(generator, syntax["arguments"][1])
                call assembler.emit(output, x86_64.move_reg_reg(7, 0))
                call assembler.relative(output, [232], "runtime_unbox_dynamic_int")
                call assembler.emit(output, x86_64.push(0))
                call emit_expression(generator, syntax["arguments"][2])
                call assembler.emit(output, x86_64.move_reg_reg(7, 0))
                call assembler.relative(output, [232], "runtime_unbox_dynamic_int")
                call assembler.emit(output, x86_64.move_reg_reg(2, 0))
                call assembler.emit(output, x86_64.pop(6))
                call assembler.emit(output, x86_64.pop(7))
                call assembler.relative(output, [232], "runtime_text_from_bytes")
                return
            elif target["name"] == "__lsl_syscall":
                call emit_expression(generator, syntax["arguments"][0])
                call assembler.emit(output, x86_64.move_reg_reg(7, 0))
                call assembler.relative(output, [232], "runtime_unbox_dynamic_int")
                call assembler.emit(output, x86_64.push(0))
                call emit_expression(generator, syntax["arguments"][1])
                call assembler.emit(output, x86_64.move_reg_reg(7, 0))
                call assembler.relative(output, [232], "runtime_unbox_dynamic_int")
                call assembler.emit(output, x86_64.push(0))
                call emit_expression(generator, syntax["arguments"][2])
                call assembler.emit(output, x86_64.move_reg_reg(7, 0))
                call assembler.relative(output, [232], "runtime_unbox_dynamic_int")
                call assembler.emit(output, x86_64.push(0))
                call emit_expression(generator, syntax["arguments"][3])
                call assembler.emit(output, x86_64.move_reg_reg(7, 0))
                call assembler.relative(output, [232], "runtime_unbox_dynamic_int")
                call assembler.emit(output, x86_64.push(0))
                call emit_expression(generator, syntax["arguments"][4])
                call assembler.emit(output, x86_64.move_reg_reg(7, 0))
                call assembler.relative(output, [232], "runtime_unbox_dynamic_int")
                call assembler.emit(output, x86_64.move_reg_reg(8, 0))
                call assembler.emit(output, x86_64.pop(1))
                call assembler.emit(output, x86_64.pop(2))
                call assembler.emit(output, x86_64.pop(6))
                call assembler.emit(output, x86_64.pop(7))
                call assembler.relative(output, [232], "runtime_syscall")
                return
            elif target["name"] == "__lsl_syscall6":
                # Evaluate right-to-left like a normal seven-argument call.
                # Six values land in the SysV registers and the final syscall
                # argument remains at stack[0] for runtime_syscall6.
                syscall_index = 6
                while syscall_index >= 0:
                    call emit_expression(generator, syntax["arguments"][syscall_index])
                    call assembler.emit(output, x86_64.move_reg_reg(7, 0))
                    call assembler.relative(output, [232], "runtime_unbox_dynamic_int")
                    if syscall_index == 0:
                        call assembler.emit(output, x86_64.move_reg_reg(7, 0))
                    else:
                        call assembler.emit(output, x86_64.push(0))
                    end
                    syscall_index -= 1
                end
                syscall_registers = abi_x86_64.ARGUMENT_REGISTERS
                syscall_index = 1
                while syscall_index < 6:
                    call assembler.emit(output, x86_64.pop(__lsl_typed_int(syscall_registers[syscall_index])))
                    syscall_index += 1
                end
                call assembler.relative(output, [232], "runtime_syscall6")
                call assembler.emit(output, x86_64.add_reg_imm8(4, 8))
                return
            elif target["name"] == "__lsl_fd_seek":
                call emit_expression(generator, syntax["arguments"][0])
                call assembler.emit(output, x86_64.move_reg_reg(7, 0))
                call assembler.relative(output, [232], "runtime_unbox_dynamic_int")
                call assembler.emit(output, x86_64.push(0))
                call emit_expression(generator, syntax["arguments"][1])
                call assembler.emit(output, x86_64.move_reg_reg(7, 0))
                call assembler.relative(output, [232], "runtime_unbox_dynamic_int")
                call assembler.emit(output, x86_64.move_reg_reg(6, 0))
                call assembler.emit(output, x86_64.pop(7))
                call assembler.relative(output, [232], "runtime_fd_seek")
                return
            elif target["name"] == "__lsl_fd_close":
                call emit_expression(generator, syntax["arguments"][0])
                call assembler.emit(output, x86_64.move_reg_reg(7, 0))
                call assembler.relative(output, [232], "runtime_unbox_dynamic_int")
                call assembler.emit(output, x86_64.move_reg_reg(7, 0))
                call assembler.relative(output, [232], "runtime_fd_close")
                return
            elif target["name"] == "capture_status":
                call assembler.relative(output, [232], "runtime_capture_status")
                return
            elif target["name"] == "capture_stderr":
                call assembler.relative(output, [232], "runtime_capture_stderr")
                return
            elif target["name"] == "input":
                generator["lazy_used"]["input"] = True
                call emit_expression(generator, checked_string_node(generator, syntax["arguments"][0]))
                call assembler.emit(output, x86_64.move_reg_reg(7, 0))
                call assembler.relative(output, [232], "runtime_input")
                call emit_pending_error(generator)
                return
            elif target["name"] == "clock":
                wall = {"kind": "call", "target": {"kind": "name", "name": "__lsl_wall_time"}, "arguments": [], "line": syntax["line"], "column": syntax["column"], "end_column": syntax["end_column"]}
                formatted = {"kind": "call", "target": {"kind": "name", "name": "__lsl_clock_text"}, "arguments": [wall], "line": syntax["line"], "column": syntax["column"], "end_column": syntax["end_column"]}
                call emit_expression(generator, formatted)
                return
            elif target["name"] == "monotonic" or target["name"] == "__lsl_monotonic" or target["name"] == "__lsl_wall_time":
                if target["name"] != "__lsl_wall_time":
                    call assembler.relative(output, [232], "runtime_clock")
                else:
                    call assembler.relative(output, [232], "runtime_wall_time")
                end
                return
            elif target["name"] == "__lsl_sleep":
                call emit_float_expression(generator, syntax["arguments"][0])
                call assembler.emit(output, x86_64.move_reg_reg(7, 0))
                call assembler.relative(output, [232], "runtime_sleep")
                call emit_pending_error(generator)
                return
            elif target["name"] == "__lsl_isatty":
                call emit_checked_int_expression(generator, syntax["arguments"][0], "file descriptor")
                call assembler.emit(output, x86_64.move_reg_reg(7, 0))
                call assembler.relative(output, [232], "runtime_isatty")
                return
            elif target["name"] == "__lsl_stdin_eof":
                call assembler.relative(output, [232], "runtime_stdin_eof")
                return
            elif target["name"] == "readfile" or target["name"] == "readbytes":
                call emit_expression(generator, checked_string_node(generator, syntax["arguments"][0]))
                call assembler.emit(output, x86_64.move_reg_reg(7, 0))
                if target["name"] == "readbytes":
                    call assembler.relative(output, [232], "runtime_readbytes")
                else:
                    call assembler.relative(output, [232], "runtime_readfile")
                end
                call runtime.thread_compare(generator["runtime"], output, runtime.ERROR_FLAG, 0)
                if generator["error_label"] != "":
                    call assembler.relative(output, [15, 133], generator["error_label"])
                else:
                    readfile_ok = label_name(generator, "readfile_ok")
                    call assembler.relative(output, [15, 132], readfile_ok)
                    call emit_uncaught_runtime_error(generator)
                    call assembler.label(output, readfile_ok)
                end
                return
            elif target["name"] == "writefile" or target["name"] == "appendfile" or target["name"] == "writebytes":
                call emit_expression(generator, checked_string_node(generator, syntax["arguments"][0]))
                call assembler.emit(output, x86_64.push(0))
                if target["name"] == "writebytes":
                    call emit_expression(generator, checked_byte_sequence_node(generator, syntax["arguments"][1]))
                else:
                    call emit_expression(generator, checked_string_node(generator, syntax["arguments"][1]))
                end
                call assembler.emit(output, x86_64.move_reg_reg(6, 0))
                call assembler.emit(output, x86_64.pop(7))
                if target["name"] == "writebytes":
                    if generator["internal_abi"] or generator.get("current_internal_function", False):
                        call assembler.relative(output, [232], "runtime_writebytes_raw")
                    else:
                        call assembler.relative(output, [232], "runtime_writebytes")
                    end
                elif target["name"] == "appendfile":
                    call assembler.relative(output, [232], "runtime_appendfile")
                else:
                    call assembler.relative(output, [232], "runtime_writefile")
                end
                call runtime.thread_compare(generator["runtime"], output, runtime.ERROR_FLAG, 0)
                if generator["error_label"] != "":
                    call assembler.relative(output, [15, 133], generator["error_label"])
                else:
                    write_ok = label_name(generator, "write_ok")
                    call assembler.relative(output, [15, 132], write_ok)
                    call emit_uncaught_runtime_error(generator)
                    call assembler.label(output, write_ok)
                end
                return
            elif target["name"] == "last_error":
                call runtime.thread_load(generator["runtime"], output, 0, runtime.ERROR)
                error_value_ready = label_name(generator, "error_value_ready")
                error_value_present = label_name(generator, "error_value_present")
                error_value_heap = label_name(generator, "error_value_heap")
                call assembler.emit(output, x86_64.cmp_reg_imm8(0, 0))
                call assembler.relative(output, [15, 133], error_value_present)
                call assembler.relative(output, [232], "runtime_box_none")
                call assembler.relative(output, [233], error_value_ready)
                call assembler.label(output, error_value_present)
                call assembler.emit(output, x86_64.move_reg_reg(7, 0))
                call assembler.relative(output, [232], "runtime_is_heap_object")
                call assembler.emit(output, x86_64.cmp_reg_imm8(0, 0))
                call assembler.relative(output, [15, 133], error_value_heap)
                call runtime.thread_load(generator["runtime"], output, 7, runtime.ERROR)
                call assembler.relative(output, [232], "runtime_string_clone")
                call runtime.thread_store(generator["runtime"], output, runtime.ERROR, 0)
                call assembler.label(output, error_value_heap)
                call runtime.thread_load(generator["runtime"], output, 0, runtime.ERROR)
                call assembler.label(output, error_value_ready)
                return
            elif target["name"] == "type":
                value_type = semantic.infer_expression_type(syntax["arguments"][0], generator["types"], generator["function_returns"])
                if value_type == "Any":
                    call emit_expression(generator, syntax["arguments"][0])
                    call assembler.emit(output, x86_64.move_reg_reg(7, 0))
                    call assembler.relative(output, [232], "function___lsl_type_name")
                    call emit_pending_error(generator)
                    return
                end
                if value_type.startswith("Class:"):
                    value_type = "Class"
                elif value_type.startswith("Instance:"):
                    value_type = "Instance"
                end
                call emit_string_pointer(generator, value_type)
                return
            elif target["name"] == "mkdir" or target["name"] == "__lsl_mkdir_private" or target["name"] == "unlink" or target["name"] == "rmdir":
                call emit_expression(generator, checked_string_node(generator, syntax["arguments"][0]))
                call assembler.emit(output, x86_64.move_reg_reg(7, 0))
                if target["name"] == "__lsl_mkdir_private":
                    call assembler.relative(output, [232], "runtime_mkdir_private")
                elif target["name"] == "mkdir":
                    call assembler.relative(output, [232], "runtime_mkdir")
                elif target["name"] == "rmdir":
                    call assembler.relative(output, [232], "runtime_rmdir")
                else:
                    call assembler.relative(output, [232], "runtime_unlink")
                end
                return
            elif target["name"] == "exists":
                call emit_expression(generator, checked_string_node(generator, syntax["arguments"][0]))
                call assembler.emit(output, x86_64.move_reg_reg(7, 0))
                call assembler.relative(output, [232], "runtime_exists")
                return
            elif target["name"] == "min" or target["name"] == "max":
                if len(syntax["arguments"]) == 1:
                    reducer = "__lsl_min"
                    if target["name"] == "max":
                        reducer = "__lsl_max"
                    end
                    reduce_call = {"kind": "call", "line": syntax["line"], "column": syntax["column"], "end_column": syntax["end_column"], "target": {"kind": "name", "name": reducer}, "arguments": syntax["arguments"]}
                    call emit_expression(generator, reduce_call)
                    return
                end
                if emit_validation_error(generator, syntax, "minmax_arity"):
                    return
                end
                minmax_left_type = semantic.infer_expression_type(syntax["arguments"][0], generator["types"], generator["function_returns"])
                minmax_right_type = semantic.infer_expression_type(syntax["arguments"][1], generator["types"], generator["function_returns"])
                if emit_validation_error(generator, syntax, "minmax_operands"):
                    return
                end
                minmax_dynamic = minmax_left_type == "Float" or minmax_right_type == "Float" or minmax_left_type == "Any" or minmax_right_type == "Any"
                call emit_expression(generator, syntax["arguments"][0])
                if minmax_dynamic:
                    call emit_dynamic_boundary_box(generator, syntax["arguments"][0])
                end
                call assembler.emit(output, x86_64.push(0))
                call emit_expression(generator, syntax["arguments"][1])
                if minmax_dynamic:
                    call emit_dynamic_boundary_box(generator, syntax["arguments"][1])
                end
                done_label = label_name(generator, "minmax_done")
                if minmax_dynamic:
                    # Dispatch Int/Float; keep the original boxed value.
                    call assembler.emit(output, x86_64.move_reg_reg(6, 0))
                    call assembler.emit(output, x86_64.pop(0))
                    call assembler.emit(output, x86_64.move_reg_reg(7, 0))
                    if (minmax_left_type == "Any" or minmax_right_type == "Any") and not generator["internal_abi"] and not generator.get("current_internal_function", False):
                        call emit_dynamic_numeric_pair_guard(generator, 0)
                    end
                    call assembler.emit(output, x86_64.move_reg_reg(0, 7))
                    call assembler.emit(output, x86_64.push(0))
                    call assembler.emit(output, x86_64.push(6))
                    call assembler.relative(output, [232], "runtime_compare_any")
                    call assembler.emit(output, x86_64.cmp_reg_imm8(0, 0))
                    call assembler.emit(output, x86_64.pop(1))
                    call assembler.emit(output, x86_64.pop(0))
                    if target["name"] == "min":
                        call assembler.relative(output, [15, 142], done_label)
                    else:
                        call assembler.relative(output, [15, 141], done_label)
                    end
                    call assembler.emit(output, x86_64.move_reg_reg(0, 1))
                    call assembler.label(output, done_label)
                    return
                end
                call assembler.emit(output, x86_64.move_reg_reg(1, 0))
                call assembler.emit(output, x86_64.pop(0))
                call assembler.emit(output, x86_64.cmp_reg_reg(0, 1))
                if target["name"] == "min":
                    call assembler.relative(output, [15, 142], done_label)
                else:
                    call assembler.relative(output, [15, 141], done_label)
                end
                call assembler.emit(output, x86_64.move_reg_reg(0, 1))
                call assembler.label(output, done_label)
                return
            elif target["name"] == "help":
                help_arguments = syntax["arguments"]
                if len(help_arguments) == 0:
                    help_arguments = [{"kind": "literal", "literal_kind": "string", "value": "", "line": syntax["line"], "column": syntax["column"], "end_column": syntax["end_column"]}]
                end
                help_call = {"kind": "call", "line": syntax["line"], "column": syntax["column"], "end_column": syntax["end_column"], "target": {"kind": "name", "name": "__lsl_help"}, "arguments": help_arguments}
                call emit_expression(generator, help_call)
                return
            elif target["name"] == "abs":
                abs_arg_type = semantic.infer_expression_type(syntax["arguments"][0], generator["types"], generator["function_returns"])
                if emit_validation_error(generator, syntax, "abs_operand"):
                    return
                end
                call emit_expression(generator, syntax["arguments"][0])
                if abs_arg_type == "Float":
                    # Clear the IEEE-754 sign bit of the boxed double and rebox.
                    call assembler.emit(output, x86_64.load_memory(7, 0, 8))
                    call assembler.emit(output, x86_64.mov_imm64(1, 9223372036854775807))
                    call assembler.emit(output, x86_64.and_reg_reg(7, 1))
                    call assembler.relative(output, [232], "runtime_float_new")
                elif abs_arg_type == "Any":
                    if not generator["internal_abi"] and not generator.get("current_internal_function", False):
                        call emit_dynamic_numeric_value_guard(generator, False)
                    end
                    call assembler.emit(output, x86_64.move_reg_reg(7, 0))
                    call assembler.relative(output, [232], dynamic_numeric_runtime(generator, "runtime_abs_any"))
                else:
                    done_label = label_name(generator, "abs_done")
                    call assembler.emit(output, x86_64.cmp_reg_imm8(0, 0))
                    call assembler.relative(output, [15, 141], done_label)
                    call assembler.emit(output, x86_64.neg_reg(0))
                    call assembler.label(output, done_label)
                end
                return
            elif target["name"] == "sqrt":
                if emit_validation_error(generator, syntax, "sqrt_operand"):
                    return
                end
                call emit_float_expression(generator, syntax["arguments"][0])
                # Float objects store the raw IEEE-754 bits at offset 8.
                call assembler.emit(output, x86_64.load_memory(7, 0, 8))
                call assembler.emit(output, x86_64.move_reg_reg(0, 7))
                call assembler.emit(output, x86_64.mov_imm64(1, 9223372036854775807))
                call assembler.emit(output, x86_64.and_reg_reg(0, 1))
                sqrt_ready = label_name(generator, "sqrt_ready")
                # Both +0.0 and -0.0 are valid. Every other negative input is a
                # domain error instead of silently producing a NaN.
                call assembler.emit(output, x86_64.cmp_reg_imm8(0, 0))
                call assembler.relative(output, [15, 132], sqrt_ready)
                call assembler.emit(output, x86_64.cmp_reg_imm8(7, 0))
                call assembler.relative(output, [15, 141], sqrt_ready)
                call emit_runtime_raise(generator, "ValueError: sqrt domain error")
                call assembler.label(output, sqrt_ready)
                call assembler.emit(output, x86_64.movq_xmm_from_reg(0, 7))
                call assembler.emit(output, x86_64.sqrt_double(0, 0))
                call assembler.emit(output, x86_64.movq_reg_from_xmm(7, 0))
                call assembler.relative(output, [232], "runtime_float_new")
                return
            elif target["name"] == "exit":
                call emit_checked_int_expression(generator, syntax["arguments"][0], "exit status")
                call assembler.emit(output, x86_64.move_reg_reg(7, 0))
                call runtime.release_input(generator["runtime"], output)
                call runtime.emit_exit(generator["runtime"], output)
                return
            end
        elif target["kind"] == "member":
            origin_call = target["target"]["kind"] == "name" and target["target"]["name"] == "origin"
            if origin_call:
                current_class = generator.get("current_class_name", "")
                parent_class = semantic.class_parent_name(generator["classes"], current_class)
                origin_method_name = semantic.resolve_method_name(generator["classes"], generator["functions"], parent_class, target["name"])
                if emit_validation_error(generator, syntax, "origin_method"):
                    return
                end
                origin_arguments = [{"kind": "name", "name": "self", "line": syntax["line"], "column": syntax["column"], "end_column": syntax["end_column"]}]
                origin_arguments.extend(syntax["arguments"])
                origin_target = {"kind": "name", "name": origin_method_name, "line": syntax["line"], "column": syntax["column"], "end_column": syntax["end_column"]}
                origin_expression = {"kind": "call", "line": syntax["line"], "column": syntax["column"], "end_column": syntax["end_column"], "target": origin_target, "arguments": origin_arguments}
                if "argument_names" in syntax:
                    origin_names = [""]
                    origin_names.extend(syntax["argument_names"])
                    origin_expression["argument_names"] = origin_names
                end
                call emit_expression(generator, origin_expression)
                return
            end
            receiver_type = semantic.infer_expression_type(target["target"], generator["types"], generator["function_returns"])
            if emit_validation_error(generator, syntax, "method_keywords"):
                return
            end
            if emit_validation_error(generator, syntax, "method_supported"):
                return
            end
            if emit_validation_error(generator, syntax, "method_arity"):
                return
            end
            if emit_validation_error(generator, syntax, "get_arity"):
                return
            end
            if emit_validation_error(generator, syntax, "setdefault_arity"):
                return
            end
            if emit_validation_error(generator, syntax, "pop_arity"):
                return
            end
            if target["name"] == "insert" or (target["name"] == "pop" and receiver_type != "Dictionary" and receiver_type != "Any" and len(syntax["arguments"]) == 1):
                if emit_validation_error(generator, syntax["arguments"][0], "method_index"):
                    return
                end
            end
            if (receiver_type == "Set" and target["name"] != "clear") or ((receiver_type == "Any") and (semantic.set_method(target["name"]) or target["name"] == "remove" or target["name"] == "update")):
                set_target = "__lsl_set_" + target["name"]
                if target["name"] == "copy":
                    set_target = "__lsl_set"
                elif receiver_type == "Any" and (target["name"] == "remove" or target["name"] == "update"):
                    set_target = "__lsl_collection_" + target["name"]
                end
                set_arguments = [target["target"]]
                set_arguments.extend(syntax["arguments"])
                call emit_expression(generator, {"kind": "call", "line": syntax["line"], "column": syntax["column"], "end_column": syntax["end_column"], "target": {"kind": "name", "name": set_target}, "arguments": set_arguments})
                return
            end
            if receiver_type.startswith("Class:") or receiver_type.startswith("Instance:"):
                if receiver_type.startswith("Class:"):
                    class_name = receiver_type[6:len(receiver_type)]
                else:
                    class_name = receiver_type[9:len(receiver_type)]
                end
                native_method_name = semantic.resolve_method_name(generator["classes"], generator["functions"], class_name, target["name"])
                if emit_validation_error(generator, syntax, "class_method"):
                    return
                end
                declaration = generator["functions"][native_method_name]
                combined_arguments = []
                if len(declaration["parameters"]) > 0:
                    if declaration["parameters"][0] == "self":
                        combined_arguments.append(target["target"])
                    end
                end
                combined_arguments.extend(syntax["arguments"])
                combined_call = {"kind": "call", "line": syntax["line"], "column": syntax["column"], "end_column": syntax["end_column"], "target": {"kind": "name", "name": native_method_name}, "arguments": combined_arguments}
                if "argument_names" in syntax:
                    combined_names = []
                    if len(combined_arguments) > len(syntax["arguments"]):
                        combined_names.append("")
                    end
                    combined_names.extend(syntax["argument_names"])
                    combined_call["argument_names"] = combined_names
                end
                call emit_expression(generator, combined_call)
                return
            elif emit_validation_error(generator, syntax, "typed_array_method"):
                return
            elif target["name"] == "append":
                if emit_validation_error(generator, syntax, "fixed_append"):
                    return
                end
                if receiver_type == "IntArray":
                    if emit_validation_error(generator, syntax["arguments"][0], "intarray_append"):
                        return
                    end
                elif receiver_type == "FloatArray":
                    if emit_validation_error(generator, syntax["arguments"][0], "floatarray_append"):
                        return
                    end
                elif receiver_type == "ByteArray":
                    if emit_validation_error(generator, syntax["arguments"][0], "bytearray_append"):
                        return
                    end
                end
                call emit_expression(generator, target["target"])
                call assembler.emit(output, x86_64.push(0))
                call emit_expression(generator, syntax["arguments"][0])
                if receiver_type == "FloatArray":
                    call assembler.emit(output, x86_64.load_memory(0, 0, 8))
                elif receiver_type == "ByteArray":
                    byte_append_ok = label_name(generator, "byte_append_ok")
                    byte_append_error = label_name(generator, "byte_append_error")
                    call assembler.emit(output, x86_64.cmp_reg_imm8(0, 0))
                    call assembler.relative(output, [15, 140], byte_append_error)
                    call assembler.emit(output, x86_64.cmp_reg_imm32(0, 255))
                    call assembler.relative(output, [15, 142], byte_append_ok)
                    call assembler.label(output, byte_append_error)
                    call assembler.emit(output, x86_64.pop(7))
                    call emit_runtime_raise(generator, "ValueError: ByteArray value is outside 0..255")
                    call assembler.label(output, byte_append_ok)
                elif receiver_type != "IntArray":
                    call emit_collection_box(generator, syntax["arguments"][0])
                end
                call assembler.emit(output, x86_64.move_reg_reg(6, 0))
                call assembler.emit(output, x86_64.pop(7))
                if receiver_type == "ByteArray":
                    call assembler.relative(output, [232], "runtime_byte_array_append")
                elif receiver_type == "Any" and not generator["internal_abi"]:
                    call assembler.relative(output, [232], "runtime_dynamic_append")
                    call emit_pending_error(generator)
                else:
                    call assembler.relative(output, [232], "runtime_list_append")
                end
                return
            elif target["name"] == "clear":
                if emit_validation_error(generator, syntax, "fixed_clear"):
                    return
                elif receiver_type == "Dictionary":
                    clear_call = {"kind": "call", "line": syntax["line"], "column": syntax["column"], "end_column": syntax["end_column"], "target": {"kind": "name", "name": "__lsl_dict_clear"}, "arguments": [target["target"]]}
                    call emit_expression(generator, clear_call)
                else:
                    call emit_expression(generator, target["target"])
                    call assembler.emit(output, x86_64.move_reg_reg(7, 0))
                    if receiver_type == "Any" and not generator["internal_abi"]:
                        call assembler.relative(output, [232], "runtime_dynamic_clear")
                        call emit_pending_error(generator)
                    else:
                        call assembler.relative(output, [232], "runtime_list_clear")
                    end
                end
                return
            elif target["name"] == "pop":
                if emit_validation_error(generator, syntax, "fixed_pop"):
                    return
                end
                pop_target = "__lsl_pop"
                pop_arguments = [target["target"]]
                if receiver_type == "Any" and not generator["internal_abi"]:
                    pop_target = "__lsl_dynamic_pop" + String(len(syntax["arguments"]))
                    pop_arguments.extend(syntax["arguments"])
                elif receiver_type == "Dictionary":
                    if len(syntax["arguments"]) == 1:
                        pop_target = "__lsl_dict_pop"
                    else:
                        pop_target = "__lsl_dict_pop_default"
                    end
                    pop_arguments.extend(syntax["arguments"])
                elif len(syntax["arguments"]) == 1:
                    pop_target = "__lsl_pop_at"
                    pop_arguments.append(checked_index_node(generator, syntax["arguments"][0]))
                end
                pop_call = {"kind": "call", "line": syntax["line"], "column": syntax["column"], "end_column": syntax["end_column"], "target": {"kind": "name", "name": pop_target}, "arguments": pop_arguments}
                call emit_expression(generator, pop_call)
                return
            elif target["name"] == "keys":
                call emit_expression(generator, target["target"])
                call assembler.emit(output, x86_64.move_reg_reg(7, 0))
                if receiver_type == "Any" and not generator["internal_abi"]:
                    call assembler.relative(output, [232], "runtime_dynamic_dict_keys")
                    call emit_pending_error(generator)
                else:
                    call assembler.relative(output, [232], "runtime_dict_keys")
                end
                return
            else:
                method_target = semantic.method_function(target["name"])
                method_receiver = target["target"]
                if receiver_type == "Any" and not generator["internal_abi"]:
                    receiver_guard = ""
                    if target["name"] == "count":
                        method_target = "__lsl_dynamic_count"
                    elif target["name"] == "index":
                        method_target = "__lsl_dynamic_index"
                    elif target["name"] == "find":
                        method_target = "__lsl_dynamic_find"
                    elif target["name"] == "copy":
                        method_target = "__lsl_dynamic_copy"
                    elif target["name"] == "extend" or target["name"] == "insert" or target["name"] == "remove" or target["name"] == "sort" or target["name"] == "reverse":
                        receiver_guard = "__lsl_require_list"
                    elif target["name"] == "get" or target["name"] == "setdefault" or target["name"] == "update" or target["name"] == "values" or target["name"] == "items":
                        receiver_guard = "__lsl_require_dictionary"
                    else:
                        receiver_guard = "__lsl_require_string"
                    end
                    if receiver_guard != "":
                        method_receiver = {"kind": "call", "line": syntax["line"], "column": syntax["column"], "end_column": syntax["end_column"], "target": {"kind": "name", "name": receiver_guard}, "arguments": [target["target"]]}
                    end
                end
                if receiver_type == "Tuple" or receiver_type == "RealArray":
                    if emit_validation_error(generator, syntax, "fixed_mutation"):
                        return
                    end
                end
                if receiver_type == "List" or receiver_type == "Tuple" or receiver_type == "RealArray" or receiver_type == "IntArray" or receiver_type == "FloatArray":
                    if target["name"] == "index":
                        method_target = "__lsl_list_index"
                    elif target["name"] == "count":
                        method_target = "__lsl_list_count"
                    elif target["name"] == "find":
                        method_target = "__lsl_list_find"
                    end
                elif receiver_type == "String" and target["name"] == "index":
                    method_target = "__lsl_string_index"
                elif receiver_type == "Dictionary" and target["name"] == "copy":
                    method_target = "__lsl_dict_copy"
                end
                if method_target != "":
                    combined_arguments = [method_receiver]
                    if target["name"] == "insert":
                        combined_arguments.append(checked_index_node(generator, syntax["arguments"][0]))
                        combined_arguments.append(syntax["arguments"][1])
                    else:
                        combined_arguments.extend(syntax["arguments"])
                    end
                    if target["name"] == "get" and len(syntax["arguments"]) == 1:
                        combined_arguments.append({"kind": "literal", "literal_kind": "name", "value": "None", "line": syntax["line"], "column": syntax["column"], "end_column": syntax["end_column"]})
                    end
                    for argument in combined_arguments:
                        call emit_expression(generator, argument)
                        call emit_collection_box(generator, argument)
                        call assembler.emit(output, x86_64.push(0))
                    end
                    method_registers = abi_x86_64.ARGUMENT_REGISTERS
                    method_index = len(combined_arguments) - 1
                    while method_index >= 0:
                        call assembler.emit(output, x86_64.pop(__lsl_typed_int(method_registers[method_index])))
                        method_index -= 1
                    end
                    if lazy_runtime(method_target):
                        generator["lazy_used"][method_target] = True
                    end
                    call assembler.relative(output, [232], "function_" + method_target)
                    call emit_pending_error(generator)
                    if target["name"] == "copy":
                        if receiver_type == "Tuple":
                            call assembler.emit(output, x86_64.store_memory_imm32(0, abi_x86_64.OBJECT_TAG, value_abi.TAG_TUPLE))
                        elif receiver_type == "RealArray":
                            call assembler.emit(output, x86_64.store_memory_imm32(0, abi_x86_64.OBJECT_TAG, value_abi.TAG_REAL_ARRAY))
                        end
                    end
                    return
                end
            end
        end
        if emit_validation_error(generator, syntax, "call_target"):
            return
        end
        if target["name"] in generator["classes"]:
            class_name = target["name"]
            arguments = syntax["arguments"]
            call assembler.relative(output, [232], "runtime_dict_new")
            call assembler.emit(output, x86_64.push(0))
            initializer_name = semantic.resolve_method_name(generator["classes"], generator["functions"], class_name, "init")
            if emit_validation_error(generator, syntax, "constructor_keywords"):
                return
            end
            if initializer_name != "":
                initializer = generator["functions"][initializer_name]
                arguments = bind_arguments(generator, syntax, initializer, 1)
                if arguments == None:
                    return
                end
                if emit_validation_error(generator, syntax, "constructor_arity"):
                    return
                end
                index = len(arguments) - 1
                while index >= 0:
                    call emit_expression(generator, arguments[index])
                    call emit_collection_box(generator, arguments[index])
                    call assembler.emit(output, x86_64.push(0))
                    index -= 1
                end
                call assembler.emit(output, x86_64.load_memory(0, 4, len(arguments) * 8))
                call assembler.emit(output, x86_64.push(0))
                argument_registers = abi_x86_64.ARGUMENT_REGISTERS
                total_arguments = len(arguments) + 1
                register_count = min(total_arguments, len(argument_registers))
                index = 0
                while index < register_count:
                    call assembler.emit(output, x86_64.pop(__lsl_typed_int(argument_registers[index])))
                    index += 1
                end
                call assembler.relative(output, [232], "function_" + initializer_name)
                stack_count = total_arguments - register_count
                if stack_count > 0:
                    call assembler.emit(output, x86_64.add_reg_imm32(4, stack_count * abi_x86_64.WORD_BYTES))
                end
                call runtime.thread_compare(generator["runtime"], output, runtime.ERROR_FLAG, 0)
                if generator["error_label"] != "":
                    call assembler.relative(output, [15, 133], generator["error_label"])
                else:
                    initializer_ok = label_name(generator, "initializer_ok")
                    call assembler.relative(output, [15, 132], initializer_ok)
                    call emit_uncaught_runtime_error(generator)
                    call assembler.label(output, initializer_ok)
                end
            end
            call assembler.emit(output, x86_64.pop(0))
            return
        end
        indirect_call = False
        if target["name"] not in generator["functions"]:
            if target["name"] in generator["variables"] or target["name"] in generator["global_variables"]:
                indirect_call = True
            elif target["name"] == "rang" or target["name"] == "range":
                # rang(...) outside a for iterable is an ordinary value: build
                # the List at run time. Loops keep their allocation-free path.
                count = len(syntax["arguments"])
                if emit_validation_error(generator, syntax, "rang_value_arity"):
                    return
                end
                zero = {"kind": "literal", "literal_kind": "number", "value": "0", "integer_value": 0, "line": syntax["line"], "column": syntax["column"], "end_column": syntax["end_column"]}
                one = {"kind": "literal", "literal_kind": "number", "value": "1", "integer_value": 1, "line": syntax["line"], "column": syntax["column"], "end_column": syntax["end_column"]}
                range_arguments = [zero, syntax["arguments"][0], one]
                if count >= 2:
                    range_arguments = [syntax["arguments"][0], syntax["arguments"][1], one]
                end
                if count == 3:
                    range_arguments[2] = syntax["arguments"][2]
                end
                range_call = {"kind": "call", "line": syntax["line"], "column": syntax["column"], "end_column": syntax["end_column"], "target": {"kind": "name", "name": "__lsl_rang_list", "line": syntax["line"], "column": syntax["column"], "end_column": syntax["end_column"]}, "arguments": range_arguments}
                call emit_expression(generator, range_call)
                return
            else:
                if generator["error_label"] != "":
                    call emit_validation_error(generator, syntax, "unknown_function")
                    return
                end
                Error(CompileError: "invalid analyzed program")
            end
        end
        arguments = syntax["arguments"]
        public_callee = False
        if not indirect_call:
            arguments = bind_arguments(generator, syntax, generator["functions"][target["name"]], 0)
            if arguments == None:
                return
            end
            if emit_validation_error(generator, syntax, "function_arity"):
                return
            end
            public_callee = not generator["functions"][target["name"]].get("internal_abi", False)
        elif emit_validation_error(generator, syntax, "indirect_keywords"):
            return
        end
        index = len(arguments) - 1
        while index >= 0:
            call emit_expression(generator, arguments[index])
            expected_parameter_type = "Any"
            if not indirect_call:
                expected_parameter_type = generator["function_parameters"][target["name"]][index]
            end
            if expected_parameter_type == "Any":
                call emit_direct_call_boundary_box(generator, arguments[index], public_callee)
            end
            # Arguments are evaluated from right to left. The first argument is
            # therefore evaluated last and can move straight from rax to rdi;
            # spilling and immediately restoring it cost two instructions at
            # every one-argument call in tight numeric loops.
            if index == 0:
                call assembler.emit(output, x86_64.move_reg_reg(7, 0))
            else:
                call assembler.emit(output, x86_64.push(0))
            end
            index -= 1
        end
        argument_registers = abi_x86_64.ARGUMENT_REGISTERS
        register_count = min(len(arguments), len(argument_registers))
        index = 1
        while index < register_count:
            call assembler.emit(output, x86_64.pop(__lsl_typed_int(argument_registers[index])))
            index += 1
        end
        if not indirect_call and (target["name"] == "__lsl_floordiv_dyn" or target["name"] == "__lsl_mod_dyn" or target["name"] == "__lsl_public_floordiv_dyn" or target["name"] == "__lsl_public_mod_dyn" or target["name"] == "__lsl_ffloordiv" or target["name"] == "__lsl_fmod") and not generator["internal_abi"] and not generator.get("current_internal_function", False):
            checked_floor_any = False
            for checked_floor_argument in arguments:
                if semantic.infer_expression_type(checked_floor_argument, generator["types"], generator["function_returns"]) == "Any":
                    checked_floor_any = True
                end
            end
            if checked_floor_any:
                call emit_dynamic_numeric_pair_guard(generator, 0)
            end
        end
        if indirect_call:
            call emit_load_local(generator, 0, target["name"])
            # Callable classification uses rdi and may clobber caller-saved
            # registers, so preserve the already loaded user arguments.
            index = 0
            while index < register_count:
                call assembler.emit(output, x86_64.push(__lsl_typed_int(argument_registers[index])))
                index += 1
            end
            call assembler.emit(output, x86_64.move_reg_reg(7, 0))
            call assembler.relative(output, [232], "runtime_unbox_dynamic_function")
            call assembler.emit(output, x86_64.move_reg_reg(11, 0))
            index = register_count - 1
            while index >= 0:
                call assembler.emit(output, x86_64.pop(__lsl_typed_int(argument_registers[index])))
                index -= 1
            end
            call assembler.emit(output, x86_64.call_reg(11))
        else:
            if lazy_runtime(target["name"]):
                generator["lazy_used"][target["name"]] = True
            end
            call assembler.relative(output, [232], "function_" + target["name"])
        end
        stack_count = len(arguments) - register_count
        if stack_count > 0:
            call assembler.emit(output, x86_64.add_reg_imm32(4, stack_count * abi_x86_64.WORD_BYTES))
        end
        call runtime.thread_compare(generator["runtime"], output, runtime.ERROR_FLAG, 0)
        if generator["error_label"] != "":
            call assembler.relative(output, [15, 133], generator["error_label"])
        else:
            call_ok = label_name(generator, "call_ok")
            call assembler.relative(output, [15, 132], call_ok)
            call emit_uncaught_runtime_error(generator)
            call assembler.label(output, call_ok)
        end
        if indirect_call and not generator.get("current_internal_function", generator["internal_abi"]):
            call assembler.emit(output, x86_64.push(0))
            call emit_load_local(generator, 7, target["name"])
            call assembler.relative(output, [232], "runtime_function_return_tag")
            call assembler.emit(output, x86_64.move_reg_reg(10, 0))
            call assembler.emit(output, x86_64.pop(0))
            callback_return_done = label_name(generator, "callback_return_done")
            callback_return_bool = label_name(generator, "callback_return_bool")
            callback_return_none = label_name(generator, "callback_return_none")
            callback_return_function = label_name(generator, "callback_return_function")
            call assembler.emit(output, x86_64.cmp_reg_imm8(10, 0))
            call assembler.relative(output, [15, 132], callback_return_bool)
            call assembler.emit(output, x86_64.cmp_reg_imm8(10, 4))
            call assembler.relative(output, [15, 132], callback_return_bool)
            call assembler.emit(output, x86_64.cmp_reg_imm8(10, 5))
            call assembler.relative(output, [15, 132], callback_return_none)
            call assembler.emit(output, x86_64.cmp_reg_imm8(10, 10))
            call assembler.relative(output, [15, 132], callback_return_function)
            call assembler.relative(output, [233], callback_return_done)
            call assembler.label(output, callback_return_bool)
            # Tag 0 means Int; tag 4 means Bool.
            call assembler.emit(output, x86_64.cmp_reg_imm8(10, 4))
            callback_box_bool = label_name(generator, "callback_box_bool")
            call assembler.relative(output, [15, 132], callback_box_bool)
            call assembler.emit(output, x86_64.move_reg_reg(7, 0))
            call assembler.relative(output, [232], "runtime_box_int")
            call assembler.relative(output, [233], callback_return_done)
            call assembler.label(output, callback_box_bool)
            call assembler.emit(output, x86_64.move_reg_reg(7, 0))
            call assembler.relative(output, [232], "runtime_box_bool")
            call assembler.relative(output, [233], callback_return_done)
            call assembler.label(output, callback_return_none)
            call assembler.relative(output, [232], "runtime_box_none")
            call assembler.relative(output, [233], callback_return_done)
            call assembler.label(output, callback_return_function)
            call assembler.emit(output, x86_64.mov_imm64(6, -1))
            call assembler.emit(output, x86_64.move_reg_reg(7, 0))
            call assembler.relative(output, [232], "runtime_box_dynamic_function")
            call assembler.label(output, callback_return_done)
        end
    elif kind == "compare":
        if len(syntax["operators"]) > 1:
            chain_false = label_name(generator, "compare_chain_false")
            chain_end = label_name(generator, "compare_chain_end")
            chain_index = 0
            while chain_index < len(syntax["operators"]):
                pair = {"kind": "compare", "line": syntax["line"], "column": syntax["column"], "end_column": syntax["end_column"], "operators": [syntax["operators"][chain_index]], "operands": [syntax["operands"][chain_index], syntax["operands"][chain_index + 1]]}
                call emit_expression(generator, pair)
                call assembler.emit(output, x86_64.cmp_reg_imm8(0, 0))
                call assembler.relative(output, [15, 132], chain_false)
                chain_index += 1
            end
            call assembler.emit(output, x86_64.mov_imm64(0, 1))
            call assembler.relative(output, [233], chain_end)
            call assembler.label(output, chain_false)
            call assembler.emit(output, x86_64.mov_imm64(0, 0))
            call assembler.label(output, chain_end)
            return
        end
        left = syntax["operands"][0]
        right = syntax["operands"][1]
        operator = syntax["operators"][0]
        if operator == "in" or operator == "not in":
            container_type = semantic.infer_expression_type(right, generator["types"], generator["function_returns"])
            member_type = semantic.infer_expression_type(left, generator["types"], generator["function_returns"])
            if emit_validation_error(generator, right, "membership_target"):
                return
            elif emit_validation_error(generator, left, "membership_value"):
                return
            end
            if (container_type == "Any" and not generator["internal_abi"]) or container_type == "Set" or container_type == "IntArray" or container_type == "FloatArray" or container_type == "ByteArray" or (container_type == "String" and member_type == "Any" and not generator["internal_abi"]):
                contains_call = {"kind": "call", "line": syntax["line"], "column": syntax["column"], "end_column": syntax["end_column"], "target": {"kind": "name", "name": "__lsl_dynamic_contains"}, "arguments": [right, left]}
                call emit_expression(generator, contains_call)
            else:
                call emit_expression(generator, right)
                call assembler.emit(output, x86_64.push(0))
                call emit_expression(generator, left)
                if container_type == "Dictionary":
                    call emit_dictionary_key_box(generator, left)
                end
                call assembler.emit(output, x86_64.move_reg_reg(6, 0))
                call assembler.emit(output, x86_64.pop(7))
                if container_type == "String":
                    call assembler.relative(output, [232], "runtime_string_contains")
                else:
                    call assembler.relative(output, [232], "runtime_contains")
                end
            end
            if operator == "not in":
                call assembler.emit(output, x86_64.cmp_reg_imm8(0, 0))
                call assembler.emit(output, x86_64.set_condition(148))
            end
            return
        end
        opcode = comparison_opcode(operator)
        if emit_validation_error(generator, syntax, "comparison_operator"):
            return
        end
        left_type = semantic.infer_expression_type(left, generator["types"], generator["function_returns"])
        right_type = semantic.infer_expression_type(right, generator["types"], generator["function_returns"])
        if emit_validation_error(generator, syntax, "ordered_operands"):
            return
        end
        if left_type == "Float" or right_type == "Float":
            call emit_float_expression(generator, left)
            call assembler.emit(output, x86_64.push(0))
            call emit_float_expression(generator, right)
            call assembler.emit(output, x86_64.move_reg_reg(6, 0))
            call assembler.emit(output, x86_64.pop(7))
            call assembler.emit(output, x86_64.load_memory(0, 7, 8))
            call assembler.emit(output, x86_64.load_memory(1, 6, 8))
            call assembler.emit(output, x86_64.movq_xmm_from_reg(0, 0))
            call assembler.emit(output, x86_64.movq_xmm_from_reg(1, 1))
            call assembler.emit(output, x86_64.compare_double(0, 1))
            if operator == "==" or operator == "is":
                call assembler.emit(output, x86_64.set_condition_ordered(148))
            elif operator == "!=" or operator == "is not":
                call assembler.emit(output, x86_64.set_condition_unordered(149))
            elif operator == "<":
                call assembler.emit(output, x86_64.set_condition_ordered(146))
            elif operator == "<=":
                call assembler.emit(output, x86_64.set_condition_ordered(150))
            elif operator == ">":
                call assembler.emit(output, x86_64.set_condition(151))
            else:
                call assembler.emit(output, x86_64.set_condition(147))
            end
            return
        end
        if operator == "==" or operator == "!=" or operator == "is" or operator == "is not":
            left_equal_type = semantic.infer_expression_type(left, generator["types"], generator["function_returns"])
            right_equal_type = semantic.infer_expression_type(right, generator["types"], generator["function_returns"])
            use_deep = (operator == "==" or operator == "!=") and maybe_collection(left_equal_type) and maybe_collection(right_equal_type)
            if direct_scalar_equality(left_equal_type, right_equal_type):
                right_constant = semantic.constant_int_expression(right)
                if right_constant[0] and x86_64.fits_signed32(right_constant[1]):
                    call emit_expression(generator, left)
                    call assembler.emit(output, x86_64.cmp_reg_imm32(0, right_constant[1]))
                elif is_int_leaf(generator, right):
                    call emit_expression(generator, left)
                    call emit_int_leaf(generator, right, 6)
                    call assembler.emit(output, x86_64.cmp_reg_reg(0, 6))
                else:
                    call emit_expression(generator, left)
                    call assembler.emit(output, x86_64.push(0))
                    call emit_expression(generator, right)
                    call assembler.emit(output, x86_64.move_reg_reg(6, 0))
                    call assembler.emit(output, x86_64.pop(0))
                    call assembler.emit(output, x86_64.cmp_reg_reg(0, 6))
                end
                call assembler.emit(output, x86_64.set_condition(opcode))
            elif use_deep:
                # Deep equality for collections (recursive, element-wise). Scalar
                # pairs stay on the runtime_equal_any fast path below.
                equal_call = {"kind": "call", "line": syntax["line"], "column": syntax["column"], "end_column": syntax["end_column"], "target": {"kind": "name", "name": "__lsl_equal"}, "arguments": [left, right]}
                call emit_expression(generator, equal_call)
                if operator == "!=":
                    call assembler.emit(output, x86_64.cmp_reg_imm8(0, 0))
                    call assembler.emit(output, x86_64.set_condition(148))
                end
            else:
                call emit_expression(generator, left)
                call emit_dynamic_boundary_box(generator, left)
                call assembler.emit(output, x86_64.push(0))
                call emit_expression(generator, right)
                call emit_dynamic_boundary_box(generator, right)
                call assembler.emit(output, x86_64.move_reg_reg(6, 0))
                call assembler.emit(output, x86_64.pop(7))
                call assembler.relative(output, [232], "runtime_equal_any")
                if operator == "!=" or operator == "is not":
                    call assembler.emit(output, x86_64.cmp_reg_imm8(0, 0))
                    call assembler.emit(output, x86_64.set_condition(148))
                end
            end
        elif left_type == "Any" or right_type == "Any":
            # Operand may be a boxed Float at runtime; dispatch tagged Int/Float.
            call emit_expression(generator, left)
            call emit_dynamic_boundary_box(generator, left)
            call assembler.emit(output, x86_64.push(0))
            call emit_expression(generator, right)
            call emit_dynamic_boundary_box(generator, right)
            call assembler.emit(output, x86_64.move_reg_reg(6, 0))
            call assembler.emit(output, x86_64.pop(7))
            if not generator["internal_abi"] and not generator.get("current_internal_function", False):
                call emit_dynamic_numeric_pair_guard(generator, 0)
            end
            call assembler.relative(output, [232], "runtime_compare_any")
            call assembler.emit(output, x86_64.cmp_reg_imm8(0, 0))
            call assembler.emit(output, x86_64.set_condition(opcode))
        else:
            # Ordered comparison compiles directly against a constant when it
            # fits x86-64's sign-extended imm32 form; otherwise leaf operands
            # still avoid a stack spill.
            right_constant = semantic.constant_int_expression(right)
            if right_constant[0] and x86_64.fits_signed32(right_constant[1]):
                call emit_expression(generator, left)
                call assembler.emit(output, x86_64.cmp_reg_imm32(0, right_constant[1]))
                call assembler.emit(output, x86_64.set_condition(opcode))
                return
            elif is_int_leaf(generator, right):
                call emit_expression(generator, left)
                call emit_int_leaf(generator, right, 6)
            elif is_int_leaf(generator, left):
                call emit_expression(generator, right)
                call assembler.emit(output, x86_64.move_reg_reg(6, 0))
                call emit_int_leaf(generator, left, 0)
            else:
                call emit_expression(generator, left)
                call assembler.emit(output, x86_64.push(0))
                call emit_expression(generator, right)
                call assembler.emit(output, x86_64.move_reg_reg(6, 0))
                call assembler.emit(output, x86_64.pop(0))
            end
            call assembler.emit(output, x86_64.cmp_reg_reg(0, 6))
            call assembler.emit(output, x86_64.set_condition(opcode))
        end
    else:
        Error(CompileError: "invalid analyzed program")
    end
end

function emit_static_write_fd(generator, text, descriptor):
    # Stdout goes through the runtime buffer; anything else flushes it first
    # so stderr diagnostics keep their place relative to earlier prints.
    payload = bytes.utf8(text)
    output = generator["builder"]
    if descriptor != 1:
        call assembler.relative(output, [232], "runtime_stdout_flush")
        call runtime.prepare_static_write(generator["runtime"], output)
        call assembler.emit(output, x86_64.mov_imm64(7, descriptor))
    end
    lea_start = assembler.position(output)
    call assembler.emit(output, x86_64.lea_rip(6, 0))
    generator["relocations"].append([lea_start + 3, lea_start + 7, len(generator["data"])])
    call assembler.emit(output, x86_64.mov_imm64(2, len(payload)))
    if descriptor == 1:
        call assembler.relative(output, [232], "runtime_stdout_write")
    else:
        call runtime.emit_static_write(generator["runtime"], output)
    end
    call bytes.extend(generator["data"], payload)
end

function emit_static_write(generator, text):
    call emit_static_write_fd(generator, text, 1)
end

function emit_print_value(generator, expression):
    if expression["kind"] == "literal":
        if expression["literal_kind"] == "string" or expression["literal_kind"] == "name":
            call emit_static_write(generator, expression["value"])
            return
        end
    end
    if True:
        value_type = semantic.infer_expression_type(expression, generator["types"], generator["function_returns"])
        if value_type == "List" or value_type == "Tuple" or value_type == "RealArray" or value_type == "IntArray" or value_type == "FloatArray" or value_type == "ByteArray" or value_type == "Dictionary" or value_type == "Set" or value_type == "Function" or value_type == "Any":
            str_call = {"kind": "call", "line": expression["line"], "column": expression["column"], "end_column": expression["end_column"], "target": {"kind": "name", "name": "__lsl_str_value"}, "arguments": [expression]}
            call emit_expression(generator, str_call)
            call assembler.emit(generator["builder"], x86_64.move_reg_reg(7, 0))
            call assembler.relative(generator["builder"], [232], "runtime_print_string")
            return
        elif value_type == "Float":
            format_float_call = {"kind": "call", "line": expression["line"], "column": expression["column"], "end_column": expression["end_column"], "target": {"kind": "name", "name": "__lsl_format_float"}, "arguments": [expression]}
            call emit_expression(generator, format_float_call)
            call assembler.emit(generator["builder"], x86_64.move_reg_reg(7, 0))
            call assembler.relative(generator["builder"], [232], "runtime_print_string")
            call emit_gc_poll(generator)
            return
        end
        call emit_expression(generator, expression)
        if value_type == "String":
            call assembler.emit(generator["builder"], x86_64.move_reg_reg(7, 0))
            call assembler.relative(generator["builder"], [232], "runtime_print_string")
        elif value_type == "Float":
            call assembler.emit(generator["builder"], x86_64.move_reg_reg(7, 0))
            call assembler.relative(generator["builder"], [232], "runtime_print_float")
        elif value_type == "Bool":
            false_label = label_name(generator, "print_false")
            done_label = label_name(generator, "print_bool_done")
            call assembler.emit(generator["builder"], x86_64.cmp_reg_imm8(0, 0))
            call assembler.relative(generator["builder"], [15, 132], false_label)
            call emit_static_write(generator, "True")
            call assembler.relative(generator["builder"], [233], done_label)
            call assembler.label(generator["builder"], false_label)
            call emit_static_write(generator, "False")
            call assembler.label(generator["builder"], done_label)
        else:
            call assembler.relative(generator["builder"], [232], "runtime_print_int")
        end
    end
end

function expression_may_allocate(generator, syntax):
    # Conservative effect test: only omit a poll when the entire expression
    # is known not to allocate. Unknown calls and dynamic values stay covered.
    kind = syntax["kind"]
    if kind == "name":
        return False
    elif kind == "literal":
        value_type = semantic.infer_expression_type(syntax, generator["types"], generator["function_returns"])
        return value_type != "Int" and value_type != "Bool" and value_type != "None"
    elif kind == "unary":
        operand_type = semantic.infer_expression_type(syntax["operand"], generator["types"], generator["function_returns"])
        return (operand_type != "Int" and operand_type != "Bool") or expression_may_allocate(generator, syntax["operand"])
    elif kind == "binary":
        left_type = semantic.infer_expression_type(syntax["left"], generator["types"], generator["function_returns"])
        right_type = semantic.infer_expression_type(syntax["right"], generator["types"], generator["function_returns"])
        result_type = semantic.infer_expression_type(syntax, generator["types"], generator["function_returns"])
        if (left_type == "Int" or left_type == "Bool") and (right_type == "Int" or right_type == "Bool") and (result_type == "Int" or result_type == "Bool"):
            return expression_may_allocate(generator, syntax["left"]) or expression_may_allocate(generator, syntax["right"])
        end
    elif kind == "compare":
        for operand in syntax["operands"]:
            operand_type = semantic.infer_expression_type(operand, generator["types"], generator["function_returns"])
            if (operand_type != "Int" and operand_type != "Bool") or expression_may_allocate(generator, operand):
                return True
            end
        end
        return False
    elif kind == "index":
        target_type = semantic.infer_expression_type(syntax["target"], generator["types"], generator["function_returns"])
        index_type = semantic.infer_expression_type(syntax["index"], generator["types"], generator["function_returns"])
        if (target_type == "IntArray" or target_type == "ByteArray") and index_type == "Int":
            return expression_may_allocate(generator, syntax["target"]) or expression_may_allocate(generator, syntax["index"])
        end
    elif kind == "call" and syntax["target"]["kind"] == "name":
        name = syntax["target"]["name"]
        arguments = syntax["arguments"]
        if len(arguments) == 1:
            argument_type = semantic.infer_expression_type(arguments[0], generator["types"], generator["function_returns"])
            if (name == "Int" or name == "__lsl_declared_Int") and argument_type == "Int":
                return expression_may_allocate(generator, arguments[0])
            elif name == "__lsl_declared_Bool" and argument_type == "Bool":
                return expression_may_allocate(generator, arguments[0])
            elif name == "len" and argument_type != "Any":
                return expression_may_allocate(generator, arguments[0])
            end
        end
    end
    return True
end

function emit_gc_poll(generator):
    if generator["internal_abi"] or generator.get("current_internal_function", False) or generator.get("gc_unsafe", False):
        return
    end
    # The fast path is two loads, a compare and a normally taken branch.
    # No call, register spills or heap scan until the byte budget is reached.
    output = generator["builder"]
    done = label_name(generator, "gc_poll_done")
    call runtime.emit_gc_poll(generator["runtime"], output, done)
    call assembler.label(output, done)
end

function emit_statement_gc_poll(generator, statement):
    if generator["internal_abi"] or generator.get("current_internal_function", False) or generator.get("gc_unsafe", False):
        return
    end
    kind = statement["kind"]
    needed = False
    if kind == "assign":
        target = statement["target"]
        needed = expression_may_allocate(generator, statement["value"])
        if target["kind"] == "name":
            target_type = generator["types"].get(target["name"], "Any")
            needed = needed or (target_type != "Int" and target_type != "Bool")
        elif target["kind"] == "index":
            target_type = semantic.infer_expression_type(target["target"], generator["types"], generator["function_returns"])
            needed = needed or expression_may_allocate(generator, target) or (target_type != "IntArray" and target_type != "ByteArray")
        else:
            needed = True
        end
    elif kind == "expression":
        needed = expression_may_allocate(generator, statement["expression"])
    elif kind == "print":
        for expression in statement["expressions"]:
            value_type = semantic.infer_expression_type(expression, generator["types"], generator["function_returns"])
            needed = needed or expression_may_allocate(generator, expression) or (value_type != "Int" and value_type != "Bool" and value_type != "String")
        end
    elif kind == "return":
        expression = statement["expression"]
        needed = generator.get("current_return_type", "Any") == "Any"
        if expression != None:
            needed = needed or expression_may_allocate(generator, expression)
        end
    elif kind == "error" or kind == "delete" or kind == "class":
        needed = True
    elif kind == "for":
        needed = expression_may_allocate(generator, statement["iterable"])
    end
    if needed:
        call emit_gc_poll(generator)
    end
end

function error_reset_target(generator, target):
    if target == "":
        return ""
    end
    # Úspěšný odchod přes break/continue/return musí mít stejný stav jako end.
    reset = label_name(generator, "error_reset")
    generator["error_resets"].append([reset, target])
    return reset
end

function emit_statements(generator, statements, break_label, continue_label, return_label):
    for statement in statements:
        kind = statement["kind"]
        call emit_statement_gc_poll(generator, statement)
        if kind == "assign":
            target = statement["target"]
            if target["kind"] == "name":
                home = local_register(generator, target["name"])
                if statement["operator"] == "=":
                    value_syntax = statement["value"]
                    if value_syntax["kind"] == "call" and value_syntax["target"]["kind"] == "name" and value_syntax["target"]["name"].startswith("__lsl_declared_"):
                        inner = value_syntax["arguments"][0]
                        if semantic.infer_expression_type(inner, generator["types"], generator["function_returns"]) == generator["types"].get(target["name"], "Any"):
                            value_syntax = inner
                        end
                    end
                else:
                    operator = statement["operator"][0:len(statement["operator"]) - 1]
                    value_syntax = {"kind": "binary", "line": statement["line"], "column": statement["column"], "end_column": statement["end_column"], "operator": operator, "left": target, "right": statement["value"]}
                end
                if home >= 0 and generator.get("fast_intarray_name", "") == "" and value_syntax["kind"] != "literal" and value_syntax["kind"] != "name":
                    need = pure_int_need(generator, value_syntax)
                    if need >= 1 and need <= 6:
                        # Pure Int value straight into the register-resident
                        # local; rax is just another scratch register here.
                        # When the tree reads the local itself, build in rax
                        # first so the home is not clobbered mid-expression.
                        if pure_tree_reads_name(value_syntax, target["name"]):
                            call emit_pure_int_expression(generator, value_syntax, 0, pure_int_pool())
                            call assembler.emit(generator["builder"], x86_64.move_reg_reg(home, 0))
                        else:
                            pool = [0]
                            pool.extend(pure_int_pool())
                            call emit_pure_int_expression(generator, value_syntax, home, pool)
                        end
                        continue
                    end
                end
                if statement["operator"] == "=":
                    call emit_expression(generator, value_syntax)
                    if generator["types"].get(target["name"], "Any") == "Any" and not generator["internal_abi"]:
                        # Public Any locals use the same tagged representation
                        # as parameters, returns and collection slots. Keeping a
                        # raw scalar here made later dynamic dispatch ambiguous
                        # with a live heap address.
                        call emit_collection_box(generator, value_syntax)
                    elif semantic.infer_expression_type(value_syntax, generator["types"], generator["function_returns"]) == "Function":
                        call emit_collection_box(generator, value_syntax)
                    end
                else:
                    call emit_expression(generator, value_syntax)
                end
                call emit_store_local(generator, target["name"], 0, statement.get("init_flag", False))
            elif target["kind"] == "index":
                target_type = semantic.infer_expression_type(target["target"], generator["types"], generator["function_returns"])
                index_type = semantic.infer_expression_type(target["index"], generator["types"], generator["function_returns"])
                if emit_validation_error(generator, statement, "assignment_target"):
                    return
                elif emit_validation_error(generator, target["index"], "assignment_index"):
                    return
                end
                fast_value = statement["value"]
                if statement["operator"] != "=":
                    fast_operator = statement["operator"][0:len(statement["operator"]) - 1]
                    fast_value = {"kind": "binary", "line": statement["line"], "column": statement["column"], "end_column": statement["end_column"], "operator": fast_operator, "left": target, "right": statement["value"]}
                end
                if target_type == "IntArray" and generator.get("unchecked_intarray", False) and (is_fast_int_index(generator, target["index"]) or pure_int_need(generator, target["index"]) >= 1) and (is_fast_int_value(generator, fast_value) or pure_int_need(generator, fast_value) >= 1):
                    if emit_validation_error(generator, statement["value"], "fast_intarray_assignment"):
                        return
                    end
                    call emit_expression(generator, target["target"])
                    call assembler.emit(generator["builder"], x86_64.load_memory(10, 0, 24))
                    if is_int_leaf(generator, target["index"]):
                        call emit_int_leaf(generator, target["index"], 11)
                    else:
                        call emit_expression(generator, target["index"])
                        call assembler.emit(generator["builder"], x86_64.move_reg_reg(11, 0))
                    end
                    if statement["operator"] == "=":
                        call emit_expression(generator, fast_value)
                    else:
                        # The old augmented path expanded a[i] += value into a
                        # complete second a[i] load, including reloading both
                        # the array object and its data pointer. Reuse the
                        # address already held in r10/r11 and combine in place.
                        fast_operator = statement["operator"][0:len(statement["operator"]) - 1]
                        value_need = pure_int_need(generator, statement["value"])
                        if value_need >= 1 and value_need <= 5 and fast_operator != "*":
                            # Pure right-hand side: build it in rcx and combine
                            # with a memory-destination ALU op; no reload of
                            # the element into rax.
                            call emit_pure_int_expression(generator, statement["value"], 1, [2, 6, 7, 8, 9])
                            if fast_operator == "+":
                                call assembler.emit(generator["builder"], x86_64.alu_mem_indexed(1, 10, 11, 3, 1))
                            elif fast_operator == "-":
                                call assembler.emit(generator["builder"], x86_64.alu_mem_indexed(41, 10, 11, 3, 1))
                            elif fast_operator == "&":
                                call assembler.emit(generator["builder"], x86_64.alu_mem_indexed(33, 10, 11, 3, 1))
                            elif fast_operator == "|":
                                call assembler.emit(generator["builder"], x86_64.alu_mem_indexed(9, 10, 11, 3, 1))
                            else:
                                call assembler.emit(generator["builder"], x86_64.alu_mem_indexed(49, 10, 11, 3, 1))
                            end
                            continue
                        end
                        call assembler.emit(generator["builder"], x86_64.load_indexed(0, 10, 11, 3))
                        if is_int_leaf(generator, statement["value"]):
                            call emit_int_leaf(generator, statement["value"], 1)
                        else:
                            call assembler.emit(generator["builder"], x86_64.push(0))
                            call emit_expression(generator, statement["value"])
                            call assembler.emit(generator["builder"], x86_64.move_reg_reg(1, 0))
                            call assembler.emit(generator["builder"], x86_64.pop(0))
                        end
                        if fast_operator == "+":
                            call assembler.emit(generator["builder"], x86_64.add_reg_reg(0, 1))
                        elif fast_operator == "-":
                            call assembler.emit(generator["builder"], x86_64.sub_reg_reg(0, 1))
                        elif fast_operator == "*":
                            call assembler.emit(generator["builder"], x86_64.imul_reg_reg(0, 1))
                        elif fast_operator == "&":
                            call assembler.emit(generator["builder"], x86_64.and_reg_reg(0, 1))
                        elif fast_operator == "|":
                            call assembler.emit(generator["builder"], x86_64.or_reg_reg(0, 1))
                        else:
                            call assembler.emit(generator["builder"], x86_64.xor_reg_reg(0, 1))
                        end
                    end
                    call assembler.emit(generator["builder"], x86_64.store_indexed(10, 11, 3, 0))
                    continue
                end
                call emit_expression(generator, target["target"])
                call assembler.emit(generator["builder"], x86_64.push(0))
                call emit_expression(generator, target["index"])
                if target_type == "Dictionary" or (target_type == "Any" and not generator["internal_abi"]):
                    call emit_dictionary_key_box(generator, target["index"])
                elif index_type == "Any":
                    call assembler.emit(generator["builder"], x86_64.move_reg_reg(7, 0))
                    if not generator["internal_abi"] and not generator.get("current_internal_function", False):
                        call assembler.relative(generator["builder"], [232], "runtime_checked_index")
                        call emit_pending_error(generator)
                    else:
                        call assembler.relative(generator["builder"], [232], "runtime_unbox_dynamic_int")
                    end
                end
                call assembler.emit(generator["builder"], x86_64.push(0))
                if statement["operator"] == "=":
                    if emit_validation_error(generator, statement["value"], "intarray_assignment"):
                        return
                    elif emit_validation_error(generator, statement["value"], "floatarray_assignment"):
                        return
                    elif emit_validation_error(generator, statement["value"], "bytearray_assignment"):
                        return
                    end
                    call emit_expression(generator, statement["value"])
                    if target_type == "FloatArray":
                        call assembler.emit(generator["builder"], x86_64.load_memory(0, 0, 8))
                    elif target_type != "IntArray" and target_type != "ByteArray":
                        call emit_collection_box(generator, statement["value"])
                    end
                else:
                    operator = statement["operator"][0:len(statement["operator"]) - 1]
                    combined = {"kind": "binary", "line": statement["line"], "column": statement["column"], "end_column": statement["end_column"], "operator": operator, "left": target, "right": statement["value"]}
                    if emit_validation_error(generator, statement["value"], "intarray_augmented"):
                        return
                    elif emit_validation_error(generator, statement["value"], "floatarray_augmented"):
                        return
                    elif emit_validation_error(generator, statement["value"], "bytearray_augmented"):
                        return
                    end
                    call emit_expression(generator, combined)
                    if target_type == "FloatArray":
                        call assembler.emit(generator["builder"], x86_64.load_memory(0, 0, 8))
                    elif target_type != "IntArray" and target_type != "ByteArray":
                        call assembler.emit(generator["builder"], x86_64.move_reg_reg(7, 0))
                        call assembler.relative(generator["builder"], [232], "runtime_box_dynamic_int")
                    end
                end
                if target_type == "ByteArray":
                    byte_set_ok = label_name(generator, "byte_set_ok")
                    byte_set_error = label_name(generator, "byte_set_error")
                    call assembler.emit(generator["builder"], x86_64.cmp_reg_imm8(0, 0))
                    call assembler.relative(generator["builder"], [15, 140], byte_set_error)
                    call assembler.emit(generator["builder"], x86_64.cmp_reg_imm32(0, 255))
                    call assembler.relative(generator["builder"], [15, 142], byte_set_ok)
                    call assembler.label(generator["builder"], byte_set_error)
                    call assembler.emit(generator["builder"], x86_64.pop(6))
                    call assembler.emit(generator["builder"], x86_64.pop(7))
                    call emit_runtime_raise(generator, "ValueError: ByteArray value is outside 0..255")
                    call assembler.label(generator["builder"], byte_set_ok)
                end
                call assembler.emit(generator["builder"], x86_64.move_reg_reg(2, 0))
                call assembler.emit(generator["builder"], x86_64.pop(6))
                call assembler.emit(generator["builder"], x86_64.pop(7))
                if emit_validation_error(generator, statement, "tuple_assignment"):
                    return
                elif target_type == "Dictionary":
                    call assembler.relative(generator["builder"], [232], "runtime_dict_set")
                elif target_type == "List" or target_type == "RealArray" or target_type == "IntArray" or target_type == "FloatArray" or target_type == "ByteArray":
                    if target_type == "RealArray":
                        call assembler.emit(generator["builder"], x86_64.push(7))
                        call assembler.emit(generator["builder"], x86_64.push(6))
                        call assembler.emit(generator["builder"], x86_64.move_reg_reg(7, 2))
                        call assembler.relative(generator["builder"], [232], "function___lsl_require_real")
                        call runtime.thread_compare(generator["runtime"], generator["builder"], runtime.ERROR_FLAG, 0)
                        if generator["error_label"] != "":
                            call assembler.relative(generator["builder"], [15, 133], generator["error_label"])
                        else:
                            real_value_ok = label_name(generator, "real_value_ok")
                            call assembler.relative(generator["builder"], [15, 132], real_value_ok)
                            call emit_uncaught_runtime_error(generator)
                            call assembler.label(generator["builder"], real_value_ok)
                        end
                        call assembler.emit(generator["builder"], x86_64.move_reg_reg(2, 0))
                        call assembler.emit(generator["builder"], x86_64.pop(6))
                        call assembler.emit(generator["builder"], x86_64.pop(7))
                    end
                    call assembler.emit(generator["builder"], x86_64.push(2))
                    call emit_bounds_check(generator, statement, target_type, False)
                    call assembler.emit(generator["builder"], x86_64.pop(2))
                    if target_type == "ByteArray":
                        call assembler.relative(generator["builder"], [232], "runtime_byte_array_set")
                    elif target_type == "IntArray":
                        # rdi = array, rsi = normalized index, rdx = raw Int.
                        call assembler.emit(generator["builder"], x86_64.load_memory(0, 7, 24))
                        call assembler.emit(generator["builder"], x86_64.store_indexed(0, 6, 3, 2))
                        call assembler.emit(generator["builder"], x86_64.mov_imm64(0, 0))
                    else:
                        call assembler.relative(generator["builder"], [232], "runtime_list_set")
                    end
                else:
                    if target_type == "Any" and not generator["internal_abi"]:
                        call assembler.relative(generator["builder"], [232], "runtime_dynamic_set")
                        call emit_pending_error(generator)
                    else:
                        call assembler.relative(generator["builder"], [232], "runtime_set")
                    end
                end
            elif target["kind"] == "member":
                target_type = semantic.infer_expression_type(target["target"], generator["types"], generator["function_returns"])
                if emit_validation_error(generator, statement, "member_assignment"):
                    return
                end
                call emit_expression(generator, target["target"])
                call assembler.emit(generator["builder"], x86_64.push(0))
                call emit_string_pointer(generator, target["name"])
                call assembler.emit(generator["builder"], x86_64.push(0))
                if statement["operator"] == "=":
                    call emit_expression(generator, statement["value"])
                    call emit_collection_box(generator, statement["value"])
                else:
                    operator = statement["operator"][0:len(statement["operator"]) - 1]
                    combined = {"kind": "binary", "line": statement["line"], "column": statement["column"], "end_column": statement["end_column"], "operator": operator, "left": target, "right": statement["value"]}
                    call emit_expression(generator, combined)
                    call assembler.emit(generator["builder"], x86_64.move_reg_reg(7, 0))
                    call assembler.relative(generator["builder"], [232], "runtime_box_dynamic_int")
                end
                call assembler.emit(generator["builder"], x86_64.move_reg_reg(2, 0))
                call assembler.emit(generator["builder"], x86_64.pop(6))
                call assembler.emit(generator["builder"], x86_64.pop(7))
                call assembler.relative(generator["builder"], [232], "runtime_dict_set")
            else:
                Error(CompileError: "invalid analyzed program")
            end
        elif kind == "print":
            expressions = statement["expressions"]
            index = 0
            while index < len(expressions):
                if index > 0:
                    call emit_static_write(generator, " ")
                end
                call emit_print_value(generator, expressions[index])
                index += 1
            end
            call emit_static_write(generator, chr(10))
        elif kind == "expression":
            call emit_expression(generator, statement["expression"])
        elif kind == "if":
            selected = semantic.constant_if_body(statement)
            if selected[0]:
                call emit_statements(generator, selected[1], break_label, continue_label, return_label)
            else:
                end_label = label_name(generator, "if_end")
                branch_index = 0
                while branch_index < len(statement["branches"]):
                    next_label = label_name(generator, "if_next")
                    branch = statement["branches"][branch_index]
                    if not generator["internal_abi"] and expression_may_allocate(generator, branch[0]):
                        call emit_gc_poll(generator)
                    end
                    if not emit_branch_if_false(generator, branch[0], next_label):
                        call emit_condition(generator, branch[0])
                        call assembler.emit(generator["builder"], x86_64.cmp_reg_imm8(0, 0))
                        call assembler.relative(generator["builder"], [15, 132], next_label)
                    end
                    call emit_statements(generator, branch[1], break_label, continue_label, return_label)
                    call assembler.relative(generator["builder"], [233], end_label)
                    call assembler.label(generator["builder"], next_label)
                    branch_index += 1
                end
                call emit_statements(generator, statement["otherwise"], break_label, continue_label, return_label)
                call assembler.label(generator["builder"], end_label)
            end
        elif kind == "while" or kind == "loop":
            constant_condition = [False, False]
            if kind == "while":
                constant_condition = semantic.constant_truth_expression(statement["condition"])
            end
            if kind == "while" and constant_condition[0] and not constant_condition[1]:
                continue
            end
            start_label = label_name(generator, "loop_start")
            end_label = label_name(generator, "loop_end")
            call assembler.label(generator["builder"], start_label)
            if kind == "while" and not constant_condition[0]:
                if not generator["internal_abi"] and expression_may_allocate(generator, statement["condition"]):
                    call emit_gc_poll(generator)
                end
                if not emit_branch_if_false(generator, statement["condition"], end_label):
                    call emit_condition(generator, statement["condition"])
                    call assembler.emit(generator["builder"], x86_64.cmp_reg_imm8(0, 0))
                    call assembler.relative(generator["builder"], [15, 132], end_label)
                end
            end
            call emit_statements(generator, statement["body"], end_label, start_label, return_label)
            call assembler.relative(generator["builder"], [233], start_label)
            call assembler.label(generator["builder"], end_label)
        elif kind == "for":
            iterable = statement["iterable"]
            is_range_loop = False
            if iterable["kind"] == "call":
                if iterable["target"]["kind"] == "name":
                    if iterable["target"]["name"] == "rang" or iterable["target"]["name"] == "range":
                        is_range_loop = True
                    end
                end
            end
            if not is_range_loop:
                iterator_name = statement["iterator_name"]
                index_name = statement["index_name"]
                value_name = statement["name"]
                call emit_expression(generator, iterable)
                iterable_type = semantic.infer_expression_type(iterable, generator["types"], generator["function_returns"])
                if emit_validation_error(generator, iterable, "iterable"):
                    return
                end
                if iterable_type == "Dictionary":
                    call assembler.emit(generator["builder"], x86_64.move_reg_reg(7, 0))
                    call assembler.relative(generator["builder"], [232], "runtime_dict_keys")
                elif iterable_type == "Any":
                    iterator_not_dict = label_name(generator, "iterator_not_dict")
                    iterator_ready = label_name(generator, "iterator_ready")
                    call assembler.emit(generator["builder"], x86_64.push(0))
                    call assembler.emit(generator["builder"], x86_64.move_reg_reg(7, 0))
                    call assembler.relative(generator["builder"], [232], "runtime_type_code")
                    call assembler.emit(generator["builder"], x86_64.cmp_reg_imm8(0, 3))
                    call assembler.relative(generator["builder"], [15, 133], iterator_not_dict)
                    call assembler.emit(generator["builder"], x86_64.pop(7))
                    call assembler.relative(generator["builder"], [232], "runtime_dict_keys")
                    call assembler.relative(generator["builder"], [233], iterator_ready)
                    call assembler.label(generator["builder"], iterator_not_dict)
                    call assembler.emit(generator["builder"], x86_64.pop(0))
                    call assembler.label(generator["builder"], iterator_ready)
                end
                call emit_store_local(generator, iterator_name, 0)
                call assembler.emit(generator["builder"], x86_64.mov_imm64(0, 0))
                call emit_store_local(generator, index_name, 0)
                start_label = label_name(generator, "iter_start")
                continue_target = label_name(generator, "iter_continue")
                end_label = label_name(generator, "iter_end")
                call assembler.label(generator["builder"], start_label)
                if iterable_type == "Any" or iterable_type == "String" or iterable_type == "FloatArray" or generator["types"].get(value_name, "Any") == "Any":
                    call emit_gc_poll(generator)
                end
                call emit_load_local(generator, 7, iterator_name)
                if iterable_type == "Any" and not generator["internal_abi"]:
                    call assembler.relative(generator["builder"], [232], "runtime_dynamic_length")
                    call emit_pending_error(generator)
                else:
                    call assembler.relative(generator["builder"], [232], "runtime_length")
                end
                call assembler.emit(generator["builder"], x86_64.move_reg_reg(1, 0))
                call emit_load_local(generator, 0, index_name)
                call assembler.emit(generator["builder"], x86_64.cmp_reg_reg(0, 1))
                call assembler.relative(generator["builder"], [15, 141], end_label)
                if iterable_type == "Any" and not generator["internal_abi"]:
                    call emit_load_local(generator, 7, index_name)
                    call assembler.relative(generator["builder"], [232], "runtime_box_int")
                    call assembler.emit(generator["builder"], x86_64.move_reg_reg(6, 0))
                    call emit_load_local(generator, 7, iterator_name)
                else:
                    call emit_load_local(generator, 7, iterator_name)
                    call emit_load_local(generator, 6, index_name)
                end
                if iterable_type == "ByteArray":
                    call assembler.relative(generator["builder"], [232], "runtime_byte_array_get")
                elif iterable_type == "IntArray":
                    call assembler.emit(generator["builder"], x86_64.load_memory(0, 7, 24))
                    call assembler.emit(generator["builder"], x86_64.load_indexed(0, 0, 6, 3))
                elif iterable_type == "List" or iterable_type == "Tuple" or iterable_type == "RealArray" or iterable_type == "FloatArray" or iterable_type == "Set":
                    call assembler.relative(generator["builder"], [232], "runtime_list_get")
                    if iterable_type == "FloatArray":
                        call assembler.emit(generator["builder"], x86_64.move_reg_reg(7, 0))
                        call assembler.relative(generator["builder"], [232], "runtime_float_new")
                    end
                else:
                    if iterable_type == "Any" and not generator["internal_abi"]:
                        call assembler.relative(generator["builder"], [232], "runtime_iter_get")
                        call emit_pending_error(generator)
                    else:
                        call assembler.relative(generator["builder"], [232], "runtime_get")
                    end
                end
                if not generator["internal_abi"] and generator["types"].get(value_name, "Any") == "Any" and (iterable_type == "IntArray" or iterable_type == "ByteArray"):
                    call assembler.emit(generator["builder"], x86_64.move_reg_reg(7, 0))
                    call assembler.relative(generator["builder"], [232], "runtime_box_int")
                end
                call emit_store_local(generator, value_name, 0, statement.get("init_flag", False))
                call emit_statements(generator, statement["body"], end_label, continue_target, return_label)
                call assembler.label(generator["builder"], continue_target)
                call emit_load_local(generator, 0, index_name)
                call assembler.emit(generator["builder"], x86_64.increment(0))
                call emit_store_local(generator, index_name, 0)
                call assembler.relative(generator["builder"], [233], start_label)
                call assembler.label(generator["builder"], end_label)
                continue
            end
            arguments = iterable["arguments"]
            if emit_validation_error(generator, iterable, "rang_keywords"):
                return
            end
            if emit_validation_error(generator, statement, "rang_loop_arity"):
                return
            end
            if len(arguments) == 1:
                start_expression = {"kind": "literal", "literal_kind": "number", "value": "0", "integer_value": 0, "line": statement["line"], "column": statement["column"], "end_column": statement["end_column"]}
                stop_expression = arguments[0]
            else:
                start_expression = arguments[0]
                stop_expression = arguments[1]
            end
            loop_name = statement["name"]
            stop_name = statement["iterator_name"]
            step_name = statement["index_name"]
            dynamic_counter = not generator["internal_abi"] and generator["types"].get(loop_name, "Any") == "Any"
            call emit_checked_int_expression(generator, start_expression, "rang start")
            if dynamic_counter:
                call assembler.emit(generator["builder"], x86_64.move_reg_reg(7, 0))
                call assembler.relative(generator["builder"], [232], "runtime_box_int")
            end
            call emit_store_local(generator, loop_name, 0, statement.get("init_flag", False))
            call emit_checked_int_expression(generator, stop_expression, "rang stop")
            call emit_store_local(generator, stop_name, 0)
            explicit_step = len(arguments) == 3
            if explicit_step:
                step_syntax = arguments[2]
                step_type = semantic.infer_expression_type(step_syntax, generator["types"], generator["function_returns"])
                if emit_validation_error(generator, step_syntax, "rang_step"):
                    return
                end
                call emit_expression(generator, step_syntax)
                if step_type == "Any":
                    call assembler.emit(generator["builder"], x86_64.move_reg_reg(7, 0))
                    call assembler.relative(generator["builder"], [232], "function___lsl_require_rang_step")
                    call emit_pending_error(generator)
                end
                call emit_store_local(generator, step_name, 0)
            end
            if explicit_step:
                rang_step_ready = label_name(generator, "rang_step_ready")
                call emit_load_local(generator, 0, step_name)
                call assembler.emit(generator["builder"], x86_64.cmp_reg_imm8(0, 0))
                call assembler.relative(generator["builder"], [15, 133], rang_step_ready)
                rang_source_path = statement.get("path", generator["path"])
                call emit_runtime_raise(generator, "ValueError: rang step cannot be zero at " + rang_source_path + ":" + String(statement["line"]))
                call assembler.label(generator["builder"], rang_step_ready)
            end
            start_label = label_name(generator, "for_start")
            positive_check = label_name(generator, "for_positive_check")
            body_label = label_name(generator, "for_body")
            continue_target = label_name(generator, "for_continue")
            end_label = label_name(generator, "for_end")
            call assembler.label(generator["builder"], start_label)
            if dynamic_counter:
                call emit_gc_poll(generator)
            end
            call emit_load_local(generator, 0, loop_name)
            if dynamic_counter:
                call assembler.emit(generator["builder"], x86_64.move_reg_reg(7, 0))
                call assembler.relative(generator["builder"], [232], "function___lsl_require_rang_step")
                call emit_pending_error(generator)
            end
            call emit_load_local(generator, 1, stop_name)
            if explicit_step:
                call emit_load_local(generator, 2, step_name)
                call assembler.emit(generator["builder"], x86_64.cmp_reg_imm8(2, 0))
                call assembler.relative(generator["builder"], [15, 143], positive_check)
                call assembler.emit(generator["builder"], x86_64.cmp_reg_reg(0, 1))
                call assembler.relative(generator["builder"], [15, 142], end_label)
                call assembler.relative(generator["builder"], [233], body_label)
                call assembler.label(generator["builder"], positive_check)
            end
            call assembler.emit(generator["builder"], x86_64.cmp_reg_reg(0, 1))
            call assembler.relative(generator["builder"], [15, 141], end_label)
            call assembler.label(generator["builder"], body_label)
            call emit_statements(generator, statement["body"], end_label, continue_target, return_label)
            call assembler.label(generator["builder"], continue_target)
            call emit_load_local(generator, 0, loop_name)
            if dynamic_counter:
                call assembler.emit(generator["builder"], x86_64.move_reg_reg(7, 0))
                call assembler.relative(generator["builder"], [232], "function___lsl_require_rang_step")
                call emit_pending_error(generator)
            end
            if explicit_step:
                call emit_load_local(generator, 1, step_name)
                call assembler.emit(generator["builder"], x86_64.add_reg_reg(0, 1))
            else:
                call assembler.emit(generator["builder"], x86_64.increment(0))
            end
            if dynamic_counter:
                call assembler.emit(generator["builder"], x86_64.move_reg_reg(7, 0))
                call assembler.relative(generator["builder"], [232], "runtime_box_int")
            end
            call emit_store_local(generator, loop_name, 0)
            call assembler.relative(generator["builder"], [233], start_label)
            call assembler.label(generator["builder"], end_label)
        elif kind == "break":
            call assembler.relative(generator["builder"], [233], break_label)
        elif kind == "continue":
            call assembler.relative(generator["builder"], [233], continue_label)
        elif kind == "unsafe":
            old_gc_unsafe = generator.get("gc_unsafe", False)
            generator["gc_unsafe"] = True
            call emit_statements(generator, statement["body"], break_label, continue_label, return_label)
            generator["gc_unsafe"] = old_gc_unsafe
        elif kind == "safe":
            safe_end = label_name(generator, "safe_end")
            safe_failure = label_name(generator, "safe_failure")
            old_error_label = generator["error_label"]
            generator["error_label"] = safe_failure
            generator["error_handlers"].append([safe_failure, safe_end, generator["frame_size"]])
            call emit_statements(generator, statement["body"], error_reset_target(generator, break_label), error_reset_target(generator, continue_label), error_reset_target(generator, return_label))
            generator["error_label"] = old_error_label
            call runtime.thread_store_immediate(generator["runtime"], generator["builder"], runtime.ERROR, 0)
            call assembler.label(generator["builder"], safe_end)
            call runtime.thread_store_immediate(generator["runtime"], generator["builder"], runtime.ERROR_FLAG, 0)
        elif kind == "try":
            try_failure = label_name(generator, "try_failure")
            try_end = label_name(generator, "try_end")
            old_error_label = generator["error_label"]
            generator["error_label"] = try_failure
            call emit_statements(generator, statement["body"], error_reset_target(generator, break_label), error_reset_target(generator, continue_label), error_reset_target(generator, return_label))
            call runtime.thread_store_immediate(generator["runtime"], generator["builder"], runtime.ERROR, 0)
            call assembler.relative(generator["builder"], [233], try_end)
            call assembler.label(generator["builder"], try_failure)
            call assembler.emit(generator["builder"], x86_64.lea_base(4, 5, -generator["frame_size"]))
            call runtime.thread_store_immediate(generator["runtime"], generator["builder"], runtime.ERROR_FLAG, 0)
            generator["error_label"] = old_error_label
            call emit_statements(generator, statement["otherwise"], break_label, continue_label, return_label)
            call assembler.label(generator["builder"], try_end)
        elif kind == "error":
            error_message = statement["message"]
            error_prefix = statement["error_kind"] + ": "
            if error_message["kind"] == "literal":
                if error_message["literal_kind"] == "string":
                    call emit_string_pointer(generator, error_prefix + error_message["value"])
                else:
                    call emit_expression(generator, error_message)
                end
            elif error_message["kind"] == "name" and error_message["name"] not in generator["variables"] and error_message["name"] not in generator["global_variables"]:
                call emit_string_pointer(generator, error_prefix + error_message["name"])
            else:
                call emit_string_pointer(generator, error_prefix)
                call assembler.emit(generator["builder"], x86_64.push(0))
                call emit_expression(generator, error_message)
                call assembler.emit(generator["builder"], x86_64.move_reg_reg(6, 0))
                call assembler.emit(generator["builder"], x86_64.pop(7))
                call assembler.relative(generator["builder"], [232], "runtime_string_concat")
            end
            call runtime.thread_store(generator["runtime"], generator["builder"], runtime.ERROR, 0)
            call runtime.thread_store_immediate(generator["runtime"], generator["builder"], runtime.ERROR_FLAG, 1)
            if generator["error_label"] != "":
                call assembler.relative(generator["builder"], [233], generator["error_label"])
            else:
                call emit_uncaught_runtime_error(generator)
            end
        elif kind == "delete":
            target = statement["target"]
            if target["kind"] == "index":
                target_type = semantic.infer_expression_type(target["target"], generator["types"], generator["function_returns"])
                if emit_validation_error(generator, statement, "fixed_delete"):
                    return
                elif emit_validation_error(generator, statement, "bytearray_delete"):
                    return
                end
                if target_type == "List" or target_type == "IntArray" or target_type == "FloatArray":
                    delete_index = checked_index_node(generator, target["index"])
                    delete_call = {"kind": "call", "line": statement["line"], "column": statement["column"], "end_column": statement["end_column"], "target": {"kind": "name", "name": "__lsl_delete_at"}, "arguments": [target["target"], delete_index]}
                    call emit_expression(generator, delete_call)
                elif target_type == "Dictionary" or target_type == "Any":
                    call emit_expression(generator, target["target"])
                    call assembler.emit(generator["builder"], x86_64.push(0))
                    call emit_expression(generator, target["index"])
                    if target_type == "Any" and not generator["internal_abi"]:
                        call emit_dictionary_key_box(generator, target["index"])
                    end
                    call assembler.emit(generator["builder"], x86_64.move_reg_reg(6, 0))
                    call assembler.emit(generator["builder"], x86_64.pop(7))
                    if target_type == "Any" and not generator["internal_abi"]:
                        call assembler.relative(generator["builder"], [232], "runtime_dynamic_delete")
                        call emit_pending_error(generator)
                    else:
                        call assembler.relative(generator["builder"], [232], "runtime_dict_delete")
                        call emit_pending_error(generator)
                    end
                else:
                    if generator["error_label"] != "":
                        call emit_validation_error(generator, statement, "delete_target")
                        return
                    end
                    Error(CompileError: "invalid analyzed program")
                end
            elif target["kind"] == "name":
                call assembler.emit(generator["builder"], x86_64.mov_imm64(0, 0))
                if target["name"] in generator["variables"] or target["name"] in generator["global_variables"]:
                    call emit_store_local(generator, target["name"], 0)
                    if target["name"] not in generator["variables"]:
                        call assembler.emit(generator["builder"], x86_64.store_memory_imm32(3, generator["global_flags"][target["name"]], 0))
                    end
                else:
                    if generator["error_label"] != "":
                        call emit_validation_error(generator, statement, "delete_name")
                        return
                    end
                    Error(CompileError: "invalid analyzed program")
                end
            elif target["kind"] == "member":
                target_type = semantic.infer_expression_type(target["target"], generator["types"], generator["function_returns"])
                if emit_validation_error(generator, statement, "delete_member"):
                    return
                end
                call emit_expression(generator, target["target"])
                call assembler.emit(generator["builder"], x86_64.push(0))
                call emit_string_pointer(generator, target["name"])
                call assembler.emit(generator["builder"], x86_64.move_reg_reg(6, 0))
                call assembler.emit(generator["builder"], x86_64.pop(7))
                call assembler.relative(generator["builder"], [232], "runtime_dict_delete")
                call emit_pending_error(generator)
            else:
                Error(CompileError: "invalid analyzed program")
            end
        elif kind == "class":
            class_name_slot = statement["name"]
            call assembler.relative(generator["builder"], [232], "runtime_dict_new")
            call emit_store_local(generator, class_name_slot, 0, statement.get("init_flag", False))
            class_end = label_name(generator, "class_end")
            if statement["condition"] != None:
                call emit_expression(generator, statement["condition"])
                call emit_truth(generator)
                call assembler.emit(generator["builder"], x86_64.cmp_reg_imm8(0, 0))
                call assembler.relative(generator["builder"], [15, 132], class_end)
            end
            for member in statement["body"]:
                if member["kind"] == "assign":
                    call emit_load_local(generator, 0, class_name_slot)
                    call assembler.emit(generator["builder"], x86_64.push(0))
                    call emit_string_pointer(generator, member["target"]["name"])
                    call assembler.emit(generator["builder"], x86_64.push(0))
                    call emit_expression(generator, member["value"])
                    call assembler.emit(generator["builder"], x86_64.move_reg_reg(2, 0))
                    call assembler.emit(generator["builder"], x86_64.pop(6))
                    call assembler.emit(generator["builder"], x86_64.pop(7))
                    call assembler.relative(generator["builder"], [232], "runtime_dict_set")
                elif member["kind"] != "function" and member["kind"] != "ctype":
                    Error(CompileError: "invalid analyzed program")
                end
            end
            call assembler.label(generator["builder"], class_end)
        elif kind == "function":
            # Function bodies are emitted in the declaration pass.
            value = None
        elif kind == "load":
            Error(CompileError: "invalid analyzed program")
        elif kind == "return":
            dynamic_return = generator.get("current_return_type", "Any") == "Any"
            if statement["expression"] == None:
                if dynamic_return and not generator.get("current_internal_function", generator["internal_abi"]):
                    call assembler.relative(generator["builder"], [232], "runtime_box_none")
                else:
                    call assembler.emit(generator["builder"], x86_64.mov_imm64(0, 0))
                end
            else:
                call emit_expression(generator, statement["expression"])
                if not generator.get("current_internal_function", generator["internal_abi"]):
                    return_type = semantic.infer_expression_type(statement["expression"], generator["types"], generator["function_returns"])
                    if return_type == "Function" or (dynamic_return and (return_type == "Int" or return_type == "Bool" or return_type == "None")):
                        call emit_collection_box(generator, statement["expression"])
                    elif return_type == "Any" and statement["expression"]["kind"] == "binary":
                        call assembler.emit(generator["builder"], x86_64.move_reg_reg(7, 0))
                        call assembler.relative(generator["builder"], [232], "runtime_box_dynamic_int")
                    end
                end
            end
            call assembler.relative(generator["builder"], [233], return_label)
        else:
            Error(CompileError: "invalid analyzed program")
        end
        # No following statement in this block can execute after an
        # unconditional transfer. Avoid dead code and its literal data.
        if kind == "return" or kind == "break" or kind == "continue" or kind == "error":
            break
        end
    end
end

function aligned_frame(variables):
    return abi_x86_64.frame_bytes(len(variables))
end

function emit_function(generator, declaration):
    name = declaration["name"]
    generator["scope_name"] = name
    scope = generator["function_scopes"][name]
    variables = {}
    for local_name in scope["variables"].keys():
        variables[local_name] = abi_x86_64.local_offset(scope["variables"][local_name])
    end
    old_global_reads = generator.get("global_reads", {})
    generator["global_reads"] = scope["global_reads"]
    types = Dictionary(scope["types"])
    register_locals = choose_register_locals(declaration, variables, types)
    save_slots = {}
    for local_name in register_locals.keys():
        save_name = "@save_r@" + String(register_locals[local_name])
        if save_name not in variables:
            variables[save_name] = abi_x86_64.local_offset(len(variables) + 1)
        end
        save_slots[register_locals[local_name]] = variables[save_name]
    end
    old_register_locals = generator.get("register_locals", {})
    generator["register_locals"] = register_locals
    old_variables = generator["variables"]
    old_frame_size = generator["frame_size"]
    generator["frame_size"] = aligned_frame(variables)
    old_types = generator["types"]
    old_error_label = generator["error_label"]
    old_current_return_type = generator.get("current_return_type", "Any")
    old_internal_function = generator.get("current_internal_function", False)
    old_internal_abi = generator["internal_abi"]
    old_current_class_name = generator.get("current_class_name", "")
    generator["variables"] = variables
    generator["types"] = types
    generator["current_return_type"] = generator["function_returns"].get(name, "Any")
    generator["current_internal_function"] = declaration.get("internal_abi", False)
    if not generator["current_internal_function"]:
        generator["internal_abi"] = False
    end
    generator["current_class_name"] = declaration.get("class_name", "")
    # Keep hot loop/function entries off cross-cache-line boundaries. The
    # direct ELF backend has no external linker to provide normal text
    # alignment for us.
    while assembler.position(generator["builder"]) % abi_x86_64.FUNCTION_ALIGNMENT != 0:
        call assembler.emit(generator["builder"], [144])
    end
    call assembler.label(generator["builder"], "function_" + name)
    call assembler.emit(generator["builder"], x86_64.function_prologue(aligned_frame(variables)))
    # Callee-saved registers that hold locals are preserved in frame slots and
    # restored at the single return label.
    for saved_register in save_slots.keys():
        call assembler.emit(generator["builder"], x86_64.store_stack(save_slots[saved_register], saved_register))
    end
    argument_registers = abi_x86_64.ARGUMENT_REGISTERS
    index = 0
    while index < len(declaration["parameters"]):
        parameter = declaration["parameters"][index]
        if index < len(argument_registers):
            call emit_store_local(generator, parameter, __lsl_typed_int(argument_registers[index]))
        else:
            call assembler.emit(generator["builder"], x86_64.load_stack(0, abi_x86_64.incoming_argument_offset(index)))
            call emit_store_local(generator, parameter, 0)
        end
        index += 1
    end
    return_label = label_name(generator, "return_" + name)
    generator["error_label"] = return_label
    call emit_statements(generator, declaration["body"], "", "", return_label)
    call assembler.emit(generator["builder"], x86_64.mov_imm64(0, 0))
    call assembler.label(generator["builder"], return_label)
    for saved_register in save_slots.keys():
        call assembler.emit(generator["builder"], x86_64.load_stack(saved_register, save_slots[saved_register]))
    end
    call assembler.emit(generator["builder"], x86_64.function_epilogue())
    generator["register_locals"] = old_register_locals
    generator["variables"] = old_variables
    generator["frame_size"] = old_frame_size
    generator["types"] = old_types
    generator["error_label"] = old_error_label
    generator["current_return_type"] = old_current_return_type
    generator["current_internal_function"] = old_internal_function
    generator["internal_abi"] = old_internal_abi
    generator["current_class_name"] = old_current_class_name
    generator["global_reads"] = old_global_reads
end

# Runtime functions emitted only when a program uses help() or the CLI's
# about text; they carry the help catalog and library descriptions.
HELP_FAMILY = validation.HELP_FAMILY

function help_family(name):
    return name in HELP_FAMILY
end

# Runtime helpers emitted only when a program calls them, so ordinary
# binaries do not grow: rang(...) as a value and find on runtime receivers.
LAZY_RUNTIME = validation.LAZY_RUNTIME

function lazy_runtime(name):
    return name in LAZY_RUNTIME
end

function generate_object(unit, target, entry_source=""):
    if target.get("architecture", "") != "x86_64":
        Error(CompileError: "x86_64 backend cannot emit target " + String(target["name"]))
    end
    if not abi_x86_64.matches(target):
        Error(CompileError: "incompatible x86_64 ABI target descriptor")
    end
    if unit.get("validation_version", 0) != 1:
        Error(CompileError: "backend requires a validated frontend program")
    end
    selected_runtime = runtime.select(target)
    if unit.get("platform_module", "") != target["platform_module"]:
        Error(CompileError: "frontend platform does not match target runtime")
    end
    path = unit["path"]
    source = unit["source"]
    program = unit["program"]
    internal_abi = unit["internal_abi"]
    lines = source
    classes = unit["classes"]
    functions = unit["functions"]
    noreturn = unit["noreturn"]
    parameter_types = unit["function_parameters"]
    function_returns = unit["function_returns"]
    main_variables = unit["variables"]
    main_types = Dictionary(unit["types"])
    guarded_main_reads = unit["global_reads"]
    mutable_globals = unit["mutable_globals"]
    output = assembler.builder()
    unchecked_intarray = unit["unchecked_intarray"]
    # Umístění globálů určuje cílový runtime; adresování používá privátní LSL ABI.
    state_bytes = runtime.state_bytes(selected_runtime)
    global_offsets = {}
    for global_name in main_variables.keys():
        global_offsets[global_name] = abi_x86_64.global_offset(main_variables[global_name], state_bytes)
    end
    globals_bytes = aligned_frame(main_variables)
    global_flags = {}
    for global_name in main_variables.keys():
        global_flags[global_name] = global_offsets[global_name] + globals_bytes
    end
    globals_bytes *= 2
    generator = {"path": path, "entry_source": entry_source, "internal_abi": internal_abi, "unchecked_intarray": unchecked_intarray, "lines": lines, "variables": {}, "types": {}, "global_variables": global_offsets, "global_types": main_types, "functions": functions, "classes": classes, "function_returns": function_returns, "function_parameters": parameter_types, "builder": output, "data": ByteArray(), "string_offsets": {}, "relocations": [], "counter": 0, "error_label": "", "current_class_name": ""}
    generator["frame_size"] = 16
    generator["noreturn"] = noreturn
    generator["function_scopes"] = unit["function_scopes"]
    generator["validation_errors"] = unit["validation_errors"]
    generator["prepared_arguments"] = unit["prepared_arguments"]
    generator["scope_name"] = ""
    generator["error_handlers"] = []
    generator["error_resets"] = []
    generator["lazy_used"] = {}
    generator["global_reads"] = guarded_main_reads
    generator["mutable_globals"] = mutable_globals
    generator["global_flags"] = global_flags
    generator["global_handlers"] = []
    generator["runtime"] = selected_runtime
    registry_bytes = 524288
    registry_mask = 65535
    if generator["internal_abi"]:
        # The compiler allocates millions of short-lived objects; avoid repeated
        # rehash stages there. Normal programs start at 64K slots and grow.
        registry_bytes = 67108864
        registry_mask = 8388607
    end
    call runtime.emit_all(selected_runtime, output)

    # Compiler-host GC cadence. Every collection marks the whole live AST, so
    # its cost grows with the program while the garbage per emitted function
    # does not: a small program is fastest recycling memory every 32
    # functions, the self-host build (about 650 functions, ~150 ms per
    # collection) every 128. Scale the batch with the function count.
    gc_batch = 32
    if len(functions) // 5 > gc_batch:
        gc_batch = len(functions) // 5
    end
    emitted_functions = 0
    for statement in program:
        if statement["kind"] == "function":
            # Topic help and library descriptions are optional runtime data.
            # Do not grow every unrelated standalone program by embedding them.
            if not help_family(statement["name"]) and not lazy_runtime(statement["name"]):
                call emit_function(generator, statement)
                emitted_functions += 1
            end
        elif statement["kind"] == "class":
            for member in statement["body"]:
                if member["kind"] == "function":
                    call emit_function(generator, member)
                    emitted_functions += 1
                    if emitted_functions >= gc_batch:
                        call gc()
                        emitted_functions = 0
                    end
                end
            end
        end
        # Compiler-host GC, not an instruction in the compiled program.
        # A completed function has no half-built runtime buffers. Reclaim
        # emission temporaries in batches while keeping AST/builder roots.
        if emitted_functions >= gc_batch:
            call gc()
            emitted_functions = 0
        end
    end

    generator["scope_name"] = ""
    generator["variables"] = {}
    generator["types"] = main_types
    call assembler.label(output, "main")
    main_offset = assembler.position(output)
    call runtime.emit_entry(selected_runtime, output, globals_bytes, registry_bytes, registry_mask)
    call emit_statements(generator, program, "", "", "")
    call runtime.release_input(generator["runtime"], output)
    call runtime.emit_finish(selected_runtime, output)
    if generator.get("help_used", False):
        for name in HELP_FAMILY:
            call emit_function(generator, functions[name])
        end
    end
    for name in LAZY_RUNTIME:
        if name in generator["lazy_used"]:
            call emit_function(generator, functions[name])
        end
    end
    call runtime.emit_lazy(selected_runtime, output, "__lsl_text_helpers" in generator["lazy_used"], "input" in generator["lazy_used"])
    # Úklid rozpracovaných výrazů pouze při chybě, mimo úspěšnou cestu safe.
    for handler in generator["error_handlers"]:
        call assembler.label(output, handler[0])
        call assembler.emit(output, x86_64.lea_base(4, 5, -handler[2]))
        call assembler.relative(output, [233], handler[1])
    end
    for reset in generator["error_resets"]:
        call assembler.label(output, reset[0])
        call runtime.thread_store_immediate(generator["runtime"], output, runtime.ERROR, 0)
        call assembler.relative(output, [233], reset[1])
    end
    for handler in generator["global_handlers"]:
        call assembler.label(output, handler[0])
        generator["error_label"] = handler[2]
        call emit_source_raise(generator, handler[1], "NameError", "global variable '" + String(handler[1]["name"]).split("@")[-1] + "' read before assignment")
    end
    program_code = assembler.finish(output)
    relocations = []
    for relocation in generator["relocations"]:
        relocations.append(relocations_x86_64.data_reference(relocation[0], relocation[1], relocation[2]))
    end
    relocations.extend(output["image_relocations"])
    return object_code.program("x86_64", program_code, generator["data"], main_offset, relocations, {"target": target["name"], "abi": target["abi"], "runtime": selected_runtime}, output["symbols"], output["imports"])
end
