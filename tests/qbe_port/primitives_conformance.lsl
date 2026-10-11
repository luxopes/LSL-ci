# lsl: internal-abi
function raw_word(value):
    return __lsl_qbe_raw_int(value)
end
object = "raw C words are not dynamic LSL values"
pointer = __lsl_address(object)
check(raw_word(pointer) == pointer, "C word matching an LSL object address")
check(raw_word(0) == 0, "C zero word")
check(raw_word(-9223372036854775808) == -9223372036854775808, "C high bit")
function native_zero():
    return 19
end
function native_three(a, b, c):
    return __lsl_qbe_raw_int(a) * 100 + __lsl_qbe_raw_int(b) * 10 + __lsl_qbe_raw_int(c)
end
function native_seven(a, b, c, d, e, f, g):
    return __lsl_qbe_raw_int(a) + __lsl_qbe_raw_int(b) + __lsl_qbe_raw_int(c) + __lsl_qbe_raw_int(d) + __lsl_qbe_raw_int(e) + __lsl_qbe_raw_int(f) + __lsl_qbe_raw_int(g)
end
function native_float(value):
    return __lsl_qbe_fadd(value, 0.5)
end
check(__lsl_qbe_call0(__lsl_address(native_zero)) == 19, "native function pointer zero arguments")
check(__lsl_qbe_call3(__lsl_address(native_three), 1, 2, 3) == 123, "native function pointer arguments")
check(__lsl_qbe_call7(__lsl_address(native_seven), 1, 2, 3, 4, 5, 6, 7) == 28, "native function pointer stack argument")
check(__lsl_qbe_fcall1(__lsl_address(native_float), 1.25) == 1.75, "native function pointer boxed Float ABI")
function choose(n):
    value = 0
    call __lsl_qbe_branch(n, 1, 2)
    call __lsl_qbe_label(2)
    value = 7
    call __lsl_qbe_jump(3)
    call __lsl_qbe_label(1)
    value = 13
    call __lsl_qbe_label(3)
    return value
end
check(choose(0) == 7 and choose(1) == 13, "C control flow")
check(__lsl_qbe_udiv(-1, 2) == 9223372036854775807, "unsigned division")
check(__lsl_qbe_urem(-1, 2) == 1, "unsigned remainder")
check(__lsl_qbe_lshr(-1, 63) == 1, "logical shift")
check(__lsl_qbe_shl(3, 4) == 48, "native C left shift")
check(__lsl_qbe_ashr(-16, 2) == -4, "native C arithmetic right shift")
check(__lsl_qbe_idiv(-7, 2) == -3, "truncating division")
check(__lsl_qbe_irem(-7, 2) == -1, "C remainder")
check(__lsl_qbe_ult(1, -1) == 1, "unsigned comparison")
p = __lsl_qbe_alloc(16)
call __lsl_qbe_storef32(p, 1.25)
check(__lsl_qbe_loadf32(p) == 1.25, "float32 roundtrip")
check(__lsl_qbe_f32(1.25) == 1.25, "float32 rounding")
check(__lsl_qbe_s8(255) == -1, "sign extension int8")
check(__lsl_qbe_s16(65535) == -1, "sign extension int16")
check(__lsl_qbe_s32(4294967295) == -1, "sign extension int32")
check(__lsl_qbe_u32(-1) == 4294967295, "zero extension uint32")
copy_source = __lsl_qbe_alloc(48)
copy_target = __lsl_qbe_alloc(48)
for index in rang(48):
    call __lsl_qbe_store8(copy_source + index, index + 1)
    call __lsl_qbe_store8(copy_target + index, 165)
end
call __lsl_qbe_copy(copy_target + 1, copy_source + 1, 15)
check(__lsl_qbe_load8(copy_target) == 165 and __lsl_qbe_load8(copy_target + 16) == 165, "native copy bounds")
for index in rang(1, 16):
    check(__lsl_qbe_load8(copy_target + index) == index + 1, "unaligned native copy tail")
