load math
# Jazykové novinky 0.9.1.

# Přiřazení více proměnným.
ma_a, ma_b = 1
print "multi same", ma_a, ma_b
ma_x, ma_y = 1, 2
ma_x, ma_y = ma_y, ma_x
print "multi swap", ma_x, ma_y
ma_p, ma_q = [3, 4]
print "multi list", ma_p, ma_q
ma_data = (5, "six")
ma_m, ma_n = ma_data
print "multi tuple", ma_m, ma_n
ma_s, ma_t = "text"
print "multi string", ma_s, ma_t
ma_items = [0, 0, 0]
ma_items[0], ma_items[2] = 7, 9
print "multi index", ma_items
ma_d = {}
ma_d["a"], ma_d["b"] = "x", "y"
print "multi dict", ma_d["a"], ma_d["b"]
function multi_assign_sum(value):
    first, second = value
    return first + second
end
print "multi function", multi_assign_sum(2), multi_assign_sum([3, 4])
ma_three = [1, 2, 3]
try:
    ma_e, ma_f = ma_three
else:
    print "multi mismatch", last_error()
end

# split() bez argumentu dělí podle mezery.
print "split default", "a b  c".split()
print "split explicit", "x,y".split(",")
function split_any(value):
    return value.split()
end
print "split any", split_any("one two")

# Vnořené for se stejnou proměnnou mají nezávislá počítadla.
nest_outer = 0
for nest_i in rang(3):
    for nest_i in rang(2):
        nest_i = nest_i
    end
    nest_outer += 1
end
print "nested outer", nest_outer
nest_count = 0
for nest_i in rang(100):
    for nest_i in rang(10):
        nest_count += 1
    end
end
print "nested count", nest_count
nest_seen = []
for nest_k in rang(4):
    nest_k = nest_k * 10
    call nest_seen.append(nest_k)
end
print "body assignment", nest_seen
nest_flow = []
for nest_j in rang(5):
    if nest_j == 1:
        continue
    end
    for nest_j in rang(3):
        if nest_j == 1:
            break
        end
    end
    if len(nest_flow) == 3:
        break
    end
    call nest_flow.append(nest_j)
end
print "nested flow", nest_flow

# Rozbalování položek v for.
unpack_data = [(1, 2.5), (3, 4.0)]
unpack_total = 0.0
for unpack_x, unpack_target in unpack_data:
    unpack_total += unpack_x * unpack_target
end
print "for unpack", unpack_total
for unpack_key, unpack_value in {"a": 1}.items():
    print "for items", unpack_key, unpack_value
end
function unpack_nested():
    pairs = [[1, 2], [3, 4]]
    result = 0
    for a, b in pairs:
        for c, d in pairs:
            result += a * c + b * d
        end
    end
    return result
end
print "for nested", unpack_nested()
unpack_bad = [[1, 2, 3]]
try:
    for unpack_p, unpack_q in unpack_bad:
        print unpack_p
    end
else:
    print "for mismatch", last_error()
end

/* Blokové komentáře
   přes více řádků. */
comment_value = 1 /* uvnitř výrazu */ + 2
print "block comment", comment_value
# Raw String a printr.
raw_text = r"C:\cesta\{comment_value}"
print "raw", raw_text, len(r"\n")
print r'raw "double" inside'
printr "printr:", raw_text, "|"
printr "\n"

# global x zapisuje do proměnné modulu.
global_counter = 1
function global_bump():
    global global_counter
    global_counter += 1
    return global_counter
end
print "global bump", global_bump(), global_bump(), global_counter
global_state = 0
function global_retype():
    global global_state
    global_state = "text"
end
function global_read():
    return global_state
end
call global_retype()
print "global retype", global_read(), global_state

