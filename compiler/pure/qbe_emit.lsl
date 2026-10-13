# AST -> LuxIR. Backend LuxIR sestaví SSA, optimalizuje, vybere instrukce
# a přidělí registry; jazyk IR popisuje doc/ir.md v projektu LuxIR.
load semantic
load validation

# Třídy hodnot (l, w, d, s) a jejich typy v LuxIR.
TYPE_NAMES = {"l":"Int64","w":"Int32","d":"Float64","s":"Float32"}

function line(s,text):
    s["lines"].append(text+chr(10))
end
# Typovaná definice hodnoty: Int64(jméno) = operace.
function define(s,name,operation,ty="l"):
    call line(s,"    "+TYPE_NAMES[ty]+"("+name+") = "+operation)
end
function temp(s,operation,ty="l"):
    s["counter"] += 1
    name = "t"+String(s["counter"])
    # Nejčastější třída l bez vyhledávání ve slovníku; jde o horkou cestu.
    if ty == "l":
        s["lines"].append("    Int64("+name+") = "+operation+chr(10))
    else:
        s["lines"].append("    "+TYPE_NAMES[ty]+"("+name+") = "+operation+chr(10))
    end
    return name
end
function label(s):
    s["label"] += 1
    return "b"+String(s["label"])
end
function jump_if(s,condition,yes,no):
    call line(s,"    if "+condition+" goto "+yes+" else "+no)
end
# Šířku uložení určuje typ hodnoty, i když je to konstanta.
function store(s,width,value,address):
    if width == "Int64":
        value = typed(value)
    else:
        value = width+"("+value+")"
    end
    call line(s,"    store("+value+", "+address+")")
end
# Konstanta v operandu začíná číslicí nebo znaménkem; jména ne.
function is_literal(text):
    first = __lsl_text_byte(text,0)
    return first == 45 or (first >= 48 and first <= 57)
end
# Typ stačí uvést jen u konstanty; jména mají vlastní třídu.
function typed(value,ty="Int64"):
    if is_literal(value):
        return ty+"("+value+")"
    end
    return value
end
function mark(s,name):
    call line(s,name+":")
    s["ended"] = False
    # A word condition is valid only in its defining basic block. At joins
    # the corresponding mutable local can have a different incoming value.
    if len(s["local_conditions"]) > 0:
        s["local_conditions"] = {}
    end
end
function jump(s,name):
    if not s["ended"]:
        call line(s,"    goto "+name)
        s["ended"] = True
    end
end
function error_check(s):
    flag = temp(s,"call qbe_error_flag()")
    next = label(s)
    call jump_if(s,flag,s["error"],next)
    call mark(s,next)
end
function invoke(s,name,args,ty="Any",checked=True):
    if s["runtime"]:
        # Runtime nevyhazuje výjimky LSL a sám nespouští GC: přímé volání.
        params = [typed(v) for v in args]
        return [temp(s,"call "+name+"("+", ".join(params)+")"),ty]
    end
    if name.startswith("fn"):
        s["callees"][name] = True
    elif name not in ["rt_runtime_maybe_gc","qbe_error_flag"]:
        # Conservatively include unchecked runtime calls too: only a body
        # made entirely of native instructions / proven LSL callees is pure.
        s["local_may_error"] = True
    end
    # Known LSL callees provide their own safepoints around their allocations.
    # A caller with only native instructions and direct LSL calls needs none:
    # even a loop/recursive cycle without a direct allocation cannot grow the
    # heap. Keep polls for runtime helpers and unknown indirect calls.
    # These error bridges only store/load TLS words; they cannot allocate.
    if name not in ["rt_runtime_maybe_gc","qbe_error_flag","qbe_error_set","qbe_error_clear","qbe_error_catch"] and not name.startswith("fn"):
        s["needs_gc_poll"] = True
        s["allocation_calls"] += 1
    end
    if name == "rt_runtime_maybe_gc":
        s["gc_poll_positions"].append(len(s["lines"]))
    end
    params = [typed(v) for v in args]
    value = temp(s,"call "+name+"("+", ".join(params)+")")
    if checked:
        if name.startswith("fn"):
            s["checked_calls"].append([len(s["lines"]),name])
        end
        call error_check(s)
    end
    return [value,ty]
end
function rt(s,name,args,ty="Any",checked=True):
    return invoke(s,"rt_runtime_"+name,args,ty,checked)
end
function finish_loop_poll(s,position,allocation_calls):
    # Count emitted allocation-capable calls in this loop (including nested
    # loops and conditions). Direct LSL callees already poll their own bodies.
    # Allocations outside the loop cannot increase its live allocation budget.
    if s["allocation_calls"] == allocation_calls:
        s["lines"][position] = ""
    end
end
function scalar(s,operation,ty="Int"):
    return [temp(s,operation),ty]
end
function string(s,text):
    strings = s["strings"]
    if text not in strings:
        strings[text] = len(strings)
    end
    if s["runtime"]:
        # Literál runtime je statický záznam String, adresa se nemění.
        return ["lslrt_str"+String(strings[text]),"Int"]
    end
    # Immutable literals have program lifetime. Clone each one once during
    # startup, keep it in the registered global roots, and reuse its pointer.
    offset = (len(s["unit"]["variables"])+strings[text])*8
    address = temp(s,"add(lsl_globals, "+String(offset)+")")
    return scalar(s,"load("+address+")","String")
end
function boxed(s,value,force=False):
    if s["internal"] and not force:
        return value[0]
    end
    kind = value[1]
    if kind == "Int":
        return rt(s,"box_int",[value[0]],"Any",False)[0]
    elif kind == "Bool":
        return rt(s,"box_bool",[value[0]],"Any",False)[0]
    elif kind == "None":
        return rt(s,"box_none",[],"Any",False)[0]
    elif kind == "Function":
        return rt(s,"box_dynamic_function",[value[0],"-1"],"Any",False)[0]
    end
    return value[0]
end
function numeric_runtime_operand(s,value):
    # A known scalar retains its numeric meaning even when its bits equal a
    # live object address. Generic runtime arithmetic probes its arguments;
    # do not pass a known Int/Bool through that ambiguous raw representation.
    return boxed(s,value,s["internal"] and value[1] in ["Int","Bool"])
end
function integer(s,value):
    if value[1] == "Int" or value[1] == "Bool" or value[1] == "None":
        return value[0]
    end
    return rt(s,"unbox_dynamic_int",[value[0]],"Int",False)[0]
end
function floating(s,value):
    # Public Float values retain their boxed word ABI. Only the expression
    # temporary is a LuxIR Float64; Int conversion happens after integer arithmetic.
    if value[1] == "Float":
        return temp(s,"load("+temp(s,"add("+value[0]+", 8)")+")","d")
    end
    return temp(s,"itof("+typed(integer(s,value))+")","d")
end
function float_box(s,value):
    return rt(s,"float_new",[temp(s,"bitcast("+value+")")],"Float",False)
end
function float_tree_safe(s,node):
    # Fuse only numeric trees without calls, indexing, or other side effects.
    # In particular, do not move a boxed payload load before a call which can
    # mutate that object through a runtime primitive.
    if infer(s,node) not in ["Float","Int","Bool"]:
        return False
    end
    kind = node["kind"]
    if kind in ["name","literal"]:
        return True
    elif kind == "unary" and node["operator"] in ["+","-"]:
        return float_tree_safe(s,node["operand"])
    elif kind == "binary" and node["operator"] in ["+","-","*","/"]:
        return float_tree_safe(s,node["left"]) and float_tree_safe(s,node["right"])
    end
    return False
end
function float_tree(s,node):
    if infer(s,node) == "Float":
        kind = node["kind"]
        if kind == "literal":
            return temp(s,"bitcast("+String(__lsl_float_bits(__lsl_parse_float(node["value"])))+")","d")
        elif kind == "unary":
            value = float_tree(s,node["operand"])
            if node["operator"] == "-":
                return temp(s,"neg("+value+")","d")
            end
            return value
        elif kind == "binary":
            left = float_tree(s,node["left"])
            right = float_tree(s,node["right"])
            op = node["operator"]
            if op == "/" and infer(s,node["left"]) != "Float" and infer(s,node["right"]) != "Float":
                # Int / Int raises on zero, whereas Float division preserves
                # the runtime's IEEE infinity/NaN behavior, including -0.0.
                zero = temp(s,"eq("+typed(right,"Float64")+", 0.0)","w")
                bad = label(s)
                ok = label(s)
                call jump_if(s,zero,bad,ok)
                call mark(s,bad)
                call raise_error(s,"ZeroDivisionError: division by zero")
                call mark(s,ok)
            end
            operations = {"+":"add","-":"sub","*":"mul","/":"div"}
            return temp(s,operations[op]+"("+left+", "+right+")","d")
        end
    end
    return floating(s,expression(s,node))
end
function truth(s,value):
    if len(value) > 2:
        # An immediately consumed comparison needs only its word condition.
        # The fresh extension has no earlier uses. Keeping it between the
        # compare and branch prevents the backend's flag selector from folding them.
        last = len(s["lines"]) - 1
        extension = "    Int64("+value[0]+") = zext32("+value[2]+")"+chr(10)
        if last >= 0 and s["lines"][last] == extension:
            s["lines"][last] = ""
        end
        return value[2]
    end
    if value[1] == "Bool":
        return temp(s,"copy("+value[0]+")","w")
    end
    if value[1] in ["Bool","Int","None"]:
        return temp(s,"ne("+typed(value[0],"Int64")+", 0)","w")
    end
    return rt(s,"truth",[value[0]],"Bool",False)[0]
end
function branch_condition(s,node,yes,no):
    # Conditions need truth rather than an operand-valued and/or temporary.
    # Preserve short-circuit order and evaluate chained operands once.
    kind = node["kind"]
    if kind == "binary" and node["operator"] in ["and","or"]:
        right = label(s)
        if node["operator"] == "and":
            call branch_condition(s,node["left"],right,no)
        else:
            call branch_condition(s,node["left"],yes,right)
        end
        call mark(s,right)
        call branch_condition(s,node["right"],yes,no)
    elif kind == "unary" and node["operator"] == "not":
        call branch_condition(s,node["operand"],no,yes)
    elif kind == "compare" and len(node["operators"]) > 1:
        left = expression(s,node["operands"][0])
        for index in rang(len(node["operators"])):
            right = expression(s,node["operands"][index+1])
            next = yes
            if index+1 < len(node["operators"]):
                next = label(s)
            end
            condition = truth(s,compare(s,node["operators"][index],left,right))
            call jump_if(s,condition,next,no)
            s["ended"] = True
            if index+1 < len(node["operators"]):
                call mark(s,next)
            end
            left = right
        end
    else:
        condition = truth(s,expression(s,node))
        call jump_if(s,condition,yes,no)
        s["ended"] = True
    end
end
function used(s,name):
    if name not in s["used"]:
        if name not in s["unit"]["functions"]:
            Error(CompileError: "LuxIR missing helper: "+name)
        end
        call validation.ensure_function_checked(s["unit"],name)
        s["used"][name] = True
        s["queue"].append(name)
    end
    if s["runtime"]:
        return runtime_symbol(name)
    end
    return "fn"+String(s["ids"][name])
end
# Symbol funkce nebo globálu runtime: jméno z LSL bez prefixu modulu.
function runtime_base_name(name):
    return String(name).split("@")[-1]
end
function runtime_symbol(name):
    text = runtime_base_name(name)
    # Rozhraní (rt_*, qbe_*, lsl_*) má pevná jména, pomocné funkce prefix.
    if text.startswith("rt_") or text.startswith("qbe_") or text.startswith("lsl_"):
        return text
    end
    return "lslrt_"+text
end
# Globál runtime je samostatný datový symbol; tls_ jsou thread-local.
function runtime_global(s,name):
    symbol = runtime_global_symbol(name)
    if runtime_base_name(name).startswith("tls_"):
        return temp(s,"copy(thread("+symbol+"))")
    end
    return symbol
end
function runtime_global_symbol(name):
    return "lslrt_g_"+String(name).replace("@","_")
end
# Konstanta runtime: jméno jen z velkých písmen, číslic a _, inlinuje se.
function runtime_constant_name(name):
    text = runtime_base_name(name)
    letter = False
    for index in rang(__lsl_text_byte_length(text)):
        byte = __lsl_text_byte(text,index)
        if byte >= 65 and byte <= 90:
            letter = True
        elif not (byte == 95 or (byte >= 48 and byte <= 57)):
            return False
        end
    end
    return letter
end
# Runtime: malé funkce bez cyklů se vkládají přímo do volajícího (LuxIR
# zatím neinlinuje); runtime se tak dá psát s malými pomocnými funkcemi.
RUNTIME_INLINE_NODES = 200
function syntax_size(node,limit):
    count = 1
    if type(node) == "Dictionary":
        if node.get("kind","") in ["while","for"]:
            return limit + 1
        end
        for key in node:
            value = node[key]
            kind = type(value)
            if kind == "Dictionary" or kind == "List":
                count += syntax_size(value,limit - count)
                if count > limit:
                    return count
                end
            end
        end
    elif type(node) == "List":
        for item in node:
            kind = type(item)
            if kind == "Dictionary" or kind == "List":
                count += syntax_size(item,limit - count)
                if count > limit:
                    return count
                end
            end
        end
    end
    return count
end
function runtime_inlinable(s,name):
    cache = s["inline_cache"]
    if name not in cache:
        # Chladné cesty (fatal_*, cold_*) zůstávají voláním: nezvětšují kód.
        base_name = runtime_base_name(name)
        cold = base_name.startswith("fatal_") or base_name.startswith("cold_")
        cache[name] = not cold and syntax_size(s["unit"]["functions"][name]["body"],RUNTIME_INLINE_NODES) <= RUNTIME_INLINE_NODES
    end
    return cache[name] and name not in s["inline_stack"] and len(s["inline_stack"]) < 4
end
function inline_call(s,name,values):
    declaration = s["unit"]["functions"][name]
    scope = semantic.ensure_function_scope(s["unit"],name)
    saved = [s["locals"],s["types"],s["inline_return"],s["local_conditions"]]
    mapping = {}
    types = Dictionary(s["types"])
    for local in scope["variables"]:
        s["inline_counter"] += 1
        mapping[local] = 100000 + s["inline_counter"]
        types[local] = "Int"
    end
    operands = [integer(s,value) for value in values]
    s["locals"] = mapping
    s["types"] = types
    s["local_conditions"] = {}
    for index in rang(len(declaration["parameters"])):
        call define(s,"v"+String(mapping[declaration["parameters"][index]]),"copy("+operands[index]+")")
    end
    s["inline_counter"] += 1
    result = "v"+String(100000 + s["inline_counter"])
    done = label(s)
    s["inline_return"] = [result,done]
    s["inline_stack"].append(name)
    call statements(s,declaration["body"],"","")
    call s["inline_stack"].pop()
    if not s["ended"]:
        call define(s,result,"copy(0)")
        call jump(s,done)
    end
    call mark(s,done)
    s["locals"] = saved[0]
    s["types"] = saved[1]
    s["inline_return"] = saved[2]
    s["local_conditions"] = {}
    return [result,"Int"]
end
function function_call(s,name,values):
    if s["runtime"] and runtime_inlinable(s,name):
        return inline_call(s,name,values)
    end
    target = used(s,name)
    declaration = s["unit"]["functions"][name]
    parameters = s["unit"]["function_parameters"][name]
    args = []
    for index in rang(len(values)):
        value = values[index]
        if parameters[index] in ["Int","Bool"]:
            args.append(integer(s,value))
        elif parameters[index] == "Any":
            args.append(boxed(s,value,not declaration.get("internal_abi",False)))
        else:
            args.append(value[0])
        end
    end
    return invoke(s,target,args,s["unit"]["function_returns"].get(name,"Any"))
end
function infer(s,node):
    return semantic.infer_expression_type(node,s["types"],s["unit"]["function_returns"])
end
function load_name(s,name,node=None):
    if name in s["locals"]:
        value = ["v"+String(s["locals"][name]),s["types"].get(name,"Any")]
        if name in s["local_conditions"]:
            value.append(s["local_conditions"][name])
        end
        return value
    elif name in s["unit"]["variables"] and s["runtime"]:
        if name in s["runtime_constants"]:
            return [String(s["runtime_constants"][name]),"Int"]
        elif name in s["runtime_tables"]:
            # Konstantní tabulka: hodnotou jména je adresa pole slov.
            return [runtime_global_symbol(name),"Int"]
        end
        return [temp(s,"load("+runtime_global(s,name)+")"),"Int"]
    elif name in s["unit"]["variables"]:
        index = s["unit"]["variables"][name]-1
        if name in s["global_reads"]:
            # A callback can run before a module assignment, or after a
            # deletion. Guard the actual read, including inside a taken branch.
            flag_ptr = temp(s,"add(lsl_global_flags, "+String(index)+")")
            initialized = temp(s,"load_u8("+flag_ptr+")","w")
            ready = label(s)
            missing = label(s)
            call jump_if(s,initialized,ready,missing)
            call mark(s,missing)
            if node == None:
                node = s["global_reads"][name]
            end
            call raise_error(s,source_error(s,"NameError: global variable '"+String(name).split("@")[-1]+"' read before assignment",node))
            call mark(s,ready)
        end
        ptr = temp(s,"add(lsl_globals, "+String(index*8)+")")
        return [temp(s,"load("+ptr+")"),s["unit"]["types"].get(name,"Any")]
    elif name in s["unit"]["functions"]:
        address = used(s,name)
        if not s["unit"]["internal_abi"]:
            # Direct calls retain their inferred scalar return ABI. Escaping
            # Function values expose an Any-to-Any entry, including returns.
            s["callbacks"][name] = True
            address = "callback"+String(s["ids"][name])
        end
        return [address,"Function"]
    end
    Error(CompileError: "LuxIR unknown variable: "+name)
