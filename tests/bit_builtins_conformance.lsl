# popcount / trailing_zeros map to POPCNT / TZCNT over raw Int values.
print popcount(0), popcount(255), popcount(-1), popcount(1 << 63)
print trailing_zeros(8), trailing_zeros(1), trailing_zeros(0), trailing_zeros(1 << 63)
mask = (1 << 40) | 5
print popcount(mask), trailing_zeros(mask), trailing_zeros(mask & (0 - mask))
