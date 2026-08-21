# LSL 0.6.3

LSL 0.6.3 je výkonnostní vydání pro celočíselné vyhledávání, parsery a další
programy s hustými podmínkami. Compiler nyní převádí celé short-circuit stromy
`and`/`or`/`not` na přímé skoky z CPU flags místo opakovaného vytváření a
testování dočasných Boolean hodnot. Staticky známé Boolean návraty zároveň
nevolají obecný runtime truthiness helper.

Přímé funkční volání předává první argument bez zbytečného `push`/`pop` a
vstupy funkcí jsou zarovnány na 32 bytů. V režimu
`# lsl: unchecked-intarray` používají složená přiřazení přímý
read-modify-write a čistý výraz s opakovaným přístupem do stejného `IntArray`
načte jeho datový ukazatel pouze jednou.

Na stejném stroji zrychlil Lumen startovní `perft 5` z mediánu přibližně
0,61–0,66 s ve verzi 0.6.2 na přibližně 0,42 s, se stále totožným výsledkem
4 865 609. Compiler, runtime i výsledné programy zůstávají pure LSL a výstupem
je statický syscall-only Linux x86_64 ELF.
