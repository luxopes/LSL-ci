call __lsl_test_small_tables()
texts = ["a", "b", "c", "d", "e", "f", "g", "h", "i", "j", "k", "l"]
objects = []
for index in rang(40):
    objects.append([index])
end
object_mask = __lsl_object_table_mask()
intern_mask = __lsl_intern_table_mask()
print object_mask >= 63, intern_mask >= 15, len(objects), len(texts)
print objects[39][0], texts[11]
