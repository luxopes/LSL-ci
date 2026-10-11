function remembered():
    return "startup literal survives"
end

call __lsl_test_small_tables()
texts = ["a", "b", "c", "d", "e", "f", "g", "h", "i", "j", "k", "l"]
objects = []
for index in rang(40):
    objects.append([index])
end
call gc()
print __lsl_object_table_mask() >= 63, __lsl_intern_table_mask() >= 15
print objects[39][0], texts[11], remembered()