end
function store_name(s,name,value,initialized=True):
    expected = s["types"].get(name,"Any")
    if name not in s["locals"]:
        # Global reads use the unit's fixed representation. A comprehension
        # can refine the emitter's temporary type map after that layout was
        # chosen; it must not change a global Any slot into a raw Int slot.
        expected = s["unit"]["types"].get(name,"Any")
    end
    operand = value[0]
    if expected == "Any":
        operand = boxed(s,value)
    elif expected in ["Int","Bool"]:
        operand = integer(s,value)
    end
    if name not in s["locals"] and s["runtime"]:
        if name in s["runtime_constants"] or name in s["runtime_tables"]:
            Error(CompileError: "runtime constant cannot be assigned: "+runtime_base_name(name))
        end
        call store(s,"Int64",operand,runtime_global(s,name))
        return None
    end
    if name in s["locals"]:
        call define(s,"v"+String(s["locals"][name]),"copy("+operand+")")
        if expected in ["Int","Bool"] and len(value) > 2:
            s["local_conditions"][name] = value[2]
        elif name in s["local_conditions"]:
            del(s["local_conditions"][name])
        end
    else:
        index = s["unit"]["variables"][name]-1
        ptr = temp(s,"add(lsl_globals, "+String(index*8)+")")
        call store(s,"Int64",operand,ptr)
        if name in s["guarded_globals"]:
            flag_ptr = temp(s,"add(lsl_global_flags, "+String(index)+")")
            flag = "0"
            if initialized:
                flag = "1"
            end
            call store(s,"Int8",flag,flag_ptr)
        end
    end
end
function checked_sequence_index(s,position,length,message):
    negative = temp(s,"lt("+typed(position,"Int64")+", 0)","w")
    adjusted = temp(s,"mul("+temp(s,"zext32("+negative+")")+", "+length+")")
    position = temp(s,"add("+position+", "+adjusted+")")
    valid = temp(s,"ult("+typed(position,"Int64")+", "+length+")","w")
    ok = label(s)
    bad = label(s)
    call jump_if(s,valid,ok,bad)
    call mark(s,bad)
    call raise_error(s,message)
    call mark(s,ok)
    return position
end
function read_at(s,target,index,kind,node=None):
    if kind == "Dictionary":
        return rt(s,"dict_get",[target[0],boxed(s,index)],"Any")
    elif kind == "Any":
        if s["internal"]:
            return rt(s,"get",[target[0],integer(s,index)],"Any")
        elif s["trusted"]:
            # Core helpers iterate Set's private List-layout storage too.
            return rt(s,"iter_get",[target[0],boxed(s,index)],"Any")
        end
        if index[1] in ["Int","Bool"]:
            # Public Any values must be checked before touching payloads.
            code = rt(s,"type_code",[target[0]],"Int",False)[0]
            list_like = temp(s,"or("+temp(s,"eq("+typed(code,"Int64")+", 2)","w")+", "+temp(s,"eq("+typed(code,"Int64")+", 7)","w")+")","w")
            list_like = temp(s,"or("+list_like+", "+temp(s,"eq("+typed(code,"Int64")+", 8)","w")+")","w")
            direct = label(s)
            fallback = label(s)
            done = label(s)
            result = temp(s,"copy(0)")
            call jump_if(s,list_like,direct,fallback)
            call mark(s,direct)
            length = temp(s,"load("+temp(s,"add("+target[0]+", 8)")+")")
            position = checked_sequence_index(s,index[0],length,"IndexError: index out of range")
            data = temp(s,"load("+temp(s,"add("+target[0]+", 24)")+")")
            address = temp(s,"add("+data+", "+temp(s,"mul("+position+", 8)")+")")
            call define(s,result,"load("+address+")")
            call jump(s,done)
            call mark(s,fallback)
            value = rt(s,"dynamic_get",[target[0],boxed(s,index)],"Any")
            call define(s,result,"copy("+value[0]+")")
            call jump(s,done)
            call mark(s,done)
            return [result,"Any"]
        end
        return rt(s,"dynamic_get",[target[0],boxed(s,index)],"Any")
    end
    if not s["internal"] and index[1] not in ["Int","Bool"]:
        position = rt(s,"checked_index",[boxed(s,index)],"Int")[0]
    else:
        position = integer(s,index)
    end
    if kind == "String":
        length = rt(s,"length",[target[0]],"Int",False)[0]
    else:
        # Typed collections all carry their logical element count at +8.
        length = temp(s,"load("+temp(s,"add("+target[0]+", 8)")+")")
    end
    position = checked_sequence_index(s,position,length,source_error(s,"IndexError: index out of range",node))
    if kind == "String":
        return rt(s,"get",[target[0],position],"String")
    end
    pointer = temp(s,"add("+target[0]+", 24)")
    data = temp(s,"load("+pointer+")")
    width = 8
    if kind == "ByteArray":
        width = 1
    end
    offset = temp(s,"mul("+position+", "+String(width)+")")
    address = temp(s,"add("+data+", "+offset+")")
    if kind == "ByteArray":
        return scalar(s,"load_u8("+address+")")
    elif kind == "IntArray":
        return scalar(s,"load("+address+")")
    elif kind == "FloatArray":
        return rt(s,"float_new",[temp(s,"load("+address+")")],"Float",False)
    end
    return [temp(s,"load("+address+")"),"Any"]
end
# Copy a validated String's UTF-8 payload into an allocated destination.
# No allocation or safepoint is allowed while the destination is incomplete.
function copy_join_bytes(s,destination,text,position):
    count = temp(s,"load("+temp(s,"add("+text+", 8)")+")")
    source = temp(s,"add("+text+", 16)")
    offset = temp(s,"copy(0)")
    head = label(s)
    body = label(s)
    done = label(s)
    call jump(s,head)
    call mark(s,head)
    valid = temp(s,"lt("+typed(offset,"Int64")+", "+count+")","w")
    call jump_if(s,valid,body,done)
    call mark(s,body)
    byte = temp(s,"load_u8("+temp(s,"add("+source+", "+offset+")")+")")
    address = temp(s,"add("+destination+", "+temp(s,"add("+position+", "+offset+")")+")")
    call store(s,"Int8",byte,address)
    call define(s,offset,"add("+offset+", 1)")
    call jump(s,head)
    call mark(s,done)
    return temp(s,"add("+position+", "+count+")")
end
function native_join(shared):
    s = {"unit":shared["unit"],"strings":shared["strings"],"lines":[],"counter":0,"label":0,"ended":False,"local_conditions":{},"runtime":False}
    call line(s,"function lsl_join_native(Int64(separator), Int64(values)) -> Int64:")
    call mark(s,"start")
    count = temp(s,"load("+temp(s,"add(values, 8)")+")")
    data = temp(s,"load("+temp(s,"add(values, 24)")+")")
    separator_length = temp(s,"load("+temp(s,"add(separator, 8)")+")")
    index = temp(s,"copy(0)")
    total = temp(s,"copy(0)")
    call jump(s,"validate")
    call mark(s,"validate")
    more = temp(s,"lt("+typed(index,"Int64")+", "+count+")","w")
    call jump_if(s,more,"validate_item","validated")
    call mark(s,"validate_item")
    item = temp(s,"load("+temp(s,"add("+data+", "+temp(s,"mul("+index+", 8)")+")")+")")
    code = temp(s,"call rt_runtime_type_code("+item+")")
    valid = temp(s,"eq("+typed(code,"Int64")+", 1)","w")
    call jump_if(s,valid,"valid_item","invalid_item")
    call mark(s,"invalid_item")
    message = string(s,"TypeError: expected a String")
    call line(s,"    call qbe_error_set("+message[0]+")")
    call line(s,"    return 0")
    call mark(s,"valid_item")
    length = temp(s,"load("+temp(s,"add("+item+", 8)")+")")
    call define(s,total,"add("+total+", "+length+")")
    call define(s,index,"add("+index+", 1)")
    call jump(s,"validate")
    call mark(s,"validated")
    empty = temp(s,"eq("+typed(count,"Int64")+", 0)","w")
    call jump_if(s,empty,"empty","nonempty")
    call mark(s,"empty")
    call line(s,"    return "+string(s,"")[0])
    call mark(s,"nonempty")
    one = temp(s,"eq("+typed(count,"Int64")+", 1)","w")
    call jump_if(s,one,"single","allocate")
    call mark(s,"single")
    call line(s,"    return "+temp(s,"load("+data+")"))
    call mark(s,"allocate")
    length = temp(s,"add("+total+", "+temp(s,"mul("+separator_length+", "+temp(s,"sub("+count+", 1)")+")")+")")
    size = temp(s,"add("+length+", 17)")
    result = temp(s,"call rt_runtime_alloc("+size+")")
    call store(s,"Int64","1",result)
    call store(s,"Int64",length,temp(s,"add("+result+", 8)"))
    destination = temp(s,"add("+result+", 16)")
    position = temp(s,"copy(0)")
    call define(s,index,"copy(0)")
    call jump(s,"copy")
    call mark(s,"copy")
    more = temp(s,"lt("+typed(index,"Int64")+", "+count+")","w")
    call jump_if(s,more,"copy_separator_check","complete")
    call mark(s,"copy_separator_check")
    first = temp(s,"eq("+typed(index,"Int64")+", 0)","w")
    call jump_if(s,first,"copy_item","copy_separator")
    call mark(s,"copy_separator")
    next = copy_join_bytes(s,destination,"separator",position)
    call define(s,position,"copy("+next+")")
    call jump(s,"copy_item")
    call mark(s,"copy_item")
    item = temp(s,"load("+temp(s,"add("+data+", "+temp(s,"mul("+index+", 8)")+")")+")")
    next = copy_join_bytes(s,destination,item,position)
    call define(s,position,"copy("+next+")")
    call define(s,index,"add("+index+", 1)")
    call jump(s,"copy")
    call mark(s,"complete")
    call store(s,"Int8","0",temp(s,"add("+destination+", "+position+")"))
    call line(s,"    return "+result)
    call line(s,"end")
    return [s["lines"],[]]
end
function dictionary_key(s,value):
    if not s["internal"] and value[1] in ["Any","Set"]:
        code = rt(s,"type_code",[value[0]],"Int",False)[0]
        invalid = temp(s,"eq("+typed(code,"Int64")+", 16)","w")
        bad = label(s)
        good = label(s)
        call jump_if(s,invalid,bad,good)
        call mark(s,bad)
        call raise_error(s,"TypeError: mutable Set cannot be a Dictionary key")
        call mark(s,good)
    end
    return boxed(s,value)
end
function constant_division(s,operator,a,divisor):
    if divisor <= 0:
        return []
    end
    if (divisor & (divisor - 1)) == 0:
        if operator == "%":
            return scalar(s,"and("+a+", "+String(divisor - 1)+")")
        end
        shift = 0
        while (divisor >> shift) > 1:
            shift += 1
        end
        return scalar(s,"sar("+a+", "+String(shift)+")")
    end
    if divisor >= 2147483648:
        return []
    end
    # A guarded signed-32-bit dividend needs only a widening multiply.
    # Larger Int64 values retain exact native division, including INT64_MIN.
    pair = semantic.magic_signed(divisor,32)
    magic = pair[0]
    fits = temp(s,"ult("+typed(temp(s,"add("+a+", 2147483648)"),"Int64")+", 4294967296)","w")
    small = label(s)
    wide = label(s)
    done = label(s)
    quotient = temp(s,"copy(0)")
    call jump_if(s,fits,small,wide)
    call mark(s,small)
    upper = temp(s,"sar("+temp(s,"mul("+a+", "+String(magic)+")")+", 32)")
    if magic < 0:
        upper = temp(s,"add("+upper+", "+a+")")
    end
    shifted = temp(s,"sar("+upper+", "+String(pair[1])+")")
    call define(s,quotient,"add("+shifted+", "+temp(s,"shr("+a+", 63)")+")")
    call jump(s,done)
    call mark(s,wide)
    call define(s,quotient,"div("+a+", "+String(divisor)+")")
    call jump(s,done)
    call mark(s,done)
    remainder = temp(s,"sub("+a+", "+temp(s,"mul("+quotient+", "+String(divisor)+")")+")")
    # Convert truncation to language floor semantics, including INT64_MIN.
    negative = temp(s,"sar("+remainder+", 63)")
    if operator == "//":
        return scalar(s,"add("+quotient+", "+negative+")")
    end
    return scalar(s,"add("+remainder+", "+temp(s,"and("+negative+", "+String(divisor)+")")+")")
end
function numeric_pair(s,left,right,mode="0"):
    a = boxed(s,left)
    b = boxed(s,right)
    call rt(s,"require_numeric_pair",[a,b,mode],"None")
    return [a,b]
end
function public_integer_binary(s,operator,left,right):
    # Public Any may contain non-numeric objects or raw legacy values. Query
    # the registered object type before loading an Int/Bool payload. Keep
    # mixed Float, String, List and errors on the existing public helper path.
    tests = []
    for value in [left,right]:
        if value[1] == "Any":
            code = rt(s,"type_code",[value[0]],"Int",False)[0]
            is_int = temp(s,"eq("+typed(code,"Int64")+", 9)","w")
            is_bool = temp(s,"eq("+typed(code,"Int64")+", 4)","w")
            tests.append(temp(s,"or("+is_int+", "+is_bool+")","w"))
        end
    end
    condition = tests[0]
    if len(tests) == 2:
        condition = temp(s,"and("+condition+", "+tests[1]+")","w")
    end
    fast = label(s)
    fallback = label(s)
    done = label(s)
    result = temp(s,"copy(0)")
    call jump_if(s,condition,fast,fallback)
    call mark(s,fast)
    operands = []
    for value in [left,right]:
        number = value[0]
        if value[1] == "Any":
            number = temp(s,"load("+temp(s,"add("+number+", 8)")+")")
        end
        operands.append(number)
    end
    operation = "add"
    if operator == "*":
        operation = "mul"
    elif operator == "-":
        operation = "sub"
    end
    number = temp(s,operation+"("+operands[0]+", "+operands[1]+")")
    boxed_result = rt(s,"box_int",[number],"Any",False)[0]
    call define(s,result,"copy("+boxed_result+")")
    call jump(s,done)
    call mark(s,fallback)
    if operator == "-":
        operands = numeric_pair(s,left,right)
        generic = rt(s,"sub_any",operands,"Any")
        generic = rt(s,"box_dynamic_int",[generic[0]],"Any",False)
    else:
        helpers = {"+":"__lsl_public_add","*":"__lsl_public_multiply"}
        generic = function_call(s,helpers[operator],[left,right])
    end
    call define(s,result,"copy("+generic[0]+")")
    call jump(s,done)
    call mark(s,done)
    return [result,"Any"]
