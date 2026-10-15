# lsl: internal-abi
# Celé číslo rovné dolním 32 bitům adresy živého objektu se v dynamických
# operacích (hodnoty Any ve vnitřním ABI) nesmí splést s objektem. Na
# 32bitových cílech by bez značky adres haldy (HEAP_ADDRESS_TAG) bylo přesně
# adresou objektu. Adresy objektů leží nad 2^36 (64bitové systémy: halda od
# 2^44, 32bitové a WebAssembly: značka 2^40, bare metal: alias od 192 GiB),
# mimo rozsah běžných celých čísel.
values = [12345, 67890]
low = __lsl_address(values) & 4294967295
dynamic = [low, 1]
total = dynamic[0] + dynamic[1]
print total == low + 1
mixed = [low, 2.5]
print mixed[0] + mixed[1] == Float(low) + 2.5
print len(values), values[0]
print __lsl_address(values) >= 68719476736
