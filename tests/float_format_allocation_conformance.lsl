# Regression for formatter candidate verification and public decimal parsing
# allocating fresh Float/String intermediates per digit. The three values cover
# fixed, signed, and large-integer spellings from the memory-growth report.
bad = 0
round = 0
while round < 100:
    negative = String(-4.5)
    fraction = String(0.5)
    large = String(9007199254740992.0)
    negative_value = Float(negative)
    fraction_value = Float(fraction)
    large_value = Float(large)
    if negative != "-4.5" or fraction != "0.5" or large != "9007199254740992.0":
        bad += 1
    elif negative_value != -4.5 or fraction_value != 0.5 or large_value != 9007199254740992.0:
        bad += 1
    end
    round += 1
end
print bad, __lsl_object_table_mask() <= 262143