end
function binary(s,operator,left,right,node=None):
    a = left[0]
    b = right[0]
    if operator == "+" and left[1] == "String" and right[1] == "String":
        return rt(s,"string_concat",[a,b],"String",False)
    elif operator == "+" and left[1] in ["List","Tuple"] and right[1] in ["List","Tuple"]:
        return function_call(s,"__lsl_list_concat",[left,right])
    end
    if (left[1] == "Float" or right[1] == "Float") and operator in ["+","-","*","/"] and left[1] in ["Float","Int","Bool"] and right[1] in ["Float","Int","Bool"]:
        operations = {"+":"add","-":"sub","*":"mul","/":"div"}
        left_number = floating(s,left)
        right_number = floating(s,right)
        return float_box(s,temp(s,operations[operator]+"("+left_number+", "+right_number+")","d"))
    end
    numeric = left[1] in ["Int","Bool"] and right[1] in ["Int","Bool"]
    if operator in ["&","|","~","<<",">>"]:
        if not s["internal"] and not s["trusted"] and left[1] not in ["Int","Bool"]:
            left = function_call(s,"__lsl_bit_operand",[left])
        end
        if not s["internal"] and not s["trusted"] and right[1] not in ["Int","Bool"]:
            right = function_call(s,"__lsl_bit_operand",[right])
        end
        a = integer(s,left)
        b = integer(s,right)
        numeric = True
    end
    if numeric:
        operations = {"+":"add","-":"sub","*":"mul","&":"and","|":"or","~":"xor","<<":"shl",">>":"sar"}
        if operator in operations:
            if operator in ["<<",">>"]:
                negative = temp(s,"lt("+typed(b,"Int64")+", 0)","w")
                bad = label(s)
                ok = label(s)
                call jump_if(s,negative,bad,ok)
                call mark(s,bad)
                call raise_error(s,"ValueError: negative shift count")
                call mark(s,ok)
                wide = temp(s,"ge("+typed(b,"Int64")+", 64)","w")
                yes = label(s)
                no = label(s)
                done = label(s)
                result = temp(s,"copy(0)")
                call jump_if(s,wide,yes,no)
                call mark(s,yes)
                if operator == ">>":
                    call define(s,result,"sar("+a+", 63)")
                end
                call jump(s,done)
                call mark(s,no)
                call define(s,result,operations[operator]+"("+a+", "+b+")")
                call jump(s,done)
                call mark(s,done)
                return [result,"Int"]
            end
            return scalar(s,operations[operator]+"("+a+", "+b+")")
        elif operator in ["//","%","/"]:
            if operator != "/" and is_literal(b):
                reduced = constant_division(s,operator,a,Int(b))
                if len(reduced) != 0:
                    return reduced
                end
            end
            zero = temp(s,"eq("+typed(b,"Int64")+", 0)","w")
            bad = label(s)
            ok = label(s)
            call jump_if(s,zero,bad,ok)
            call mark(s,bad)
            message = "ZeroDivisionError: integer division or modulo by zero"
            if operator == "/":
                message = "ZeroDivisionError: division by zero"
            end
            call raise_error(s,source_error(s,message,node))
            call mark(s,ok)
            if operator == "/":
                return rt(s,"float_div",[rt(s,"float_from_int",[a],"Float",False)[0],rt(s,"float_from_int",[b],"Float",False)[0]],"Float",False)
            end
            overflow = temp(s,"and("+temp(s,"eq("+typed(a,"Int64")+", -9223372036854775808)","w")+", "+temp(s,"eq("+typed(b,"Int64")+", -1)","w")+")","w")
            normal = label(s)
            special = label(s)
            division_done = label(s)
            quotient = temp(s,"copy(-9223372036854775808)")
            remainder = temp(s,"copy(0)")
            call jump_if(s,overflow,special,normal)
            call mark(s,special)
            call jump(s,division_done)
            call mark(s,normal)
            call define(s,quotient,"div("+a+", "+b+")")
            call define(s,remainder,"rem("+a+", "+b+")")
            call jump(s,division_done)
            call mark(s,division_done)
            negative = temp(s,"lt("+typed(temp(s,"xor("+a+", "+b+")"),"Int64")+", 0)","w")
            nonzero = temp(s,"ne("+typed(remainder,"Int64")+", 0)","w")
            adjust = temp(s,"and("+negative+", "+nonzero+")","w")
            adjust = temp(s,"zext32("+adjust+")")
            if operator == "//":
                return scalar(s,"sub("+quotient+", "+adjust+")")
            end
            return scalar(s,"add("+remainder+", "+temp(s,"mul("+adjust+", "+b+")")+")")
        elif operator in ["^","**"]:
            if not s["internal"] and not s["trusted"]:
                negative = temp(s,"lt("+typed(b,"Int64")+", 0)","w")
                bad = label(s)
                ready = label(s)
                call jump_if(s,negative,bad,ready)
                call mark(s,bad)
                call raise_error(s,source_error(s,"ValueError: negative Int exponent",node))
                call mark(s,ready)
            end
            return rt(s,"int_power",[a,b],"Int",False)
        end
    end
    if operator == "*" and left[1] == "String":
        return function_call(s,"__lsl_str_repeat",[left,right])
    elif operator == "*" and right[1] == "String":
        return function_call(s,"__lsl_str_repeat",[right,left])
    end
    if operator in ["//","%"]:
        name = "__lsl_floordiv_dyn"
        if operator == "%":
            name = "__lsl_mod_dyn"
        end
        if not s["internal"]:
            name = "__lsl_public_floordiv_dyn"
            if operator == "%":
                name = "__lsl_public_mod_dyn"
            end
        end
        if not s["internal"] and not s["trusted"]:
            call numeric_pair(s,left,right)
        end
        return function_call(s,name,[left,right])
    end
    if operator == "-" and not s["internal"] and not s["trusted"] and (left[1] == "Any" or right[1] == "Any") and left[1] in ["Any","Int","Bool"] and right[1] in ["Any","Int","Bool"]:
        return public_integer_binary(s,operator,left,right)
    end
    operations = {"+":"add_any","-":"sub_any","*":"mul_any","**":"pow_any","^":"pow_any"}
    if operator in operations:
        if not s["internal"] and not s["trusted"] and operator in ["+","*"] and (left[1] == "Any" or right[1] == "Any"):
            if left[1] in ["Any","Int","Bool"] and right[1] in ["Any","Int","Bool"]:
                return public_integer_binary(s,operator,left,right)
            end
            helpers = {"+":"__lsl_public_add","*":"__lsl_public_multiply"}
            result = function_call(s,helpers[operator],[left,right])
            return [result[0],"Any"]
        end
        helper = operations[operator]
        if s["internal"]:
            helper += "_raw"
        end
        operands = [numeric_runtime_operand(s,left),numeric_runtime_operand(s,right)]
        if not s["internal"] and not s["trusted"]:
            mode = "0"
            if operator in ["^","**"]:
                mode = "2"
            elif operator == "+":
                mode = "1"
            end
            call rt(s,"require_numeric_pair",[operands[0],operands[1],mode],"None")
        end
        result = rt(s,helper,operands,"Any")
        if not s["internal"] and not s["trusted"]:
            return rt(s,"box_dynamic_int",[result[0]],"Any",False)
        end
        return result
    elif operator == "/":
        a = numeric_runtime_operand(s,left)
        b = numeric_runtime_operand(s,right)
        if not s["internal"] and not s["trusted"]:
            call rt(s,"require_numeric_value",[a,"0"],"None")
            call rt(s,"require_numeric_value",[b,"0"],"None")
        end
        return rt(s,"float_div",[rt(s,"coerce_float",[a],"Float")[0],rt(s,"coerce_float",[b],"Float")[0]],"Float")
    end
    Error(CompileError: "LuxIR binary operator: "+operator)
end
function compare(s,op,left,right):
    if op in ["in","not in"]:
        if not s["internal"] and not s["trusted"] and right[1] in ["Any","Set","IntArray","FloatArray","ByteArray"]:
            result = function_call(s,"__lsl_dynamic_contains",[right,left])
            result = [result[0],"Bool"]
        else:
            helper = "contains"
            if right[1] == "String":
                helper = "string_contains"
            end
            result = rt(s,helper,[right[0],boxed(s,left)],"Bool")
        end
        if op == "not in":
            return scalar(s,"xor("+result[0]+", 1)","Bool")
        end
        return result
    end
    if (left[1] == "Float" or right[1] == "Float") and left[1] in ["Float","Int","Bool"] and right[1] in ["Float","Int","Bool"]:
        # Floating predicates preserve IEEE unordered/NaN semantics. A
        # three-way integer comparator cannot represent unordered operands.
        opcodes = {"==":"eq","!=":"ne","is":"eq","is not":"ne","<":"lt","<=":"le",">":"gt",">=":"ge"}
        left_number = floating(s,left)
        condition = temp(s,opcodes[op]+"("+typed(left_number,"Float64")+", "+floating(s,right)+")","w")
        return [temp(s,"zext32("+condition+")"),"Bool",condition]
    end
    numeric = left[1] in ["Int","Bool","None"] and right[1] in ["Int","Bool","None"]
    direct_equality = numeric and (s["internal"] or left[1] == right[1])
    if op in ["is","is not"]:
        if direct_equality:
            opcode = "eq"
            if op == "is not":
                opcode = "ne"
            end
            return scalar(s,opcode+"("+typed(left[0],"Int64")+", "+right[0]+")","Bool")
        end
        # Identity compares scalar values but retains object identity for
        # collections. Deep collection equality is reserved for == and !=.
        operands = [numeric_runtime_operand(s,left),numeric_runtime_operand(s,right)]
        result = rt(s,"equal_any",operands,"Bool",False)
        if op == "is not":
            return scalar(s,"xor("+result[0]+", 1)","Bool")
        end
        return result
    end
    if op in ["==","!="] and not direct_equality:
        if left[1] == "String" and right[1] == "String":
            result = rt(s,"string_equal",[left[0],right[0]],"Bool",False)
        elif s["internal"] and not (left[1] in ["List","Tuple","RealArray","IntArray","FloatArray","ByteArray","Dictionary","Set","Any"] and right[1] in ["List","Tuple","RealArray","IntArray","FloatArray","ByteArray","Dictionary","Set","Any"]):
            result = rt(s,"equal_any",[numeric_runtime_operand(s,left),numeric_runtime_operand(s,right)],"Bool",False)
        else:
            result = function_call(s,"__lsl_equal",[left,right])
        end
        if op == "!=":
            return scalar(s,"xor("+result[0]+", 1)","Bool")
        end
        # Equality helpers return a raw 0/1 word. Their recursive primitive
        # inference can widen to Int/Any; the language comparison stays Bool.
        return [result[0],"Bool"]
    end
    a = left[0]
    b = right[0]
    if not numeric:
        operands = [boxed(s,left),boxed(s,right)]
        if not s["internal"] and not s["trusted"] and (left[1] == "Any" or right[1] == "Any"):
            call rt(s,"require_numeric_pair",[operands[0],operands[1],"0"],"None")
        end
        a = rt(s,"compare_any",operands,"Int")[0]
        b = "0"
    end
    opcodes = {"==":"eq","!=":"ne","<":"lt","<=":"le",">":"gt",">=":"ge"}
    condition = temp(s,opcodes[op]+"("+typed(a,"Int64")+", "+b+")","w")
    return [temp(s,"zext32("+condition+")"),"Bool",condition]
end
function expression(s,node):
    if node == None:
        return ["0","None"]
    end
    kind = node["kind"]
    if s["has_validation_errors"] and expression_validation_error(s,node):
        return ["0","None"]
    end
    if not s["internal"] and (kind == "binary" or (kind == "unary" and node["operator"] == "-")) and infer(s,node) == "Float" and float_tree_safe(s,node):
        # Intermediate doubles and numeric literals need no heap objects.
        # Materialize one ordinary Float at the existing expression boundary.
        return float_box(s,float_tree(s,node))
    end
    if kind == "literal":
        value = node["value"]
        if node["literal_kind"] == "string":
            return string(s,value)
        elif value == "True":
            return ["1","Bool"]
        elif value == "False":
            return ["0","Bool"]
        elif value == "None":
            return ["0","None"]
        elif s["runtime"] and ("." in value or "e" in value or "E" in value):
            # Desetinný literál runtime: bity binary64 (bez objektu Float).
            return [String(__lsl_float_bits(__lsl_parse_float(value))),"Int"]
        elif infer(s,node) == "Float":
            bits = String(__lsl_float_bits(__lsl_parse_float(value)))
            return rt(s,"float_new",[bits],"Float",False)
        end
        return [String(semantic.integer_literal(node)),"Int"]
    elif kind == "name":
        return load_name(s,node["name"],node)
    elif kind in ["list","tuple","real_array"]:
        value = rt(s,"list_new",[String(len(node["items"])),"0"],"List",False)
        data = temp(s,"load("+temp(s,"add("+value[0]+", 24)")+")")
        for index in rang(len(node["items"])):
            item = expression(s,node["items"][index])
            if kind == "real_array" and item[1] not in ["Int","Float"]:
                item = function_call(s,"__lsl_require_real",[item])
            end
            address = temp(s,"add("+data+", "+String(index*8)+")")
            call store(s,"Int64",boxed(s,item),address)
        end
        if kind in ["tuple","real_array"]:
            tag = "7"
            value[1] = "Tuple"
            if kind == "real_array":
                tag = "8"
                value[1] = "RealArray"
            end
            call store(s,"Int64",tag,value[0])
        end
        return value
    elif kind == "dictionary":
        value = rt(s,"dict_new",[],"Dictionary",False)
        for entry in node["entries"]:
            key = expression(s,entry[0])
            item = expression(s,entry[1])
            call rt(s,"dict_set",[value[0],dictionary_key(s,key),boxed(s,item)],"None",False)
        end
        return value
    elif kind == "member":
        return rt(s,"dict_get",[expression(s,node["target"])[0],string(s,node["name"])[0]],"Any")
    elif kind == "index":
        target = expression(s,node["target"])
        return read_at(s,target,expression(s,node["index"]),target[1],node)
    elif kind == "slice":
        target = expression(s,node["target"])
        start = ["0","Int"]
        stop = ["0","Int"]
        step = ["1","Int"]
        has_start = "0"
        has_stop = "0"
        if node["start"] != None:
            start = expression(s,node["start"])
            has_start = "1"
        end
        if node["stop"] != None:
            stop = expression(s,node["stop"])
            has_stop = "1"
        end
        if node.get("step",None) != None:
            step = expression(s,node["step"])
        end
        if not s["internal"]:
            needs_index_check = (has_start == "1" and start[1] not in ["Int","Bool"]) or (has_stop == "1" and stop[1] not in ["Int","Bool"]) or step[1] not in ["Int","Bool"]
            if needs_index_check:
                # Match the public receiver-before-index validation order.
                target = function_call(s,"__lsl_require_sequence",[target])
            end
            if has_start == "1" and start[1] not in ["Int","Bool"]:
                start = rt(s,"checked_index",[boxed(s,start)],"Int")
            end
            if has_stop == "1" and stop[1] not in ["Int","Bool"]:
                stop = rt(s,"checked_index",[boxed(s,stop)],"Int")
            end
            if step[1] not in ["Int","Bool"]:
                step = rt(s,"checked_index",[boxed(s,step)],"Int")
            end
        end
        if target[1] == "String" and node.get("step",None) == None and start[1] in ["Int","Bool"] and stop[1] in ["Int","Bool"]:
            # The native contiguous slice scans UTF-8 boundaries once. The
            # general strided helper indexes each character independently.
            if has_stop == "0":
                stop = rt(s,"length",[target[0]],"Int",False)
            end
            return rt(s,"slice",[target[0],integer(s,start),integer(s,stop)],"String",False)
        end
        return function_call(s,"__lsl_slice3",[target,start,[has_start,"Bool"],stop,[has_stop,"Bool"],step])
    elif kind == "unary":
        value = expression(s,node["operand"])
        op = node["operator"]
        if op == "not":
            result = temp(s,"eq(Int32("+truth(s,value)+"), 0)","w")
            return [temp(s,"zext32("+result+")"),"Bool",result]
        elif op == "+":
            return value
        elif op == "~":
            if not s["internal"] and not s["trusted"] and value[1] not in ["Int","Bool"]:
                value = function_call(s,"__lsl_bit_operand",[value])
            end
            return scalar(s,"xor("+integer(s,value)+", -1)")
        elif value[1] in ["Int","Bool"]:
            return scalar(s,"neg("+value[0]+")")
        elif value[1] == "Float":
            return float_box(s,temp(s,"neg("+floating(s,value)+")","d"))
        end
        if not s["internal"] and not s["trusted"]:
            call rt(s,"require_numeric_value",[boxed(s,value),"0"],"None")
        end
        helper = "neg_any"
        if s["internal"]:
            helper += "_raw"
        end
        return rt(s,helper,[value[0]],"Any")
    elif kind == "binary":
        op = node["operator"]
        left = expression(s,node["left"])
        if op in ["and","or"]:
            yes = label(s)
            done = label(s)
            result = temp(s,"copy("+boxed(s,left)+")")
            cond = truth(s,left)
            if op == "and":
                call jump_if(s,cond,yes,done)
            else:
                call jump_if(s,cond,done,yes)
            end
            call mark(s,yes)
            right = expression(s,node["right"])
            call define(s,result,"copy("+boxed(s,right)+")")
            call jump(s,done)
            call mark(s,done)
            return [result,"Any"]
        end
        return binary(s,op,left,expression(s,node["right"]),node)
    elif kind == "compare":
        if len(node["operators"]) == 1:
            left = expression(s,node["operands"][0])
            right = expression(s,node["operands"][1])
            return compare(s,node["operators"][0],left,right)
        end
        result = temp(s,"copy(1)")
        done = label(s)
        left = expression(s,node["operands"][0])
        for index in rang(len(node["operators"])):
            right = expression(s,node["operands"][index+1])
            value = compare(s,node["operators"][index],left,right)
            call define(s,result,"copy("+value[0]+")")
            if index+1 < len(node["operators"]):
                next = label(s)
                call jump_if(s,truth(s,value),next,done)
                call mark(s,next)
            end
            left = right
        end
        call jump(s,done)
        call mark(s,done)
        return [result,"Bool"]
    elif kind == "call":
        return call_expression(s,node)
    elif kind == "comprehension":
        call semantic.collect_types(node["body"],s["types"],s["unit"]["function_returns"])
        call statements(s,node["body"],"","")
        return expression(s,node["result"])
    end
    Error(CompileError: "LuxIR expression: "+kind)
