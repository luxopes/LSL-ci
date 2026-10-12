# Regrese nálezů auditu 0.9.1 (AUD-091-xx), opravené ve verzi 0.9.2.
load math
load time
load json
load bigint
load lconf

function audit_error(kind):
    return kind + " " + last_error()
end

# AUD-01: rozbalení nejdřív přečte všechny prvky.
audit_alias = [1, 2]
audit_alias[1], audit_alias[0] = audit_alias
audit_triple = [1, 2, 3]
audit_triple[2], audit_triple[0], audit_triple[1] = audit_triple
print "unpack", audit_alias, audit_triple

# AUD-02: správně zaokrouhlený převod textu na Float.
print "float", Float("0.49999999999999994") == 0.5, Float("1." + "0" * 400), Float("1" + "0" * 400 + "e-400"), json.decode("1." + "0" * 400)
print "float edges", Float("2.4703282292062327e-324"), Float("2.4703282292062328e-324"), Float("1.7976931348623157e308"), Float("1.7976931348623159e308"), Float("9007199254740993")
print "float literal", 0.1 + 0.2, 1e23, 8.98846567431158e307, 6.93147180369123816490e-01 == 0.6931471803691238
# Formát jako repr v Pythonu: nejkratší, nejbližší, přenos přes řád.
print "float repr", 1e-300, 1e-323, 2.2253e-320, 2.50254648778164e-310, 4.6678633181812096e-36, 0.040744437400417444, 3.5862982565236525e+241
# Dlouhé zápisy u poloviny mezi doubly: shoda -> sudý, lepivé číslice za 800.
audit_half = "2.4703282292062327208828439643411068618252990130716238221279284125033775363510437593264991818081799618989828234772285886546332835517796989819938739800539093906315035659515570226392290858392449105184435931802849936536152500319370457678249219365623669863658480757001585769269903706311928279558551332927834338409351978015531246597263579574622766465272827220056374006485499977096599470454020828166226237857393450736339007967761930577506740176324673600968951340535537458516661134223766678604162159680461914467291840300530057530849048765391711386591646239524912623653881879636239373280423891018672348497668235089863388587925628302755995657524455507255189313690836254779186948667994968324049705821028513185451396213837722826145437693412532098591327667236328125"
print "float half", Float(audit_half + "e-324"), Float(audit_half + "1e-324"), Float(audit_half + "0" * 900 + "e-324"), Float(audit_half + "0" * 900 + "1e-324")
audit_one = "1.00000000000000011102230246251565404236316680908203125"
print "float one", Float(audit_one), Float(audit_one + "0000001"), Float("1.00000000000000011102230246251565404236316680908203124999"), Float("-" + audit_one + "1")

# AUD-03 až 06: počet míst bez přetečení.
print "round digits", math.round(1.5, 9223372036854775807), math.round(123, -9223372036854775807 - 1), math.round(0.015, -9223372036854775807 - 1), math.trunc(-9223372036854775807 - 1, -1), math.round(-9223372036854775807 - 1, -18)
try:
    print math.round(5000000000000000000, -19)
else:
    print audit_error("round 10^19")
end

# AUD-07: floor/ceil mimo rozsah Int.
for audit_value in [1e20, -1e20, 0.0 / 0.0]:
    try:
        print math.floor(audit_value)
    else:
        print audit_error("floor")
    end
    try:
        print math.ceil(audit_value)
    else:
        print audit_error("ceil")
    end
end
print "floor ok", math.floor(-2.5), math.ceil(-2.5), math.floor(9007199254740993), math.ceil(7)

# AUD-08 až 10, 14, 15: numerika u hranic.
print "exp", math.exp(709.5) > 1.35e308, math.exp(709.5) < 1.36e308, math.exp(-710.0) > 4.47e-309, math.exp(-710.0) < 4.48e-309, math.exp(710.0), math.exp(-746.0), math.exp(0.0), math.exp(1.0)
print "hypot", math.hypot(1e200, 1e200), math.hypot(1e-200, 1e-200), math.hypot(3, 4), math.hypot(0, 0)
print "mean", math.mean([1e308, 1e308]), math.median([1e308, 1e308]), math.mean([1, 2, 3])
print "sin", math.is_close(math.sin(1e20), -0.6452512852657808, 1e-12, 0.0), math.is_close(math.cos(1e20), 0.7639704044417283, 1e-12, 0.0), math.is_close(math.sin(1e9), 0.5458434494486996, 1e-12, 0.0)
try:
    print math.sin(1.0 / 0.0)
else:
    print audit_error("sin inf")
end

# AUD-11: is_close a NaN/nekonečno.
audit_inf = 1.0 / 0.0
print "is_close", math.is_close(0.0 / 0.0, 1.0, 1e-9, 0.0), math.is_close(audit_inf, 1.0, 1e-9, 0.0), math.is_close(audit_inf, -audit_inf, 1e-9, 0.0), math.is_close(audit_inf, audit_inf, 1e-9, 0.0), math.is_close(1.0, 1.0 + 1e-12, 1e-9, 0.0)

# AUD-12, 13: gcd/lcm a přetečení.
print "gcd", math.gcd(-9223372036854775807 - 1, 6), math.gcd(12, -18), math.lcm(4, 6), math.lcm(-3, 5)
try:
    print math.gcd(-9223372036854775807 - 1, 0)
else:
    print audit_error("gcd")
end
try:
    print math.lcm(9223372036854775807, 2)
else:
    print audit_error("lcm")
end

# AUD-16, C01: rozsah času.
print "time", time.iso8601(253402300799.5), time.iso8601(-62135596800)
for audit_stamp in ["0001-01-01T00:00:00+01:00", "9999-12-31T23:59:59-01:00"]:
    try:
        print time.parse_iso8601(audit_stamp)
    else:
        print audit_error("parse")
    end
end

# AUD-21: kánonický BigInt.
try:
    print bigint.BigInt({"sign": 0, "digits": "5"}).text()
else:
    print audit_error("bigint")
end
print "bigint", bigint.BigInt({"sign": 1, "digits": "0"}).text(), bigint.BigInt({"sign": -1, "digits": "007"}).text()

# AUD-22: JSON přesně na limitu 4 MiB.
print "json limit", len(json.encode(["x" * 4194295, True]))
try:
    print len(json.encode(["x" * 4194296, True]))
else:
    print audit_error("json")
end

# AUD-31: lineární průchod Stringem a hledání.
audit_long = "a" * 200000
audit_count = 0
for audit_character in audit_long:
    audit_count += 1
end
print "string", audit_count, lconf.valid_dependency(audit_long), audit_long.find("b"), ("ab" * 50000).count("ab"), ("x" * 100000 + "€").endswith("€")
audit_text = "aÄ€😀z"
audit_parts = []
for audit_character in audit_text:
    audit_parts.append(audit_character)
end
print "utf8", audit_parts, audit_text.find("😀"), audit_text.replace("€", "-"), audit_text.startswith("aÄ")

# Typy v běhových chybách.
audit_items = [1, 2]
audit_keys = ["a", 1]
try:
    print audit_items[audit_keys[0]]
else:
    print audit_error("index")
end
