call __lsl_test_small_tables()
texts = ["a", "b", "c", "d", "e", "f", "g", "h", "i", "j", "k", "l"]
objects = []
for index in rang(40):
    objects.append([index])
end
# Objekty rozlišuje bitmapa začátků objektů, tabulka objektů už neroste;
# literály se při startu kopírují bez internovací tabulky (od 0.10.5),
# malé tabulky tedy nesmí vadit ani růstu haldy, ani dvanácti literálům.
print __lsl_intern_table_mask() >= 7, len(objects), len(texts)
print objects[39][0], texts[11]