end
# Absolutní cesty ke zdrojům repozitáře nebo instalace se v binárce zkrátí
# na relativní (stdlib/..., compiler/pure/...), aby build nezávisel na adresáři.
function display_path(path):
    text = String(path)
    if not text.startswith("/"):
        return text
    end
    for marker in ["/compiler/pure/", "/stdlib/", "/extensions/"]:
        position = -1
        search = text.find(marker)
        while search >= 0:
            position = search
            following = text[search + 1:len(text)].find(marker)
            if following < 0:
                break
            end
            search = search + 1 + following
        end
        if position >= 0:
            return text[position + 1:len(text)]
        end
    end
    return text
end

function source_error(s,message,node=None):
    if node == None or s["internal"] or s["trusted"]:
        return message
    end
    return message+" at "+display_path(node.get("path",s["unit"]["path"]))+":"+String(node.get("line",1))
end
function raise_error(s,message):
    value = string(s,message)
    call invoke(s,"qbe_error_set",[value[0]],"None",False)
    call jump(s,s["error"])
end
function class_context(s):
    return {"scope_name":s["scope"],"path":s["unit"]["path"],"validation_errors":s["unit"]["validation_errors"],"prepared_arguments":s["unit"]["prepared_arguments"]}
end
function class_validation_error(s,node,rules):
    if not s["has_validation_errors"]:
        return False
    end
    # Kontext (nový slovník) jen pro pravidla, která v jednotce mají chybu.
    errors = s["unit"]["validation_errors"]
    for rule in rules:
        if rule not in errors:
            continue
        end
        error = validation.error_for(class_context(s),node,rule)
        if error != None:
            location = display_path(node.get("path",s["unit"]["path"]))+":"+String(node.get("line",1))+":"+String(node.get("column",1))
            call raise_error(s,error[0]+": "+error[1]+" at "+location)
            # The enclosing expression may still emit operations using its
            # placeholder result. Keep them in an unreachable basic block.
            call mark(s,label(s))
            return True
        end
    end
    return False
end
function expression_validation_error(s,node):
    # Reuse frontend decisions at the same evaluation sites as the native
    # emitter. Do not scan descendants: an unchosen and/or arm must stay inert.
    # Bez chyb validace se seznamy pravidel ani nealokují.
    if not s["has_validation_errors"]:
        return False
    end
    kind = node["kind"]
    if kind == "name":
        return class_validation_error(s,node,["unknown_variable"])
    elif kind == "member":
        return class_validation_error(s,node,["member_value"])
    elif kind == "index":
        return class_validation_error(s,node,["index_target"]) or class_validation_error(s,node["index"],["index_value"])
    elif kind == "slice":
        if class_validation_error(s,node,["slice_target"]):
            return True
        end
        for bound in [node["start"],node["stop"],node.get("step",None)]:
            if bound != None and class_validation_error(s,bound,["slice_bound"]):
                return True
            end
        end
    elif kind == "unary":
        if node["operator"] == "~":
            return class_validation_error(s,node["operand"],["bit_operand"])
        end
        return class_validation_error(s,node,["unary_numeric"])
    elif kind == "binary":
        if class_validation_error(s,node,["add_operands","multiply_operands","numeric_operands","exponent_operands","floor_operands","float_exponent","int_exponent"]):
            return True
        end
        if node["operator"] in ["&","|","xor","<<",">>"]:
            return class_validation_error(s,node["left"],["bit_operand"]) or class_validation_error(s,node["right"],["bit_operand"]) or class_validation_error(s,node,["negative_shift"])
        end
    elif kind == "compare" and len(node["operators"]) == 1:
        if node["operators"][0] in ["in","not in"]:
            return class_validation_error(s,node["operands"][1],["membership_target"]) or class_validation_error(s,node["operands"][0],["membership_value"])
        end
        return class_validation_error(s,node,["comparison_operator","ordered_operands"])
    elif kind == "call":
        if node["target"]["kind"] == "name":
            return class_validation_error(s,node,["call_keywords","help_arity","builtin_arity","array_arity","call_target","unknown_function","rang_value_arity","indirect_keywords"])
        elif node["target"]["kind"] == "member":
            return class_validation_error(s,node,["method_keywords","method_supported","method_arity","get_arity","setdefault_arity","pop_arity"])
        end
    end
    return False
end
# Znaménko celočíselného literálu kroku rang (i s unárním minus), jinak 0.
function constant_step_sign(node):
    negative = False
    while node["kind"] == "unary" and node["operator"] in ["-","+"]:
        if node["operator"] == "-":
            negative = not negative
        end
        node = node["operand"]
    end
    if node["kind"] != "literal" or node.get("literal_kind","") != "number":
        return 0
    end
    text = node["value"]
    if text.find(".") >= 0 or text.find("e") >= 0 or text.find("E") >= 0 or text.find("x") >= 0 or text.find("X") >= 0:
        return 0
    end
    for character in text:
        if character != "0" and character != "_":
            if negative:
                return -1
            end
            return 1
        end
    end
    return 0
end
function checked_integer_expression(s,node):
    if class_validation_error(s,node,["integer_value"]):
        return ["0","Int"]
    end
    value = expression(s,node)
    if value[1] == "Any" and not s["internal"] and not s["trusted"]:
        call rt(s,"require_numeric_value",[value[0],"1"],"Any")
    end
    return [integer(s,value),"Int"]
end
function builtin_argument(s,name,node,index):
    rule = ""
    helper = ""
    if name in ["chr","arg","exit","thread_join"] and index == 0:
        return checked_integer_expression(s,node)
    elif (name in ["ord","native_open","readfile","readbytes","exists","mkdir","unlink","rmdir","writefile","appendfile","writebytes","run","run_clean","capture","capture_clean","__lsl_run","__lsl_run_clean","__lsl_capture","__lsl_capture_clean","capture_input","capture_input_clean","capture_stream","capture_stream_clean","capture_input_stream","capture_input_stream_clean"] and index == 0) or (name in ["writefile","appendfile"] and index == 1) or (name in ["capture_input","capture_input_clean","capture_input_stream","capture_input_stream_clean"] and index == 2):
        rule = "string_value"
        helper = "__lsl_require_string_value"
    elif name in ["run","run_clean","capture","capture_clean","__lsl_run","__lsl_run_clean","__lsl_capture","__lsl_capture_clean","capture_input","capture_input_clean","capture_stream","capture_stream_clean","capture_input_stream","capture_input_stream_clean"] and index == 1:
        rule = "list_value"
        helper = "__lsl_require_list"
    elif name == "writebytes" and index == 1:
        rule = "byte_sequence"
        helper = "__lsl_require_byte_sequence"
    elif name == "thread_spawn":
        rule = "thread_function"
    elif name == "len":
        rule = "length_target"
    end
    if rule != "" and class_validation_error(s,node,[rule]):
        return ["0","None"]
    end
    value = expression(s,node)
    if helper != "" and value[1] == "Any" and not s["internal"] and not s["trusted"]:
        return function_call(s,helper,[value])
    end
    return value
end
function class_arguments(s,node,declaration,skip):
    arguments = validation.arguments(class_context(s),node,declaration,skip)
    values = [["0","None"] for argument in arguments]
    # Match the existing native class-call ABI's right-to-left evaluation.
    # Binding/defaults are already prepared by the shared frontend.
    index = len(arguments)-1
    while index >= 0:
        values[index] = expression(s,arguments[index])
        index -= 1
    end
    return values
end
function class_constructor(s,node):
    name = node["target"]["name"]
    instance = rt(s,"dict_new",[],"Instance:"+name,False)
    if class_validation_error(s,node,["constructor_keywords","arguments","constructor_arity"]):
        return instance
    end
    initializer = semantic.resolve_method_name(s["unit"]["classes"],s["unit"]["functions"],name,"init")
    if initializer != "":
        values = class_arguments(s,node,s["unit"]["functions"][initializer],1)
        call function_call(s,initializer,[instance]+values)
    end
    return instance
end
function class_method(s,node):
    target = node["target"]
    receiver = target["target"]
    is_origin = receiver["kind"] == "name" and receiver["name"] == "origin"
    class_name = ""
    if is_origin:
        if class_validation_error(s,node,["origin_method"]):
            return ["0","Any"]
        end
        declaration = s["unit"]["functions"][s["scope"]]
        class_name = semantic.class_parent_name(s["unit"]["classes"],declaration["class_name"])
        receiver = {"kind":"name","name":"self","line":node["line"],"column":node["column"],"end_column":node["end_column"]}
    else:
        if class_validation_error(s,node,["class_method"]):
            return ["0","Any"]
        end
        receiver_type = infer(s,receiver)
        offset = 9
        if receiver_type.startswith("Class:"):
            offset = 6
        end
        class_name = receiver_type[offset:len(receiver_type)]
    end
    name = semantic.resolve_method_name(s["unit"]["classes"],s["unit"]["functions"],class_name,target["name"])
    declaration = s["unit"]["functions"][name]
    arguments = []
    if is_origin or (len(declaration["parameters"]) > 0 and declaration["parameters"][0] == "self"):
        arguments.append(receiver)
    end
    arguments.extend(node["arguments"])
    # Use exactly the synthetic call identity prepared by validation for
    # method/origin calls, including its caller scope and source position.
    combined = {"kind":"call","line":node["line"],"column":node["column"],"end_column":node["end_column"],"target":{"kind":"name","name":name},"arguments":arguments}
    if "argument_names" in node:
        names = []
        if len(arguments) > len(node["arguments"]):
            names.append("")
        end
        names.extend(node["argument_names"])
        combined["argument_names"] = names
    end
    if class_validation_error(s,combined,["arguments","function_arity"]):
        return ["0","Any"]
    end
    return function_call(s,name,class_arguments(s,combined,declaration,0))
end
function class_declaration(s,node):
    name = node["name"]
    call store_name(s,name,rt(s,"dict_new",[],"Class:"+name,False))
    done = label(s)
    if node["condition"] != None:
        body = label(s)
        call branch_condition(s,node["condition"],body,done)
        call mark(s,body)
    end
    for member in node["body"]:
        if member["kind"] == "assign":
            receiver = load_name(s,name)
            key = string(s,member["target"]["name"])
            value = expression(s,member["value"])
            call rt(s,"dict_set",[receiver[0],key[0],boxed(s,value)],"None")
        end
    end
    call jump(s,done)
    call mark(s,done)
end
function assign(s,target,value):
    if target["kind"] == "name":
        call store_name(s,target["name"],value)
    elif target["kind"] == "index":
        collection = expression(s,target["target"])
        index = expression(s,target["index"])
        # IntArray stores raw signed words. Static Int operands prove the
        # dynamic setter's value tag check; Bool is allowed only as an index.
        # Keep normalization and bounds checking, including negative indices.
        if collection[1] == "IntArray" and index[1] in ["Int","Bool"] and value[1] == "Int":
            length = temp(s,"load("+temp(s,"add("+collection[0]+", 8)")+")")
            position = checked_sequence_index(s,index[0],length,source_error(s,"IndexError: index out of range",target))
            data = temp(s,"load("+temp(s,"add("+collection[0]+", 24)")+")")
            address = temp(s,"add("+data+", "+temp(s,"mul("+position+", 8)")+")")
            call store(s,"Int64",value[0],address)
            return None
        end
        if collection[1] == "List" and index[1] in ["Int","Bool"]:
            length = temp(s,"load("+temp(s,"add("+collection[0]+", 8)")+")")
            position = checked_sequence_index(s,index[0],length,source_error(s,"IndexError: index out of range",target))
            data = temp(s,"load("+temp(s,"add("+collection[0]+", 24)")+")")
            address = temp(s,"add("+data+", "+temp(s,"mul("+position+", 8)")+")")
            call store(s,"Int64",boxed(s,value),address)
            return None
        end
        helper = "set"
        index_bits = integer(s,index)
        if collection[1] == "Dictionary":
            helper = "dict_set"
            index_bits = dictionary_key(s,index)
        elif not s["internal"]:
            helper = "dynamic_set"
            index_bits = boxed(s,index)
        end
        call rt(s,helper,[collection[0],index_bits,boxed(s,value)],"None")
    elif target["kind"] == "member":
        collection = expression(s,target["target"])
        call rt(s,"dict_set",[collection[0],string(s,target["name"])[0],boxed(s,value)],"None")
    else:
        Error(CompileError: "LuxIR assignment target")
    end
end
# Další znak Stringu od bajtového offsetu: vedoucí bajt a navazující bajty
# 10xxxxxx tvoří jeden znak (stejné dělení jako délka Stringu).
function for_string_step(s,target,string_mode,byte_offset,index):
    string_path = label(s)
    other_path = label(s)
    joined = label(s)
    result = temp(s,"copy(0)")
    if string_mode != "1":
        call jump_if(s,string_mode,string_path,other_path)
    else:
        call jump(s,string_path)
    end
    call mark(s,string_path)
    width = temp(s,"copy(1)")
    scan = label(s)
    grow = label(s)
    done = label(s)
    call jump(s,scan)
    call mark(s,scan)
    following = rt(s,"text_byte",[target[0],temp(s,"add("+byte_offset+", "+width+")")],"Int",False)[0]
    continuation = temp(s,"eq("+temp(s,"and("+typed(following,"Int64")+", 192)")+", 128)","w")
    call jump_if(s,continuation,grow,done)
    call mark(s,grow)
    call define(s,width,"add("+width+", 1)")
    call jump(s,scan)
    call mark(s,done)
    piece = rt(s,"text_piece",[target[0],byte_offset,width],"String",False)[0]
    call define(s,byte_offset,"add("+byte_offset+", "+width+")")
    call define(s,result,"copy("+piece+")")
    call jump(s,joined)
    call mark(s,other_path)
    if string_mode != "1":
        if target[1] == "Any" and not s["internal"]:
            other = rt(s,"iter_get",[target[0],boxed(s,[index,"Int"])],"Any")
        else:
            other = read_at(s,target,[index,"Int"],target[1])
        end
        call define(s,result,"copy("+boxed(s,other,True)+")")
    end
    call jump(s,joined)
    call mark(s,joined)
    if string_mode == "1":
        return [result,"String"]
    end
    return [result,"Any"]
end

