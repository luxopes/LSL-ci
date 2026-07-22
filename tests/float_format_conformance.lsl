function show(value):
    text = String(value)
    reparsed = Float(text)
    print text, __lsl_float_bits(value) == __lsl_float_bits(reparsed)
end

call show(0.0)
call show(-0.0)
call show(0.1)
call show(1.2345678901234567)
call show(1e20)
call show(1e300)
call show(1e-20)
call show(2.2250738585072014e-308)
call show(5e-324)
call show(3.141592653589793)
call show(-2.718281828459045)
call show(1.0 / 3.0)
call show(1.7976931348623157e308)
call show(1000000000000000.5)
call show(1.0 / 0.0)
call show(-1.0 / 0.0)
print String(0.0 / 0.0), Float("nan") != Float("nan")
print [1.25, 1e20]
