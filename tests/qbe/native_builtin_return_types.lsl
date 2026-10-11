# The legacy intrinsic returns a raw Int 0/1, including direct expression use.
print __lsl_raw_equal(3, 3), __lsl_raw_equal(3, 4)
print type(__lsl_raw_equal(3, 3)), type(__lsl_raw_equal(3, 4))
x = __lsl_raw_equal(3, 3)
y = __lsl_raw_equal(3, 4)
print x, y, type(x), type(y)

function equal_result(left, right):
    return __lsl_raw_equal(left, right)
end
print equal_result(3, 3), equal_result(3, 4)
print type(equal_result(3, 3)), type(equal_result(3, 4))

# snapshot returns an address or negative errno, never a ByteArray object.
print __lsl_fd_snapshot(-1, -1, 0)
print type(__lsl_fd_snapshot(-1, -1, 0))