function statements(s,body,break_target,continue_target):
    for node in body:
        if s["ended"]:
            is_label = False
            if node["kind"] == "expression":
                expression_node = node["expression"]
                if expression_node["kind"] == "call":
                    label_target = expression_node["target"]
                    is_label = label_target["kind"] == "name" and label_target.get("name", "") == "__lsl_qbe_label"
                end
            end
            if not is_label:
                continue
            end
        end
        kind = node["kind"]
        if kind == "assign":
            target = node["target"]
            if target["kind"] == "index":
                if class_validation_error(s,node,["assignment_target"]) or class_validation_error(s,target["index"],["assignment_index"]):
                    continue
                end
            elif target["kind"] == "member" and class_validation_error(s,node,["member_assignment"]):
                continue
            end
            value = expression(s,node["value"])
            if node["operator"] != "=":
                value = binary(s,node["operator"][:-1],expression(s,node["target"]),value,node)
            end
            call assign(s,node["target"],value)
        elif kind == "expression":
            call expression(s,node["expression"])
        elif kind == "return":
            value = expression(s,node["expression"])
            operand = value[0]
            if s["return_type"] == "Any" and not s["trusted"]:
                operand = boxed(s,value)
            elif s["return_type"] in ["Int","Bool"]:
                operand = integer(s,value)
            end
            if len(s["error_cleanups"]) > 0:
                call invoke(s,"qbe_error_clear",[],"None",False)
            end
            if s["runtime"] and s["inline_return"] != None:
                call define(s,s["inline_return"][0],"copy("+operand+")")
                call jump(s,s["inline_return"][1])
            else:
                call line(s,"    return "+operand)
                s["ended"] = True
            end
        elif kind == "if":
            selected = semantic.constant_if_body(node)
            if selected[0]:
                call statements(s,selected[1],break_target,continue_target)
                continue
            end
            done = label(s)
            for branch in node["branches"]:
                body_label = label(s)
                next = label(s)
                call branch_condition(s,branch[0],body_label,next)
                call mark(s,body_label)
                call statements(s,branch[1],break_target,continue_target)
                call jump(s,done)
                call mark(s,next)
            end
            call statements(s,node["otherwise"],break_target,continue_target)
            call jump(s,done)
            call mark(s,done)
        elif kind in ["while","loop"]:
            head = label(s)
            inner = label(s)
            done = label(s)
            call jump(s,head)
            call mark(s,head)
            poll_position = len(s["lines"])
            allocation_calls = s["allocation_calls"]
            call rt(s,"maybe_gc",[],"None",False)
            if kind == "while":
                call branch_condition(s,node["condition"],inner,done)
            else:
                call jump(s,inner)
            end
            call mark(s,inner)
            call statements(s,node["body"],done,head)
            call jump(s,head)
            call mark(s,done)
            call finish_loop_poll(s,poll_position,allocation_calls)
        elif kind == "for":
            iterable = node["iterable"]
            range_loop = iterable["kind"] == "call" and iterable["target"]["kind"] == "name" and iterable["target"]["name"] in ["rang","range"]
            start = "0"
            step = "1"
            # Znaménko kroku známé při překladu (1/-1), jinak 0: podmínka
            # smyčky je pak jediné porovnání místo výběru podle směru.
            step_sign = 1
            target = ["0","None"]
            string_mode = ""
            byte_offset = ""
            if range_loop:
                if class_validation_error(s,iterable,["rang_keywords"]) or class_validation_error(s,node,["rang_loop_arity"]):
                    continue
                end
                arguments = iterable["arguments"]
                if len(arguments) == 1:
                    call store_name(s,node["name"],[start,"Int"])
                    stop = checked_integer_expression(s,arguments[0])[0]
                else:
                    start = checked_integer_expression(s,arguments[0])[0]
                    call store_name(s,node["name"],[start,"Int"])
                    stop = checked_integer_expression(s,arguments[1])[0]
                    if len(arguments) == 3:
                        if class_validation_error(s,arguments[2],["rang_step"]):
                            continue
                        end
                        step_sign = constant_step_sign(arguments[2])
                        step_value = expression(s,arguments[2])
                        step = step_value[0]
                        if step_value[1] == "Any":
                            step = function_call(s,"__lsl_require_rang_step",[step_value])[0]
                        end
                        ready = label(s)
                        zero = label(s)
                        call jump_if(s,step,ready,zero)
                        call mark(s,zero)
                        call raise_error(s,"ValueError: rang step cannot be zero at "+display_path(node.get("path",s["unit"]["path"]))+":"+String(node["line"]))
                        call mark(s,ready)
                    end
                end
            else:
                target = expression(s,iterable)
                if class_validation_error(s,iterable,["iterable"]):
                    continue
                end
                if target[1] == "Dictionary":
                    target = rt(s,"dict_keys",[target[0]],"List",False)
                elif target[1] == "Any":
                    type_code = rt(s,"type_code",[target[0]],"Int",False)[0]
                    is_dict = temp(s,"eq("+typed(type_code,"Int64")+", 3)","w")
                    yes = label(s)
                    done = label(s)
                    collection = temp(s,"copy("+target[0]+")")
                    call jump_if(s,is_dict,yes,done)
                    call mark(s,yes)
                    keys = rt(s,"dict_keys",[target[0]],"List",False)
                    call define(s,collection,"copy("+keys[0]+")")
                    call jump(s,done)
                    call mark(s,done)
                    target = [collection,"Any"]
                end
                stop = rt(s,"dynamic_length",[target[0]],"Int")[0]
                # String se prochází po bajtových offsetech (UTF-8), ne přes
                # index znaku, který by pokaždé hledal od začátku (O(n²)).
                if target[1] == "String":
                    string_mode = "1"
                elif target[1] == "Any":
                    string_mode = temp(s,"eq("+typed(rt(s,"type_code",[target[0]],"Int",False)[0],"Int64")+", 1)","w")
                end
                if string_mode != "":
                    byte_offset = temp(s,"copy(0)")
                end
            end
            index = temp(s,"copy("+start+")")
            head = label(s)
            inner = label(s)
            increment = label(s)
            done = label(s)
            call jump(s,head)
            call mark(s,head)
            poll_position = len(s["lines"])
            allocation_calls = s["allocation_calls"]
            call rt(s,"maybe_gc",[],"None",False)
            if range_loop and step_sign > 0:
                condition = temp(s,"lt("+typed(index,"Int64")+", "+stop+")","w")
            elif range_loop and step_sign < 0:
                condition = temp(s,"gt("+typed(index,"Int64")+", "+stop+")","w")
            elif range_loop:
                positive = temp(s,"gt("+typed(step,"Int64")+", 0)","w")
                less = temp(s,"lt("+typed(index,"Int64")+", "+stop+")","w")
                greater = temp(s,"gt("+typed(index,"Int64")+", "+stop+")","w")
                condition = temp(s,"or("+temp(s,"and("+positive+", "+less+")","w")+", "+temp(s,"and("+temp(s,"xor("+positive+", 1)","w")+", "+greater+")","w")+")","w")
            else:
                condition = temp(s,"lt("+typed(index,"Int64")+", "+stop+")","w")
            end
            finished = done
            if range_loop:
                finished = label(s)
            end
            call jump_if(s,condition,inner,finished)
            call mark(s,inner)
            if range_loop:
                value = [index,"Int"]
                # Iteraci řídí interní počítadlo; přiřazení do proměnné v těle
                # ani vnořená smyčka se stejným jménem počet iterací nemění.
                call store_name(s,node["name"],value)
            elif string_mode != "":
                value = for_string_step(s,target,string_mode,byte_offset,index)
            else:
                if target[1] == "Any" and not s["internal"]:
                    value = rt(s,"iter_get",[target[0],boxed(s,[index,"Int"])],"Any")
                else:
                    value = read_at(s,target,[index,"Int"],target[1])
                end
            end
            if not range_loop:
                call store_name(s,node["name"],value)
            end
            call statements(s,node["body"],done,increment)
            call jump(s,increment)
            call mark(s,increment)
            call define(s,index,"add("+index+", "+step+")")
            call jump(s,head)
            if range_loop:
                # Po normálním skončení má proměnná konečnou hodnotu počítadla
                # (testované chování); break si ponechá hodnotu iterace.
                call mark(s,finished)
                call store_name(s,node["name"],[index,"Int"])
                call jump(s,done)
            end
            call mark(s,done)
            call finish_loop_poll(s,poll_position,allocation_calls)
        elif kind == "break":
            for cleanup in s["error_cleanups"]:
                if cleanup[0] == break_target:
                    call invoke(s,"qbe_error_clear",[],"None",False)
                    break
                end
            end
            call jump(s,break_target)
        elif kind == "continue":
            for cleanup in s["error_cleanups"]:
                if cleanup[1] == continue_target:
                    call invoke(s,"qbe_error_clear",[],"None",False)
                    break
                end
            end
            call jump(s,continue_target)
        elif kind == "unsafe":
            call statements(s,node["body"],break_target,continue_target)
        elif kind in ["safe","try"]:
            old = s["error"]
            failure = label(s)
            done = label(s)
            s["error"] = failure
            s["error_cleanups"].append([break_target,continue_target])
            call statements(s,node["body"],break_target,continue_target)
            call s["error_cleanups"].pop()
            if not s["ended"]:
                call invoke(s,"qbe_error_clear",[],"None",False)
            end
            call jump(s,done)
            call mark(s,failure)
            s["error"] = old
            call invoke(s,"qbe_error_catch",[],"None",False)
            if kind == "try":
                call statements(s,node["otherwise"],break_target,continue_target)
            end
            call jump(s,done)
            call mark(s,done)
        elif kind == "error":
            message_node = node["message"]
            if message_node["kind"] == "name" and message_node["name"] not in s["locals"] and message_node["name"] not in s["unit"]["variables"]:
                # Existing Error(Kind: word) syntax treats an unbound bare
                # name as diagnostic text, even if a function has that name.
                value = string(s,message_node["name"])
            else:
                value = expression(s,message_node)
            end
            if node.get("rethrow",False):
                # Znovu vyhozená zachycená chyba (lock blok): text beze změny.
                message = value
            else:
                message = rt(s,"string_concat",[string(s,node["error_kind"]+": ")[0],value[0]],"String",False)
            end
            call invoke(s,"qbe_error_set",[message[0]],"None",False)
            call jump(s,s["error"])
        elif kind == "delete":
            target = node["target"]
            if target["kind"] == "index":
                if class_validation_error(s,node,["fixed_delete","bytearray_delete","delete_target"]):
                    continue
                end
                call rt(s,"dynamic_delete",[expression(s,target["target"])[0],boxed(s,expression(s,target["index"]))],"None")
            elif target["kind"] == "member":
                if not class_validation_error(s,node,["delete_member"]):
                    call rt(s,"dict_delete",[expression(s,target["target"])[0],string(s,target["name"])[0]],"None")
                end
            else:
                if not class_validation_error(s,node,["delete_name"]):
                    call store_name(s,target["name"],["0","None"],False)
                end
            end
        elif kind == "print":
            raw = node.get("raw",False)
            for index in rang(len(node["expressions"])):
                if index > 0 and not raw:
                    call rt(s,"print_string",[string(s," ")[0]],"None",False)
                end
                value = expression(s,node["expressions"][index])
                text = stringify(s,value)
                call rt(s,"print_string",[text[0]],"None",False)
            end
            if not raw:
                call rt(s,"print_string",[string(s,chr(10))[0]],"None",False)
            end
        elif kind == "class":
            call class_declaration(s,node)
        elif kind in ["function","load","global"]:
            continue
        else:
            Error(CompileError: "LuxIR statement: "+kind)
        end
    end
end
function stringify(s,value):
    if value[1] == "String":
        return value
    elif value[1] == "Int":
        return rt(s,"int_to_string",[value[0]],"String",False)
    elif value[1] == "Float":
        return function_call(s,"__lsl_format_float",[value])
    elif value[1] == "None":
        return string(s,"None")
    elif value[1] == "Bool":
        yes = label(s)
        no = label(s)
        done = label(s)
        result = temp(s,"copy(0)")
        call jump_if(s,value[0],yes,no)
        call mark(s,yes)
        call define(s,result,"copy("+string(s,"True")[0]+")")
        call jump(s,done)
        call mark(s,no)
        call define(s,result,"copy("+string(s,"False")[0]+")")
        call jump(s,done)
        call mark(s,done)
        return [result,"String"]
    end
    return function_call(s,"__lsl_str_value",[value])
end
NATIVE = {
"native_open":["native_open","NativeLibrary"],"native_size":["native_size","Int"],"native_u64":["native_u64","Int"],"native_function":["native_function","NativeFunction"],"native_call":["native_call","Int"],"native_name_equal":["native_name_equal","Bool"],"native_close":["native_close","Int"],
"float_sum":["float_array_sum","Float"],"float_fill":["float_array_fill","None"],"float_dot":["float_array_dot","Float"],
"__lsl_pop_last":["list_pop_last","Any"],"__lsl_checked_index":["checked_index","Int"],"__lsl_parse_literal_int":["parse_literal_int","Int"],"__lsl_string_chars":["string_chars","List"],
"__lsl_run":["run","Int"],"__lsl_capture":["capture","String"],"__lsl_run_clean":["run_clean","Int"],"__lsl_capture_clean":["capture_clean","String"],"__lsl_monotonic":["clock","Float"],"__lsl_wall_time":["wall_time","Float"],
"__lsl_unbox_int":["unbox_dynamic_int","Int"],"__lsl_unbox_bool":["unbox_dynamic_bool","Bool"],"__lsl_unbox_float":["unbox_dynamic_float","Float"],"__lsl_unbox_function":["unbox_dynamic_function","Function"],
"__lsl_box_int":["box_int","Any"],"__lsl_box_bool":["box_bool","Any"],"__lsl_box_none":["box_none","Any"],
"__lsl_type_code":["type_code","Int"],"__lsl_is_heap":["is_heap_object","Bool"],"__lsl_raw_equal":["equal_any","Int"],
"__lsl_test_small_tables":["test_small_tables","None"],"__lsl_test_fd_fault":["test_fd_fault","Int"],"__lsl_object_table_mask":["object_table_mask","Int"],"__lsl_intern_table_mask":["intern_table_mask","Int"],
"__lsl_float_accumulate":["float_accumulate","Float"],"__lsl_float_candidate_bits":["float_candidate_bits","Int"],"__lsl_float_from_decimal":["decimal_bits","Int"],"__lsl_decimal_compare":["decimal_compare","Int"],"__lsl_decimal_digits_compare":["decimal_digits_compare","Int"],"__lsl_float_nearer_upper":["float_nearer_upper","Bool"],"__lsl_float_from_int":["float_from_int","Float"],"__lsl_float_to_int":["float_to_int","Int"],"__lsl_float_from_bits":["float_new","Float"],
"__lsl_text_byte_length":["text_byte_length","Int"],"__lsl_text_byte":["text_byte","Int"],"__lsl_text_byte_offset":["string_byte_offset","Int"],
"__lsl_text_piece":["text_piece","String"],"__lsl_text_scan_digits":["text_scan_digits","Int"],"__lsl_text_digits":["text_digits","Int"],"__lsl_text_split_byte":["text_split_byte","List"],
"__lsl_byte_zeros":["byte_array_zeros","ByteArray"],"__lsl_byte_copy":["byte_copy","Int"],"__lsl_text_from_bytes":["text_from_bytes","String"],
"__lsl_floatarray_bytes":["float_array_bytes","String"],"__lsl_floatarray_from_bytes":["float_array_from_bytes","FloatArray"],
"__lsl_raster_pack":["raster_pack","Int"],"__lsl_raster_copy":["raster_copy","Int"],"__lsl_raster_fill":["raster_fill","Int"],
"__lsl_data_address":["data_address","Int"],"__lsl_mem_unpack":["mem_unpack","Int"],"__lsl_mem_pack":["mem_pack","Int"],
"__lsl_fd_open":["fd_open","Int"],"__lsl_fd_read":["fd_read","Int"],"__lsl_fd_write":["fd_write","Int"],"__lsl_fd_seek":["fd_seek","Int"],"__lsl_fd_close":["fd_close","Int"],
"__lsl_fd_socket":["fd_socket","Int"],"__lsl_fd_connect":["fd_connect","Int"],"__lsl_fd_ioctl":["fd_ioctl","Int"],"__lsl_fd_mmap":["fd_mmap","Int"],"__lsl_fd_snapshot":["fd_snapshot","Int"],
"__lsl_syscall":["syscall","Int"],"__lsl_syscall6":["syscall6","Int"],"__lsl_getenv":["getenv","Any"],"__lsl_sleep":["sleep","None"],"__lsl_isatty":["isatty","Bool"],"__lsl_stdin_eof":["stdin_eof","Bool"],
"readfile":["readfile","String"],"readbytes":["readbytes","ByteArray"],"writefile":["writefile","None"],"appendfile":["appendfile","None"],"writebytes":["writebytes","None"],
"run":["run","Int"],"capture":["capture","String"],"capture_status":["capture_status","Int"],"capture_stderr":["capture_stderr","String"],
"exists":["exists","Bool"],"mkdir":["mkdir","Int"],"__lsl_mkdir_private":["mkdir_private","Int"],"unlink":["unlink","Int"],"rmdir":["rmdir","Int"],
"executable_path":["executable_path","String"],"clock":["clock","Float"],"monotonic":["clock","Float"],"wall_time":["wall_time","Float"],"gc":["gc","Int"],"chr":["chr","String"],"ord":["ord","Int"],"cpu_count":["cpu_count","Int"],"input":["input","String"],
"__lsl_new_set":["list_new","Set"],"__lsl_set_append":["list_append","None"],"__lsl_set_store":["list_set","None"]}
METHODS = {"startswith":"__lsl_startswith","endswith":"__lsl_endswith","split":"__lsl_split","join":"__lsl_join","strip":"__lsl_strip","lstrip":"__lsl_lstrip","rstrip":"__lsl_rstrip","lower":"__lsl_lower","upper":"__lsl_upper","capitalize":"__lsl_capitalize","title":"__lsl_title","replace":"__lsl_replace","find":"__lsl_find","count":"__lsl_count","index":"__lsl_list_index","extend":"__lsl_extend","insert":"__lsl_insert","remove":"__lsl_remove","reverse":"__lsl_reverse","sort":"__lsl_sort","copy":"__lsl_copy","get":"__lsl_dict_get","setdefault":"__lsl_setdefault","update":"__lsl_update","values":"__lsl_dict_values","items":"__lsl_dict_items"}
# These runtime operands are object addresses, even when a caller's local type
# is Any. The helpers perform their own receiver checks; scalar unboxing first
# can also reinterpret an unboxed integer equal to another live object's
# address. In particular an explicit unbox must receive the original value.
OBJECT_NATIVE_ARGS = {"__lsl_raster_pack":[0,1],"__lsl_raster_copy":[0,1],"__lsl_raster_fill":[0],"__lsl_set_append":[0,1],"__lsl_set_store":[0,2],"__lsl_unbox_int":[0],"__lsl_unbox_bool":[0],"__lsl_unbox_float":[0],"__lsl_unbox_function":[0],"__lsl_text_byte":[0],"__lsl_text_piece":[0],"__lsl_text_scan_digits":[0],"__lsl_text_digits":[0],"__lsl_text_split_byte":[0],"__lsl_text_from_bytes":[0],"__lsl_data_address":[0],"__lsl_byte_copy":[0,1],"__lsl_decimal_digits_compare":[0]}
function atomic_call(s,node,name):
    if name == "atomic_pause":
        return rt(s,"atomic_pause",[],"None",False)
    end
    rules = ["atomic_target","atomic_index","atomic_value"]
    if name == "atomic_cas":
        rules = ["cas_target","cas_index","cas_expected","cas_desired"]
    end
    # Keep the native backend's validation and effect order: check the slot
    # before evaluating values, then reload backing storage after those calls.
    for index in rang(len(rules)):
        if class_validation_error(s,node["arguments"][index],[rules[index]]):
            return ["0","Int"]
        end
    end
    target = expression(s,node["arguments"][0])
    index = integer(s,expression(s,node["arguments"][1]))
    length = temp(s,"load("+temp(s,"add("+target[0]+", 8)")+")")
    index = checked_sequence_index(s,index,length,source_error(s,"IndexError: index out of range",node))
    operands = []
    for argument in node["arguments"][2:]:
        operands.append(integer(s,expression(s,argument)))
    end
    data = temp(s,"load("+temp(s,"add("+target[0]+", 24)")+")")
    address = temp(s,"add("+data+", "+temp(s,"mul("+index+", 8)")+")")
    return rt(s,name,[address]+operands,"Int",False)
