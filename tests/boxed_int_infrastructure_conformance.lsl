function verify(value):
    boxed = __lsl_box_int(__lsl_unbox_int(value))
    print __lsl_type_code(boxed), __lsl_unbox_int(boxed), __lsl_unbox_int(boxed) == value, Bool(boxed)
    call gc()
    print __lsl_unbox_int(boxed)
end

call verify(0)
call verify(1)
call verify(-1)
call verify(-9223372036854775808)
call verify(9223372036854775807)
