# lsl: internal-abi
load semantic
needle = "# lsl: unchecked-intarray"
check(semantic.source_has_directive("", needle) == False, "empty source")
check(semantic.source_has_directive(needle, needle) == True, "exact source")
check(semantic.source_has_directive("žluťoučký\n" + needle, needle) == True, "UTF8 prefix")
check(semantic.source_has_directive(needle[0:len(needle)-1], needle) == False, "partial directive")
large = "a" * 2000000
check(semantic.source_has_directive(large, needle) == False, "large absent directive")
check(semantic.source_has_directive(large + needle, needle) == True, "large suffix directive")
print "PASS compiler directive search"