end

# text.split("x") s jednobajtovým literálem: String rovnou nativně, jiný typ
# přes __lsl_split (stejné chyby jako dosud).
function split_byte(s,values,byte):
    receiver = values[0]
    if receiver[1] == "String":
        return rt(s,"text_split_byte",[receiver[0],String(byte)],"List")
    end
    result = temp(s,"copy(0)")
    code = rt(s,"type_code",[receiver[0]],"Int",False)[0]
    is_string = temp(s,"eq("+typed(code,"Int64")+", 1)","w")
    fast = label(s)
    slow = label(s)
    done = label(s)
    call jump_if(s,is_string,fast,slow)
    call mark(s,fast)
    pieces = rt(s,"text_split_byte",[receiver[0],String(byte)],"List")
    call define(s,result,"copy("+pieces[0]+")")
    call jump(s,done)
    call mark(s,slow)
    pieces = function_call(s,"__lsl_split",values)
    call define(s,result,"copy("+pieces[0]+")")
    call jump(s,done)
    call mark(s,done)
    return [result,"List"]
end
function call_expression(s,node):
    target = node["target"]
    name = target.get("name","")
    if target["kind"] == "name" and name == "__lsl_symbol":
        # Adresa symbolu mimo LSL; argument se nevyhodnocuje (žádný literál).
        symbol_node = node["arguments"][0]
        if symbol_node["kind"] != "literal" or symbol_node["literal_kind"] != "string":
            Error(CompileError: "__lsl_symbol expects a string literal")
        end
        return [String(symbol_node["value"]),"Int"]
    end
    if target["kind"] == "name" and name in ["atomic_add","atomic_xchg","atomic_cas","atomic_pause"]:
        return atomic_call(s,node,name)
    end
    if target["kind"] == "name" and name in s["unit"]["classes"] and infer(s,node).startswith("Instance:"):
        return class_constructor(s,node)
    end
    if target["kind"] == "name" and name.startswith("__lsl_declared_"):
        declared = name[15:]
        value = expression(s,node["arguments"][0])
        if value[1] == declared or declared == "Any":
            return value
        end
        value = function_call(s,"__lsl_require_declared",[value,string(s,declared)])
        if declared in ["Int","Bool","Function"]:
            helpers = {"Int":"unbox_dynamic_int","Bool":"unbox_dynamic_bool","Function":"unbox_dynamic_function"}
            return rt(s,helpers[declared],[value[0]],declared,False)
        end
        return [value[0],declared]
    end
    if target["kind"] == "member":
        receiver_type = infer(s,target["target"])
        is_origin = target["target"]["kind"] == "name" and target["target"]["name"] == "origin"
        if is_origin or receiver_type.startswith("Class:") or receiver_type.startswith("Instance:"):
            return class_method(s,node)
        end
        receiver = expression(s,target["target"])
        values = [receiver]
        for arg in node["arguments"]:
            values.append(expression(s,arg))
        end
        if name == "append":
            if not s["internal"] and receiver[1] != "List":
                return rt(s,"dynamic_append",[receiver[0],boxed(s,values[1])],"None")
            end
            helper = "list_append"
            if receiver[1] == "ByteArray":
                helper = "byte_array_append"
                item = integer(s,values[1])
            elif receiver[1] == "IntArray":
                item = integer(s,values[1])
            elif receiver[1] == "FloatArray":
                item = temp(s,"load("+temp(s,"add("+values[1][0]+", 8)")+")")
            else:
                item = boxed(s,values[1])
            end
            return rt(s,helper,[receiver[0],item],"None")
        elif name == "keys":
            if not s["internal"] and receiver[1] != "Dictionary":
                return rt(s,"dynamic_dict_keys",[receiver[0]],"List")
            end
            return rt(s,"dict_keys",[receiver[0]],"List")
        elif semantic.set_method(name):
            result = function_call(s,"__lsl_set_"+name,values)
            if name in ["add","discard"]:
                return [result[0],"Int"]
            end
            return result
        elif name == "clear":
            if receiver[1] == "Any":
                return rt(s,"dynamic_clear",[receiver[0]],"None")
            elif receiver[1] == "Dictionary":
                return function_call(s,"__lsl_dict_clear",values)
            end
            result_type = "None"
            if receiver[1] == "Set":
                result_type = "Int"
            end
            return rt(s,"list_clear",[receiver[0]],result_type,False)
        elif name == "pop":
            if receiver[1] == "Any":
                return function_call(s,"__lsl_dynamic_pop"+String(len(values)-1),values)
            elif receiver[1] == "Set":
                return function_call(s,"__lsl_set_pop",values)
            elif receiver[1] == "Dictionary":
                helper = "__lsl_dict_pop"
                if len(values) == 3:
                    helper = "__lsl_dict_pop_default"
                end
                return function_call(s,helper,values)
            elif len(values) == 1:
                return function_call(s,"__lsl_pop",values)
            end
            return function_call(s,"__lsl_pop_at",values)
        elif name == "join" and receiver[1] == "String" and values[1][1] in ["List","Tuple"]:
            s["native_helpers"]["join"] = True
            return invoke(s,"lsl_join_native",[receiver[0],values[1][0]],"String")
        elif name in METHODS:
            if name == "get" and len(values) == 2:
                values.append(["0","None"])
            elif name == "split" and len(values) == 1:
                # split() bez argumentu: mezera se doplní už při překladu.
                values.append(string(s," "))
            end
            if name == "split" and len(node["arguments"]) == 1:
                separator = node["arguments"][0]
                if separator["kind"] == "literal" and separator["literal_kind"] == "string" and len(separator["value"]) == 1 and ord(separator["value"]) < 128:
                    return split_byte(s,values,ord(separator["value"]))
                end
            end
            helper = METHODS[name]
            if name == "copy":
                helper = "__lsl_dynamic_copy"
            elif name == "remove":
                helper = "__lsl_collection_remove"
            elif name == "update":
                helper = "__lsl_collection_update"
            elif name == "index" and receiver[1] == "Any":
                helper = "__lsl_dynamic_index"
            elif name == "count" and receiver[1] == "Any":
                helper = "__lsl_dynamic_count"
            elif name == "find" and receiver[1] != "String" and len(values) == 2:
                helper = "__lsl_dynamic_find"
            elif name == "find" and len(values) == 3:
                helper = "__lsl_find_offset"
            elif name == "count" and receiver[1] != "String":
                helper = "__lsl_list_count"
            elif name == "index" and receiver[1] == "String":
                helper = "__lsl_string_index"
            end
            if name == "insert" and not s["internal"] and values[1][1] not in ["Int","Bool"]:
                values[1] = rt(s,"checked_index",[boxed(s,values[1])],"Int")
            end
            result = function_call(s,helper,values)
            if receiver[1] == "Set" and name in ["remove","update"]:
                return [result[0],"Int"]
            end
            return result
        end
        Error(CompileError: "LuxIR method: "+name)
    end
    if target["kind"] == "name" and name in s["unit"]["functions"] and name not in NATIVE:
        if class_validation_error(s,node,["arguments","function_arity"]):
            return ["0","None"]
        end
        values = class_arguments(s,node,s["unit"]["functions"][name],0)
        return function_call(s,name,values)
    end
    values = []
    argument_index = 0
    for argument in node["arguments"]:
        values.append(builtin_argument(s,name,argument,argument_index))
        argument_index += 1
    end
    args = [value[0] for value in values]
    if name == "clock":
        return function_call(s,"__lsl_clock_text",[rt(s,"wall_time",[],"Float")])
    elif name in ["rang","range"] and name not in s["locals"] and name not in s["unit"]["variables"]:
        range_values = [["0","Int"],values[0],["1","Int"]]
        if len(values) >= 2:
            range_values = [values[0],values[1],["1","Int"]]
        end
        if len(values) == 3:
            range_values[2] = values[2]
        end
        return function_call(s,"__lsl_rang_list",range_values)
    elif name == "help":
        if len(values) == 0:
            values = [string(s,"")]
        end
        return function_call(s,"__lsl_help",values)
    elif name == "thread_spawn":
        return rt(s,"thread_spawn",[boxed(s,values[0],True)],"Int")
    elif name == "thread_join":
        return rt(s,"thread_join",args,"Int")
    elif name in ["run","__lsl_run","run_clean","__lsl_run_clean","capture","__lsl_capture","capture_clean","__lsl_capture_clean","capture_input","capture_input_clean","capture_stream","capture_stream_clean","capture_input_stream","capture_input_stream_clean"]:
        clean = "0"
        if name.endswith("clean"):
            clean = "1"
        end
        helper = "run"
        result_type = "Int"
        if "capture" in name:
            helper = "capture"
            result_type = "String"
        end
        input_text = "0"
        callback = "0"
        if name in ["capture_input","capture_input_clean","capture_input_stream","capture_input_stream_clean"]:
            input_text = args[2]
        end
        if name in ["capture_stream","capture_stream_clean"]:
            callback = boxed(s,values[2],True)
        elif name in ["capture_input_stream","capture_input_stream_clean"]:
            callback = boxed(s,values[3],True)
        end
        return rt(s,helper,[args[0],args[1],callback,input_text,clean],result_type)
    elif name in ["String","__lsl_declared_String"]:
        return stringify(s,values[0])
    elif name in ["Int","__lsl_declared_Int"]:
        value = values[0]
        if value[1] == "String":
            return function_call(s,"__lsl_parse_int",values)
        elif value[1] == "Float":
            return rt(s,"float_to_int",args,"Int")
        elif value[1] == "Any":
            result = function_call(s,"__lsl_int_any",values)
            # Every successful __lsl_int_any branch returns a raw integer.
            # Its legacy raw-Any branch keeps inference at Any, but probing
            # the result again would confuse numeric bits with heap pointers.
            return [result[0],"Int"]
        end
        if len(value) > 2:
            return [value[0],"Int",value[2]]
        end
        return [value[0],"Int"]
    elif name in ["Bool","__lsl_declared_Bool"]:
        condition = truth(s,values[0])
        return [temp(s,"zext32("+condition+")"),"Bool",condition]
    elif name in ["Float","__lsl_declared_Float"]:
        if values[0][1] == "Float":
            return values[0]
        elif values[0][1] == "String":
            return function_call(s,"__lsl_parse_float",values)
        elif values[0][1] == "Any":
            return function_call(s,"__lsl_float_any",values)
        end
        return rt(s,"float_from_int",[integer(s,values[0])],"Float",False)
    elif name == "type":
        if values[0][1].startswith("Class:"):
            return string(s,"Class")
        elif values[0][1].startswith("Instance:"):
            return string(s,"Instance")
        elif values[0][1] != "Any":
            return string(s,values[0][1])
        end
        return function_call(s,"__lsl_type_name",values)
    elif name == "len":
        if values[0][1] == "Any" and not s["internal"]:
            return rt(s,"dynamic_length",args,"Int")
        end
        return rt(s,"length",args,"Int")
    elif name == "arg":
        state = temp(s,"load(lsl_state)")
        stack = temp(s,"load("+temp(s,"add("+state+", 120)")+")")
        argc = temp(s,"load("+stack+")")
        idx = integer(s,values[0])
        valid = temp(s,"and("+temp(s,"ge("+typed(idx,"Int64")+", 0)","w")+", "+temp(s,"lt("+typed(idx,"Int64")+", "+argc+")","w")+")","w")
        yes = label(s)
        no = label(s)
        done = label(s)
        result = temp(s,"copy(0)")
        call jump_if(s,valid,yes,no)
        call mark(s,yes)
        offset = temp(s,"mul("+temp(s,"add("+idx+", 1)")+", 8)")
        pointer = temp(s,"load("+temp(s,"add("+stack+", "+offset+")")+")")
        text = rt(s,"from_cstring",[pointer],"String",False)
        call define(s,result,"copy("+text[0]+")")
        call jump(s,done)
        call mark(s,no)
        # arg() is nullable Any. Preserve None's dynamic tag even for the
        # internal ABI, where a raw zero otherwise prints as the integer 0.
        absent = boxed(s,["0","None"],True)
        call define(s,result,"copy("+absent+")")
        call jump(s,done)
        call mark(s,done)
        return [result,"Any"]
    elif name == "arg_count":
        state = temp(s,"load(lsl_state)")
        stack = temp(s,"load("+temp(s,"add("+state+", 120)")+")")
        return scalar(s,"load("+stack+")")
    elif name == "last_error":
        pending = invoke(s,"qbe_error_pending",[],"Any",False)
        if not s["internal"]:
            absent = label(s)
            done = label(s)
            call jump_if(s,pending[0],done,absent)
            call mark(s,absent)
            none = boxed(s,["0","None"],True)
            call define(s,pending[0],"copy("+none+")")
            call jump(s,done)
            call mark(s,done)
        end
        return pending
    elif name == "exit":
        call invoke(s,"qbe_exit",[integer(s,values[0])],"None",False)
        call line(s,"    halt")
        s["ended"] = True
        return ["0","None"]
    elif name == "check":
        yes = label(s)
        no = label(s)
        call jump_if(s,truth(s,values[0]),yes,no)
        call mark(s,no)
        message = rt(s,"string_concat",[string(s,"CheckError: ")[0],values[1][0]],"String",False)
        call invoke(s,"qbe_error_set",[message[0]],"None",False)
        call jump(s,s["error"])
        call mark(s,yes)
        return ["0","None"]
    elif name in ["IntArray","FloatArray","ByteArray"]:
        if len(args) > 0:
            # These constructors are checked casts, never iterable conversion.
            tags = {"IntArray":"13","FloatArray":"14","ByteArray":"15"}
            code = rt(s,"type_code",[boxed(s,values[0])],"Int",False)[0]
            valid = temp(s,"eq("+typed(code,"Int64")+", "+tags[name]+")","w")
            yes = label(s)
            no = label(s)
            call jump_if(s,valid,yes,no)
            call mark(s,no)
            call raise_error(s,"TypeError: "+name+"(value) only converts an existing "+name+"; create an empty one with "+name+"() and add items with append")
            call mark(s,yes)
            return [args[0],name]
        elif name == "ByteArray":
            return rt(s,"byte_array_new",[],name,False)
        end
        value = rt(s,"list_new",["0","0"],name,False)
        tag = "13"
        if name == "FloatArray":
            tag = "14"
        end
        call store(s,"Int64",tag,value[0])
        return value
    elif name in ["List","Tuple","RealArray","Dictionary","set","sorted","dedup","sum"]:
        helpers = {"List":"__lsl_list","Tuple":"__lsl_list","RealArray":"__lsl_real_array","Dictionary":"__lsl_dictionary","set":"__lsl_set","sorted":"__lsl_sorted","dedup":"__lsl_dedup","sum":"__lsl_sum"}
        if len(values) == 0:
            if name == "Dictionary":
                return rt(s,"dict_new",[],name,False)
            end
            value = rt(s,"list_new",["0","0"],name,False)
            if name in ["Tuple","RealArray","set"]:
                tags = {"Tuple":"7","RealArray":"8","set":"16"}
                call store(s,"Int64",tags[name],value[0])
                if name == "set":
                    value[1] = "Set"
                end
            end
            return value
        end
        helper = helpers[name]
        if name == "sum" and not s["internal"] and not s["trusted"]:
            helper = "__lsl_public_sum"
        end
        value = function_call(s,helper,values)
        if name in ["Tuple","RealArray"]:
            tags = {"Tuple":"7","RealArray":"8"}
            call store(s,"Int64",tags[name],value[0])
            value[1] = name
        end
        return value
    elif name == "__lsl_qbe_raw_int":
        # The migrated C ABI already carries an unboxed word. Reinterpreting
        # it must not probe the dynamic LSL heap or mistake pointer bits for
        # an LSL object. This is an internal representation primitive.
        if len(values[0]) > 2:
            return [args[0],"Int",values[0][2]]
        end
        return [args[0],"Int"]
    elif name.startswith("__lsl_qbe_call") or name.startswith("__lsl_qbe_fcall"):
        # Native internal word ABI, including boxed Float pointers. The C
        # migration supplies real code addresses, not an integer-ID dispatcher.
        kind = "Int"
        if name.startswith("__lsl_qbe_fcall"):
            kind = "Float"
        end
        return invoke(s,integer(s,values[0]),args[1:],kind)
    elif name in ["__lsl_qbe_s8","__lsl_qbe_s16","__lsl_qbe_s32","__lsl_qbe_u8","__lsl_qbe_u16","__lsl_qbe_u32"]:
        # Comparison metadata denotes an exact 0/1 value. Narrowing or
        # extending it preserves both its value and its native condition.
        if len(values[0]) > 2:
            return [args[0],"Int",values[0][2]]
        end
        operations = {"__lsl_qbe_s8":"sext8","__lsl_qbe_s16":"sext16","__lsl_qbe_s32":"sext32","__lsl_qbe_u32":"zext32"}
        value = integer(s,values[0])
        if name == "__lsl_qbe_u8":
            return scalar(s,"and("+value+", 255)")
        elif name == "__lsl_qbe_u16":
            return scalar(s,"and("+value+", 65535)")
        end
        return scalar(s,operations[name]+"("+temp(s,"copy("+value+")","w")+")")
    elif name in ["__lsl_qbe_fadd","__lsl_qbe_fsub","__lsl_qbe_fmul","__lsl_qbe_fdiv","__lsl_qbe_feq","__lsl_qbe_fne","__lsl_qbe_flt","__lsl_qbe_fle","__lsl_qbe_fgt","__lsl_qbe_fge","__lsl_qbe_uitof","__lsl_qbe_ftoui"]:
        if name == "__lsl_qbe_uitof":
            value = temp(s,"utof("+typed(integer(s,values[0]))+")","d")
            return rt(s,"float_new",[temp(s,"bitcast("+value+")")],"Float",False)
        end
        operands = []
        for value in values:
            bits = temp(s,"load("+temp(s,"add("+value[0]+", 8)")+")")
            operands.append(temp(s,"bitcast("+bits+")","d"))
        end
        if name == "__lsl_qbe_ftoui":
            return scalar(s,"ftou("+operands[0]+")")
        end
        operations = {"__lsl_qbe_fadd":"add","__lsl_qbe_fsub":"sub","__lsl_qbe_fmul":"mul","__lsl_qbe_fdiv":"div","__lsl_qbe_feq":"eq","__lsl_qbe_fne":"ne","__lsl_qbe_flt":"lt","__lsl_qbe_fle":"le","__lsl_qbe_fgt":"gt","__lsl_qbe_fge":"ge"}
        operation = operations[name]+"("+operands[0]+", "+operands[1]+")"
        if name in ["__lsl_qbe_fadd","__lsl_qbe_fsub","__lsl_qbe_fmul","__lsl_qbe_fdiv"]:
            value = temp(s,operation,"d")
            return rt(s,"float_new",[temp(s,"bitcast("+value+")")],"Float",False)
        end
        return scalar(s,"zext32("+temp(s,operation,"w")+")")
    elif name in ["__lsl_qbe_label","__lsl_qbe_jump","__lsl_qbe_branch"]:
        # Internal control-flow primitives keep C labels explicit in the LSL
        # migration without a program-counter interpreter at runtime.
        first_label = 0
        if name == "__lsl_qbe_branch":
            first_label = 1
        end
        for index in rang(first_label,len(node["arguments"])):
            argument = node["arguments"][index]
            if argument["kind"] != "literal" or argument["literal_kind"] != "number":
                Error(CompileError: "LuxIR control-flow label must be an integer literal")
            end
        end
        if name == "__lsl_qbe_branch":
            yes = "c"+String(node["arguments"][1]["value"])
            no = "c"+String(node["arguments"][2]["value"])
            call jump_if(s,truth(s,values[0]),yes,no)
            s["ended"] = True
        else:
            name_label = "c"+String(node["arguments"][0]["value"])
            call jump(s,name_label)
            if name == "__lsl_qbe_label":
                call mark(s,name_label)
            end
        end
        return ["0","Int"]
    elif name == "__lsl_qbe_alloc":
        return scalar(s,"alloc16("+integer(s,values[0])+")")
    elif name in ["__lsl_qbe_copy","__lsl_qbe_zero"]:
        size_node = node["arguments"][len(node["arguments"])-1]
        if size_node["kind"] != "literal" or size_node["literal_kind"] != "number":
            Error(CompileError: "native small copy size must be an integer literal")
        end
        count = semantic.integer_literal(size_node)
        if count < 0 or count > 128:
            Error(CompileError: "native small copy size must be between 0 and 128")
        end
        destination = integer(s,values[0])
        source = "0"
        if name == "__lsl_qbe_copy":
            source = integer(s,values[1])
        end
        offset = 0
        for width in [8,4,2,1]:
            while offset + width <= count:
                target = destination
                origin = source
                if offset != 0:
                    target = temp(s,"add("+destination+", "+String(offset)+")")
                    if name == "__lsl_qbe_copy":
                        origin = temp(s,"add("+source+", "+String(offset)+")")
                    end
                end
                loads = {8:"load",4:"load_u32",2:"load_u16",1:"load_u8"}
                stores = {8:"Int64",4:"Int32",2:"Int16",1:"Int8"}
                value = "0"
                if name == "__lsl_qbe_copy":
                    value = temp(s,loads[width]+"("+origin+")")
                end
                call store(s,stores[width],value,target)
                offset += width
            end
        end
        return [destination,"Int"]
    elif name in ["__lsl_qbe_lshr","__lsl_qbe_shl","__lsl_qbe_ashr","__lsl_qbe_udiv","__lsl_qbe_urem","__lsl_qbe_idiv","__lsl_qbe_irem","__lsl_qbe_ult","__lsl_qbe_ule"]:
        operations = {"__lsl_qbe_lshr":"shr","__lsl_qbe_shl":"shl","__lsl_qbe_ashr":"sar","__lsl_qbe_udiv":"udiv","__lsl_qbe_urem":"urem","__lsl_qbe_idiv":"div","__lsl_qbe_irem":"rem","__lsl_qbe_ult":"ult","__lsl_qbe_ule":"ule"}
        first = integer(s,values[0])
        if name in ["__lsl_qbe_ult","__lsl_qbe_ule"]:
            first = typed(first)
        end
        operation = operations[name]+"("+first+", "+integer(s,values[1])+")"
        if name in ["__lsl_qbe_ult","__lsl_qbe_ule"]:
            condition = temp(s,operation,"w")
            return [temp(s,"zext32("+condition+")"),"Int",condition]
        end
        return scalar(s,operation)
    elif name in ["__lsl_qbe_loadf32","__lsl_qbe_f32","__lsl_qbe_storef32"]:
        if name == "__lsl_qbe_loadf32":
            value = temp(s,"load("+integer(s,values[0])+")","s")
        else:
            number = values[0]
            if name == "__lsl_qbe_storef32":
                number = values[1]
            end
            bits = temp(s,"load("+temp(s,"add("+number[0]+", 8)")+")")
            number_value = temp(s,"bitcast("+bits+")","d")
            value = temp(s,"ftrunc("+number_value+")","s")
        end
        if name == "__lsl_qbe_storef32":
            call store(s,"Float32",value,integer(s,values[0]))
            return ["0","Int"]
        end
        wide = temp(s,"fext("+value+")","d")
        return rt(s,"float_new",[temp(s,"bitcast("+wide+")")],"Float",False)
    elif name.startswith("__lsl_qbe_load"):
        operations = {"__lsl_qbe_load8":"load_u8","__lsl_qbe_load16":"load_u16","__lsl_qbe_load32":"load_u32","__lsl_qbe_load64":"load"}
        return scalar(s,operations[name]+"("+integer(s,values[0])+")")
    elif name.startswith("__lsl_qbe_store"):
        operations = {"__lsl_qbe_store8":"Int8","__lsl_qbe_store16":"Int16","__lsl_qbe_store32":"Int32","__lsl_qbe_store64":"Int64"}
        value = integer(s,values[1])
        call store(s,operations[name],value,integer(s,values[0]))
        return ["0","Int"]
    elif name == "__lsl_checked_index":
        return rt(s,"checked_index",[boxed(s,values[0])],"Int")
    elif name in ["__lsl_address","__lsl_raw_int"]:
        return [args[0],"Int"]
    elif name.startswith("__lsl_raw_f"):
        return raw_float(s,name,values)
    elif name == "__lsl_box_function":
        return rt(s,"box_function",[args[0],"-1"],"Any",False)
    elif name in ["popcount","trailing_zeros"]:
        number = integer(s,values[0])
        if name == "trailing_zeros":
            # popcount((x & -x) - 1), including the defined zero result 64.
            low = temp(s,"and("+number+", "+temp(s,"neg("+number+")")+")")
            number = temp(s,"sub("+low+", 1)")
        end
        number = temp(s,"sub("+number+", "+temp(s,"and("+temp(s,"shr("+number+", 1)")+", 6148914691236517205)")+")")
        number = temp(s,"add("+temp(s,"and("+number+", 3689348814741910323)")+", "+temp(s,"and("+temp(s,"shr("+number+", 2)")+", 3689348814741910323)")+")")
        number = temp(s,"and("+temp(s,"add("+number+", "+temp(s,"shr("+number+", 4)")+")")+", 1085102592571150095)")
        return scalar(s,"shr("+temp(s,"mul("+number+", 72340172838076673)")+", 56)")
    elif name == "sqrt":
        operand = values[0]
        if operand[1] not in ["Int","Bool","Float"] and not s["internal"] and not s["trusted"]:
            call rt(s,"require_numeric_value",[boxed(s,operand),"0"],"None")
        end
        if operand[1] in ["Int","Bool"]:
            operand = rt(s,"float_from_int",[operand[0]],"Float",False)
        elif operand[1] != "Float":
            operand = rt(s,"coerce_float",[operand[0]],"Float")
        end
        return rt(s,"float_sqrt",[operand[0]],"Float")
    elif name in ["float_fill","float_sum","float_dot","float_axpy","float_matmul"]:
        arrays = [0]
        if name in ["float_dot","float_matmul"]:
            arrays = [0,1]
        elif name == "float_axpy":
            arrays = [1,2]
        end
        for index in arrays:
            if values[index][1] != "FloatArray":
                code = rt(s,"type_code",[boxed(s,values[index])],"Int",False)[0]
                valid = label(s)
                invalid = label(s)
                call jump_if(s,temp(s,"eq("+typed(code,"Int64")+", 14)","w"),valid,invalid)
                call mark(s,invalid)
                call raise_error(s,"TypeError: "+name+" requires FloatArray")
                call mark(s,valid)
            end
        end
        if name in ["float_dot","float_axpy"]:
            a = values[arrays[0]][0]
            b = values[arrays[1]][0]
            left_length = temp(s,"load("+temp(s,"add("+a+", 8)")+")")
            right_length = temp(s,"load("+temp(s,"add("+b+", 8)")+")")
            bad = label(s)
            ready = label(s)
            call jump_if(s,temp(s,"ne("+typed(left_length,"Int64")+", "+right_length+")","w"),bad,ready)
            call mark(s,bad)
            call raise_error(s,"ValueError: "+name+" requires equal lengths")
            call mark(s,ready)
        end
        scalar_indices = []
        if name == "float_fill":
            scalar_indices = [1]
        elif name == "float_axpy":
            scalar_indices = [0]
        end
        for index in scalar_indices:
            if values[index][1] not in ["Float","Int","Bool"]:
                call rt(s,"require_numeric_value",[boxed(s,values[index]),"0"],"None")
                values[index] = rt(s,"coerce_float",[values[index][0]],"Float")
            end
        end
        if name == "float_fill":
            return rt(s,"float_array_fill",[values[0][0],temp(s,"bitcast("+floating(s,values[1])+")")],"None")
        elif name == "float_sum":
            return rt(s,"float_array_sum",[values[0][0]],"Float")
        elif name == "float_dot":
            return rt(s,"float_array_dot",[values[0][0],values[1][0]],"Float")
        elif name == "float_axpy":
            return rt(s,"float_array_axpy",[temp(s,"bitcast("+floating(s,values[0])+")"),values[1][0],values[2][0]],"None")
        end
        dimensions = [integer(s,values[2]),integer(s,values[3]),integer(s,values[4])]
        invalid = temp(s,"lt("+typed(dimensions[0],"Int64")+", 0)","w")
        invalid = temp(s,"or("+invalid+", "+temp(s,"lt("+typed(dimensions[1],"Int64")+", 0)","w")+")","w")
        invalid = temp(s,"or("+invalid+", "+temp(s,"lt("+typed(dimensions[2],"Int64")+", 0)","w")+")","w")
        left_length = temp(s,"load("+temp(s,"add("+values[0][0]+", 8)")+")")
        right_length = temp(s,"load("+temp(s,"add("+values[1][0]+", 8)")+")")
        invalid = temp(s,"or("+invalid+", "+temp(s,"ne("+typed(left_length,"Int64")+", "+temp(s,"mul("+dimensions[0]+", "+dimensions[1]+")")+")","w")+")","w")
        invalid = temp(s,"or("+invalid+", "+temp(s,"ne("+typed(right_length,"Int64")+", "+temp(s,"mul("+dimensions[1]+", "+dimensions[2]+")")+")","w")+")","w")
        bad = label(s)
        ready = label(s)
        call jump_if(s,invalid,bad,ready)
        call mark(s,bad)
        call raise_error(s,"ValueError: float_matmul shape does not match array lengths")
        call mark(s,ready)
        return rt(s,"float_array_matmul",[values[0][0],values[1][0]]+dimensions,"FloatArray")
    elif name == "float_zeros":
        if values[0][1] not in ["Int","Bool"] and not s["internal"] and not s["trusted"]:
            call rt(s,"require_numeric_value",[boxed(s,values[0]),"1"],"None")
        end
        count = integer(s,values[0])
        bad = label(s)
        ready = label(s)
        call jump_if(s,temp(s,"lt("+typed(count,"Int64")+", 0)","w"),bad,ready)
        call mark(s,bad)
        call raise_error(s,"ValueError: float_zeros size cannot be negative")
        call mark(s,ready)
        result = rt(s,"list_new",[count,"0"],"FloatArray",False)
        call store(s,"Int64","14",result[0])
        return result
    elif name in ["__lsl_int_zeros","__lsl_byte_zeros"]:
        count = integer(s,values[0])
        bad = label(s)
        ready = label(s)
        call jump_if(s,temp(s,"lt("+typed(count,"Int64")+", 0)","w"),bad,ready)
        call mark(s,bad)
        kind = "IntArray"
        if name == "__lsl_byte_zeros":
            kind = "ByteArray"
        end
        call raise_error(s,"ValueError: "+kind+" size cannot be negative")
        call mark(s,ready)
        if kind == "ByteArray":
            return rt(s,"byte_array_zeros",[count],kind,False)
        end
        value = rt(s,"list_new",[count,"0"],kind,False)
        call store(s,"Int64","13",value[0])
        return value
    elif name == "__lsl_typed_int":
        return [integer(s,values[0]),"Int"]
    elif name == "__lsl_typed_bool":
        return [integer(s,values[0]),"Bool"]
    elif name == "__lsl_text_byte_length":
        return scalar(s,"load("+temp(s,"add("+args[0]+", 8)")+")")
    elif name == "__lsl_float_bits":
        return scalar(s,"load("+temp(s,"add("+args[0]+", 8)")+")")
    elif name == "__lsl_float_string":
        return function_call(s,"__lsl_format_float",values)
    elif name == "__lsl_entry_source":
        return string(s,s["entry_source"])
    elif name in ["min","max"]:
        if len(values) == 1:
            return function_call(s,"__lsl_"+name,values)
        end
        result_type = values[0][1]
        if values[1][1] != result_type:
            result_type = "Any"
        end
        left = args[0]
        right = args[1]
        if result_type == "Any":
            left = boxed(s,values[0])
            right = boxed(s,values[1])
        end
        op = "<="
        if name == "max":
            op = ">="
        end
        flag = truth(s,compare(s,op,values[0],values[1]))
        yes = label(s)
        no = label(s)
        done = label(s)
        value = temp(s,"copy("+left+")")
        call jump_if(s,flag,yes,no)
        call mark(s,yes)
        call jump(s,done)
        call mark(s,no)
        call define(s,value,"copy("+right+")")
        call jump(s,done)
        call mark(s,done)
        return [value,result_type]
    elif name == "abs":
        operand = values[0]
        if operand[1] in ["Int","Bool"]:
            sign = temp(s,"sar("+operand[0]+", 63)")
            return scalar(s,"sub("+temp(s,"xor("+operand[0]+", "+sign+")")+", "+sign+")",operand[1])
        elif operand[1] == "Float":
            bits = temp(s,"load("+temp(s,"add("+operand[0]+", 8)")+")")
            return rt(s,"float_new",[temp(s,"and("+bits+", 9223372036854775807)")],"Float",False)
        end
        if not s["internal"] and not s["trusted"]:
            call rt(s,"require_numeric_value",[boxed(s,operand),"0"],"None")
        end
        helper = "abs_any"
        if s["internal"]:
            helper += "_raw"
        end
        return rt(s,helper,args,"Any")
    elif name in NATIVE:
        helper = NATIVE[name]
        native_args = List(args)
        if name.startswith("__lsl_") and name not in ["__lsl_is_heap","__lsl_type_code","__lsl_raw_equal"]:
            native_args = []
            object_arguments = OBJECT_NATIVE_ARGS.get(name,[])
            for index in rang(len(values)):
                if index in object_arguments:
                    native_args.append(values[index][0])
                else:
                    native_args.append(integer(s,values[index]))
                end
            end
        end
        if name in ["native_u64","native_function","native_name_equal"]:
            native_args[1] = integer(s,values[1])
        end
        if name == "chr":
            native_args = [integer(s,values[0])]
        end
        if name == "__lsl_new_set":
            value = rt(s,"list_new",["0","0"],"Set",False)
            call store(s,"Int64","16",value[0])
            return value
        end
        return rt(s,helper[0],native_args,helper[1])
    end
    # An indirect function pointer uses the same SysV signature as direct QBE
    # functions. Public closure ABI tagging is handled by the boundary helpers.
    callable = expression(s,target)
    address = rt(s,"unbox_dynamic_function",[callable[0]],"Int")[0]
    return invoke(s,address,[boxed(s,value) for value in values],"Any")
