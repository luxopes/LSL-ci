text = "  pure LSL  "
clean = text.strip()
print clean, clean.startswith("pure"), clean.endswith("LSL"), clean.find("LSL")
parts = clean.split(" ")
print len(parts), "-".join(parts)