# math.round a math.trunc s počtem desetinných míst.
print "round int", math.round(2.5), math.round(-2.5), math.trunc(-3.7)
print "round digits", math.round(2.675, 2), math.round(-2.675, 2), math.round(1.005, 2)
print "round scale", math.round(1234.5678, 1), math.round(1234.5678, 0), math.round(1234.5678, -2), math.round(-1250.0, -2)
print "trunc digits", math.trunc(2.679, 2), math.trunc(-2.679, 2), math.trunc(1999.0, -3)
print "round carry", math.round(9.995, 2), math.round(0.0004, 3), math.round(0.0005, 3), math.round(5.0, -1)
print "round extremes", math.round(1e300, 2), math.round(1.5e-10, 12), math.round(123.0, 5)
round_inf = 1e308 * 10.0
print "round special", math.round(round_inf, 2), math.round(0.0 - round_inf, 1), math.round(round_inf - round_inf, 2)
try:
    print math.round(1.5, 1.0)
else:
    print "round invalid", last_error()
end
# Int zůstává Int (přesně), NaN/Infinity/mimo rozsah bez digits je chyba.
print "round integer", math.round(123456789012345678, -3), math.round(-15, -1), math.trunc(-19, -1), math.round(14, -1), math.round(7, 2), math.round(9223372036854775807, -20)
print "round halves", math.round(0.5), math.round(1.5), math.round(-0.5), math.round(4503599627370497.0), math.trunc(-7.9)
for round_case in [round_inf - round_inf, round_inf, 0.0 - round_inf, 1e19]:
    try:
        print math.round(round_case)
    else:
        print "round error", last_error()
    end
    try:
        print math.trunc(round_case)
    else:
        print "trunc error", last_error()
    end
end
try:
    print math.round(9223372036854775807, -1)
else:
    print "round overflow", last_error()
end
try:
    print math.round("1.5")
else:
    print "round type", last_error()
end
# Dynamická rovnost Floatů odpovídá statické: IEEE NaN a 0.0 == -0.0.
equality_values = [1, 1.0, True, 0.0, -0.0, round_inf - round_inf]
print "dynamic equality", equality_values[0] == equality_values[1], equality_values[1] == 1, equality_values[3] == equality_values[4], equality_values[5] == equality_values[5], equality_values[5] != equality_values[5], equality_values[2] == equality_values[0]

# Čtení po prokazatelně neprázdné smyčce.
for da_i in rang(3):
    da_last = da_i
end
print "nonempty range", da_last, da_i
for da_item in [1, 2]:
    da_total = da_item * 10
end
print "nonempty list", da_total
function da_inside():
    for k in rang(1, 4):
        if k > 0:
            mark = k
        else:
            mark = 0
        end
    end
    return mark + k
end
print "nonempty function", da_inside()
for da_j in rang(5, 0, -1):
    da_down = da_j
    if da_j == 3:
        break
    end
end
print "nonempty break", da_down
# lock blok: vzájemné vyloučení, uvolnění po chybě, propagace chyby.
lock_guard = IntArray()
lock_guard.append(0)
lock_guard.append(0)
lock_total = IntArray()
lock_total.append(0)
function lock_work():
    for lock_i in rang(5000):
        lock lock_guard:
            lock_total[0] += 1
        end
    end
    return None
end
function lock_failing():
    lock lock_guard, 1:
        lock_values = [1]
        print lock_values[5]
    end
    return 7
end
function lock_nested_break():
    count = 0
    lock lock_guard:
        while True:
            count += 1
            if count == 3:
                break
            end
        end
    end
    return count
end
unsafe:
    lock_workers = [thread_spawn(lock_work) for lock_k in rang(4)]
    for lock_worker in lock_workers:
        call thread_join(lock_worker)
    end
end
print "lock total", lock_total[0], lock_guard[0]
try:
    call lock_failing()
else:
    print "lock propagated", last_error().startswith("IndexError: index out of range at ")
end
print "lock released", lock_guard[1], lock_nested_break(), lock_guard[0]
lock = "plain name"
print lock
lock_wrong = [1, 2]
try:
    lock lock_wrong:
        print "unreachable"
    end
else:
    print "lock target", last_error().startswith("TypeError: IntArray(value) only converts")
end