end
function emit_function(shared,name,declaration,callback=False):
    s = Dictionary(shared)
    s["lines"] = []
    s["needs_gc_poll"] = False
    s["allocation_calls"] = 0
    s["gc_poll_positions"] = []
    s["callees"] = {}
    s["local_may_error"] = False
    s["checked_calls"] = []
    s["counter"] = 0
    s["label"] = 0
    s["ended"] = False
    s["error"] = "error"
    s["error_cleanups"] = []
    s["scope"] = name
    s["internal"] = shared["unit"]["internal_abi"]
    s["trusted"] = s["internal"]
    s["runtime"] = shared["runtime"]
    s["inline_return"] = None
    s["inline_stack"] = []
    s["inline_counter"] = 0
    s["locals"] = {}
    s["local_conditions"] = {}
    s["types"] = Dictionary(shared["unit"]["types"])
    s["global_reads"] = shared["unit"]["global_reads"]
    s["return_type"] = "Int"
    parameters = []
    body = shared["unit"]["program"]
    symbol = "lsl_entry"
    if declaration != None:
        s["internal"] = shared["unit"]["internal_abi"] and declaration.get("internal_abi",False)
        s["trusted"] = declaration.get("internal_abi",False)
        scope = semantic.ensure_function_scope(shared["unit"],name)
        s["global_reads"] = scope["global_reads"]
        s["types"].update(scope["types"])
        s["locals"] = scope["variables"]
        s["return_type"] = shared["unit"]["function_returns"].get(name,"Any")
        parameters = ["Int64(arg"+String(i)+")" for i in rang(len(declaration["parameters"]))]
        body = declaration["body"]
        symbol = "fn"+String(shared["ids"][name])
        if s["runtime"]:
            symbol = runtime_symbol(name)
            # Runtime pracuje jen se surovými slovy (Int, adresy, bity Float).
            for local in s["locals"]:
                s["types"][local] = "Int"
            end
        end
        if callback:
            symbol = "callback"+String(shared["ids"][name])
        end
    end
    call line(s,"export function "+symbol+"("+", ".join(parameters)+") -> Int64:")
    call mark(s,"start")
    for local in s["locals"]:
        call define(s,"v"+String(s["locals"][local]),"copy(0)")
    end
    if declaration != None:
        for index in rang(len(declaration["parameters"])):
            local = declaration["parameters"][index]
            call define(s,"v"+String(s["locals"][local]),"copy(arg"+String(index)+")")
        end
    else:
        if s["internal"]:
            call rt(s,"reserve_object_table",["67108864","8388607"],"None",False)
        end
        roots_bytes = temp(s,"load(lsl_global_bytes)")
        roots_end = temp(s,"add(lsl_globals, "+roots_bytes+")")
        call rt(s,"set_global_roots",["lsl_globals",roots_end],"None",False)
        # The table bootstrap intrinsic resets registration and must precede
        # compiler-created literals when it is the first source operation.
        # Declarations and loads have no entry-time effects. Keep later calls
        # in source order and leave user functions with this name untouched.
        for index in rang(len(body)):
            startup = body[index]
            if startup["kind"] in ["function","load"]:
                continue
            end
            if startup["kind"] == "expression":
                startup_call = startup["expression"]
                if startup_call["kind"] == "call" and len(startup_call["arguments"]) == 0:
                    startup_target = startup_call["target"]
                    if startup_target["kind"] == "name" and startup_target["name"] == "__lsl_test_small_tables" and startup_target["name"] not in shared["unit"]["functions"]:
                        call expression(s,startup_call)
                        remaining = []
                        for body_index in rang(len(body)):
                            if body_index != index:
                                remaining.append(body[body_index])
                            end
                        end
                        body = remaining
                    end
                end
            end
            break
        end
        call invoke(s,"lsl_init_literals",[],"None",False)
    end
    # Constructors are complete at function/loop boundaries. Polling here
    # bounds temporary allocation without collecting half-built objects.
    if not s["runtime"]:
        call rt(s,"maybe_gc",[],"None",False)
    end
    if callback:
        values = [["arg"+String(i),"Any"] for i in rang(len(declaration["parameters"]))]
        value = function_call(s,name,values)
        call line(s,"    return "+boxed(s,value,True))
        s["ended"] = True
    else:
        call statements(s,body,"","")
    end
    if not s["ended"]:
        call line(s,"    return 0")
    end
    call mark(s,"error")
    if declaration == None:
        call rt(s,"uncaught_error",[],"None",False)
        call invoke(s,"qbe_exit",["1"],"None",False)
    end
    call line(s,"    return 0")
    call line(s,"end")
    if declaration != None and not s["needs_gc_poll"]:
        for position in s["gc_poll_positions"]:
            s["lines"][position] = ""
        end
    end
    shared["effects"][symbol] = [s["local_may_error"],s["callees"]]
    return [s["lines"],s["checked_calls"]]
