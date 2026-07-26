sink = __lsl_int_zeros(6)
call __lsl_raster_fill(sink, 2, 3, 305419896)
print String(sink)
call __lsl_raster_fill(sink, 4, 99, 7)
call __lsl_raster_fill(sink, 0 - 3, 2, 9)
print String(sink)
src = __lsl_int_zeros(3)
src[0] = 16711680
src[1] = 65280
src[2] = 255
packed = __lsl_byte_zeros(16)
call __lsl_raster_pack(src, packed, 0, 4, 3)
print String(packed)
short_packed = __lsl_byte_zeros(8)
print __lsl_raster_pack(src, short_packed, 1, 0, 99)
print String(short_packed)
copied = __lsl_int_zeros(5)
call __lsl_raster_copy(copied, sink, 1, 2, 99)
print String(copied)
print __lsl_raster_fill(packed, 0, 4, 1)
print __lsl_raster_copy(copied, packed, 0, 0, 2)
print String(copied)

function raster_fill_any_boundary(arr, off, count, value):
    return __lsl_raster_fill(arr, off, count, value)
end

any_target = __lsl_int_zeros(4)
print raster_fill_any_boundary(any_target, 1, 2, 42)
print String(any_target)