end
call __lsl_qbe_zero(copy_target + 1, 15)
check(__lsl_qbe_load8(copy_target) == 165 and __lsl_qbe_load8(copy_target + 16) == 165, "native zero bounds")
for index in rang(1, 16):
    check(__lsl_qbe_load8(copy_target + index) == 0, "native zero tail")
end
inf = __lsl_qbe_fdiv(1.0, 0.0)
nan = __lsl_qbe_fdiv(0.0, 0.0)
check(__lsl_qbe_fgt(inf, 1.0) == 1, "IEEE infinity")
check(__lsl_qbe_feq(nan, nan) == 0, "IEEE NaN equality")
check(__lsl_qbe_fne(nan, nan) == 1, "IEEE NaN inequality")
check(__lsl_qbe_flt(nan, 0.0) == 0, "IEEE NaN ordering")
check(__lsl_qbe_ftoui(9223372036854775808.0) == -9223372036854775808, "unsigned float conversion")
check(String(Int(2 < 3)) == "1", "comparison Int string representation")
check(String(2 < 3) == "True", "comparison Bool string representation")
check(1 < 2 < 3 and not (1 < 0 < 3), "chained comparison conditions")
condition_calls = [0]
function condition_counter(raw_value):
    condition_calls[0] = __lsl_qbe_raw_int(condition_calls[0]) + 1
    return __lsl_qbe_raw_int(raw_value) + 1
end
check(condition_counter(2) < condition_counter(3) and condition_calls[0] == 2, "comparison evaluates operands once")
function local_condition(raw_n):
    n = __lsl_qbe_raw_int(raw_n)
    selected = Int(n < 4)
    if __lsl_qbe_s8(__lsl_qbe_raw_int(selected)):
        result = 10
    else:
        result = 20
    end
    # A join, a reassignment and the next loop iteration must invalidate
    # any earlier comparison condition associated with this mutable local.
    selected = Int(n == 4)
    if selected:
        result += 3
    end
    for index in rang(5):
        selected = Int(index == n)
        if selected:
            result += 1
        end
    end
    selected = 0
    if selected:
        return -1
    end
    return result
end
for value in rang(-2, 7):
    expected = 20
    if value < 4:
        expected = 10
    end
    if value == 4:
        expected += 3
    end
    if value >= 0 and value < 5:
        expected += 1
    end
    check(local_condition(value) == expected, "mutable comparison conditions across joins and loops")
end
condition_trace = []
function trace_condition(raw_id, raw_value):
    condition_trace.append(__lsl_qbe_raw_int(raw_id))
    return __lsl_qbe_raw_int(raw_value)
end
function fail_condition():
    Error(ConditionProbe: "must be skipped")
end
selected = 0
if trace_condition(1, 0) and fail_condition():
    selected = -1
elif trace_condition(2, 1) or fail_condition():
    selected = 1
end
check(selected == 1 and String(condition_trace) == "[1, 2]", "conditional short-circuit skips error and preserves order")
loop_calls = [0]
function next_condition():
    loop_calls[0] = __lsl_qbe_raw_int(loop_calls[0]) + 1
    return __lsl_qbe_raw_int(loop_calls[0])
end
iterations = 0
while 0 < next_condition() <= 3 and trace_condition(3, 1):
    iterations += 1
end
check(iterations == 3 and loop_calls[0] == 4 and String(condition_trace) == "[1, 2, 3, 3, 3]", "chained while operands evaluate once")
if not (trace_condition(4, 0) or trace_condition(5, 0)):
    selected += 1
end
check(selected == 2 and String(condition_trace) == "[1, 2, 3, 3, 3, 4, 5]", "nested not condition")
caught_condition = False
try:
    if trace_condition(6, 1) and fail_condition():
        selected = -2
    end
else:
    caught_condition = last_error() == "ConditionProbe: must be skipped"
end
check(caught_condition and condition_trace[len(condition_trace)-1] == 6, "evaluated right condition propagates error")
check((0 or 7) == 7 and (5 and 9) == 9 and (0 and 9) == 0, "and/or value context retains operands")
print "PASS QBE primitives"