end
# Desetinná čísla v runtime jsou bity binary64 v Int; výsledek zase bity.
RAW_FLOAT_BINARY = {"__lsl_raw_fadd":"add","__lsl_raw_fsub":"sub","__lsl_raw_fmul":"mul","__lsl_raw_fdiv":"div"}
RAW_FLOAT_COMPARE = {"__lsl_raw_feq":"eq","__lsl_raw_fne":"ne","__lsl_raw_flt":"lt","__lsl_raw_fle":"le","__lsl_raw_fgt":"gt","__lsl_raw_fge":"ge"}
function raw_float(s,name,values):
    if name == "__lsl_raw_fitof":
        return scalar(s,"bitcast("+temp(s,"itof("+typed(integer(s,values[0]))+")","d")+")")
    end
    operands = [temp(s,"bitcast("+typed(integer(s,value))+")","d") for value in values]
    if name in RAW_FLOAT_BINARY:
        return scalar(s,"bitcast("+temp(s,RAW_FLOAT_BINARY[name]+"("+operands[0]+", "+operands[1]+")","d")+")")
    elif name in RAW_FLOAT_COMPARE:
        condition = temp(s,RAW_FLOAT_COMPARE[name]+"("+operands[0]+", "+operands[1]+")","w")
        return [temp(s,"zext32("+condition+")"),"Int",condition]
    elif name == "__lsl_raw_fftoi":
        return scalar(s,"ftoi("+operands[0]+")")
    elif name == "__lsl_raw_fneg":
        return scalar(s,"bitcast("+temp(s,"neg("+operands[0]+")","d")+")")
    end
    Error(CompileError: "unknown raw float operation: "+name)
end
# Hodnota top-level přiřazení runtime: celočíselný konstantní výraz
# z literálů a dříve definovaných konstant.
function runtime_constant(node,known):
    kind = node["kind"]
    if kind == "literal" and node["literal_kind"] == "number":
        return semantic.integer_literal(node)
    elif kind == "name" and node["name"] in known:
        return known[node["name"]]
    elif kind == "unary" and node["operator"] == "-":
        return -runtime_constant(node["operand"],known)
    elif kind == "unary" and node["operator"] == "~":
        return ~runtime_constant(node["operand"],known)
    elif kind == "binary":
        left = runtime_constant(node["left"],known)
        right = runtime_constant(node["right"],known)
        operator = node["operator"]
        if operator == "+":
            return left + right
        elif operator == "-":
            return left - right
        elif operator == "*":
            return left * right
        elif operator == "|":
            return left | right
        elif operator == "&":
            return left & right
        elif operator == "~":
            return left ~ right
        elif operator == "<<":
            return left << right
        elif operator == ">>":
            return left >> right
        end
    end
    Error(CompileError: "runtime global needs an integer constant value (line "+String(node.get("line",0))+")")
end
# Runtime jazyka napsaný v LSL (# lsl: runtime): každá funkce je exportovaný
# symbol se svým jménem, globály jsou datové symboly, literály statické
# záznamy String. Bez lsl_entry, bez kontrol výjimek a bez bodů GC.
function generate_runtime(unit,path):
    ids = {}
    for name in unit["functions"]:
        ids[name] = len(ids)
        unit["function_returns"][name] = "Int"
        unit["function_parameters"][name] = ["Int" for parameter in unit["functions"][name]["parameters"]]
    end
    # V runtime není kde vyhodit výjimku: každá chyba validace zastaví překlad.
    for rule in unit["validation_errors"]:
        for key in unit["validation_errors"][rule]:
            entry = unit["validation_errors"][rule][key]
            Error(CompileError: "runtime "+String(key)+": "+String(entry[0])+": "+String(entry[1]))
        end
    end
    shared = {"unit":unit,"entry_source":"","ids":ids,"strings":{},"used":{},"queue":[],"effects":{},"native_helpers":{},"callbacks":{},"guarded_globals":{},"has_validation_errors":len(unit["validation_errors"]) > 0,"runtime":True,"runtime_constants":{},"runtime_tables":{},"inline_cache":{}}
    initial = {}
    skipped = {}
    for statement in unit["program"]:
        if statement["kind"] in ["function","load"]:
            continue
        elif statement["kind"] == "assign" and statement["target"]["kind"] == "name" and statement["value"]["kind"] == "list" and statement.get("internal_abi",False):
            # Tabulka runtime: seznam celočíselných konstant -> pole Int64.
            target_name = statement["target"]["name"]
            shared["runtime_tables"][target_name] = [runtime_constant(item,initial) for item in statement["value"]["items"]]
        elif statement["kind"] == "assign" and statement["target"]["kind"] == "name":
            target_name = statement["target"]["name"]
            if not statement.get("internal_abi",False):
                # Konstanty modulů mimo runtime (např. _platform): jen čísla;
                # textové hodnoty runtime nepoužívá.
                value_node = statement["value"]
                # Záporné číslo (AT_FDCWD = -100) je unární minus literálu.
                if value_node["kind"] == "unary" and value_node["operator"] == "-":
                    value_node = value_node["operand"]
                end
                if value_node["kind"] != "literal" or value_node["literal_kind"] != "number":
                    skipped[target_name] = True
                    continue
                end
            end
            initial[target_name] = runtime_constant(statement["value"],initial)
            if runtime_constant_name(target_name):
                shared["runtime_constants"][target_name] = initial[target_name]
            end
        else:
            Error(CompileError: "runtime top level allows only functions and integer constants (line "+String(statement.get("line",0))+")")
        end
    end
    call writefile(path,"ir_version \"1\""+chr(10))
    bodies = []
    for name in unit["functions"]:
        if not unit["functions"][name].get("internal_abi",False):
            continue
        end
        shared["used"][name] = True
        bodies.append(emit_function(shared,name,unit["functions"][name]))
    end
    call write_bodies(shared,path,bodies)
    data = []
    for name in shared["runtime_tables"]:
        words = [String(word) for word in shared["runtime_tables"][name]]
        if len(words) == 0:
            words = ["0"]
        end
        data.append("data "+runtime_global_symbol(name)+" align 8 = Int64("+", ".join(words)+")"+chr(10))
    end
    for name in unit["variables"]:
        if name in shared["runtime_constants"] or name in skipped or name in shared["runtime_tables"]:
            continue
        end
        symbol = runtime_global_symbol(name)
        linkage = "export data "
        if runtime_base_name(name).startswith("tls_"):
            linkage = "export thread data "
        end
        data.append(linkage+symbol+" align 8 = Int64("+String(initial.get(name,0))+")"+chr(10))
    end
    for text in shared["strings"]:
        escaped = text.replace("\\","\\\\").replace("\"","\\\"").replace(chr(10),"\\n").replace(chr(13),"\\r").replace(chr(9),"\\t").replace(chr(0),"\\0")
        length = __lsl_text_byte_length(String(text))
        data.append("data lslrt_str"+String(shared["strings"][text])+" align 8 = [Int64(1, "+String(length)+"), \""+escaped+"\", Int8(0)]"+chr(10))
    end
    call appendfile(path,"".join(data))
end
function write_bodies(shared,path,bodies):
    # Propagate possible exceptions backward through the call graph. Cycles
    # containing only native operations cannot introduce an exception.
    reverse = {}
    can_raise = {}
    pending = []
    for symbol in shared["effects"]:
        effect = shared["effects"][symbol]
        if effect[0]:
            can_raise[symbol] = True
            pending.append(symbol)
        end
        for callee in effect[1]:
            if callee not in reverse:
                reverse[callee] = []
            end
            reverse[callee].append(symbol)
        end
    end
    cursor = 0
    while cursor < len(pending):
        callee = pending[cursor]
        for caller in reverse.get(callee,[]):
            if caller not in can_raise:
                can_raise[caller] = True
                pending.append(caller)
            end
        end
        cursor += 1
    end
    for body in bodies:
        lines = body[0]
        for site in body[1]:
            position = site[0]
            callee = site[1]
            if callee in shared["effects"] and callee not in can_raise:
                lines[position] = ""
                # Retain the successor label and explicit block terminator;
                # the backend folds the now-unconditional edge during simplify.
                successor = lines[position+2]
                lines[position+1] = "    goto "+successor[0:len(successor)-2]+chr(10)
            end
        end
        call appendfile(path,"".join(lines))
    end
end
function generate(unit,path,entry_source=""):
    ids = {}
    for name in unit["functions"]:
        ids[name] = len(ids)
    end
    # Module-only variables already proved by flow need no runtime flag stores
    # in their hot loops. Flags are shared by every actual guarded reader.
    guarded_globals = Dictionary(unit["global_reads"])
    for scope in unit["function_scopes"].values():
        guarded_globals.update(scope["global_reads"])
    end
    shared = {"unit":unit,"entry_source":entry_source,"ids":ids,"strings":{},"used":{},"queue":[],"effects":{},"native_helpers":{},"callbacks":{},"guarded_globals":guarded_globals,"has_validation_errors":len(unit["validation_errors"]) > 0,"runtime":False}
    bodies = [emit_function(shared,"",None)]
    call writefile(path,"")
    cursor = 0
    while cursor < len(shared["queue"]):
        name = shared["queue"][cursor]
        call writefile(path+".phase",String(cursor)+" "+name)
        bodies.append(emit_function(shared,name,unit["functions"][name]))
        cursor += 1
        # Automatic safepoints already bound allocation. Frequent forced scans
        # retrace the same large, still-live compiler AST without reclaiming it.
        if cursor % 256 == 0:
            call gc()
        end
    end
    for name in shared["callbacks"]:
        bodies.append(emit_function(shared,name,unit["functions"][name],True))
    end
    if "join" in shared["native_helpers"]:
        bodies.append(native_join(shared))
    end
    call write_bodies(shared,path,bodies)
    bodies = None
    global_bytes = (len(unit["variables"])+len(shared["strings"]))*8
    call appendfile(path,"export data lsl_globals align 8 = zero("+String(max(8,global_bytes))+")"+chr(10)+"data lsl_global_bytes align 8 = Int64("+String(global_bytes)+")"+chr(10))
    call appendfile(path,"data lsl_global_flags align 8 = zero("+String(max(8,len(unit["variables"])))+")"+chr(10))
    initializers = ["function lsl_init_literals():"+chr(10),"start:"+chr(10)]
    for text in shared["strings"]:
        index = shared["strings"][text]
        offset = (len(unit["variables"])+index)*8
        initializers.append("    Int64(p"+String(index)+") = call rt_runtime_string_clone(str"+String(index)+")"+chr(10))
        initializers.append("    Int64(a"+String(index)+") = add(lsl_globals, "+String(offset)+")"+chr(10))
        initializers.append("    store(p"+String(index)+", a"+String(index)+")"+chr(10))
        # Previously initialized slots are already roots. Bound startup work
        # for programs containing unusually large sets of string literals.
        initializers.append("    call rt_runtime_maybe_gc()"+chr(10))
        escaped = text.replace("\\","\\\\").replace("\"","\\\"").replace(chr(10),"\\n").replace(chr(13),"\\r").replace(chr(9),"\\t").replace(chr(0),"\\0")
        # LuxIR strings contain UTF-8 bytes; LSL length counts characters.
        length = __lsl_text_byte_length(String(text))
        call appendfile(path,"data str"+String(shared["strings"][text])+" align 8 = [Int64(1, "+String(length)+"), \""+escaped+"\", Int8(0)]"+chr(10))
    end
    initializers.append("    return"+chr(10)+"end"+chr(10))
    call appendfile(path,"".join(initializers))
    return len(shared["queue"])
end
