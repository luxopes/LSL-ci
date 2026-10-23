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
# Od 0.10 eviduje objekty bitmapa začátků objektů, tabulka objektů už
# s počtem objektů neroste; od 0.10.5 se literály při startu kopírují bez
# internovací tabulky, malé tabulky tedy nesmí vadit ani po úklidu.
print __lsl_intern_table_mask() >= 7
print objects[39][0], texts[11], remembered()
