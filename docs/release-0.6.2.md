# LSL 0.6.2

LSL 0.6.2 je výkonnostní údržbové vydání zaměřené na numerické a vyhledávací
programy. Typované `IntArray` čtení, zápis a iterace po kontrole mezí přistupují
přímo k raw Int64 bufferu bez pomocného runtime volání. Inference parametrů
navíc zachová typy známých volajících i přes přímou a vzájemnou rekurzi.

Pro programy, které samy dokazují platnost všech indexů, je dostupná explicitní
direktiva `# lsl: unchecked-intarray`. Vypne kontroly mezí pouze pro staticky
typované `IntArray` přístupy v dané translation unit; bez direktivy zůstává
bezpečné chování i `IndexError` beze změny. Direktiva je určena pro měřené hot
pathy a chybný index při jejím použití má nedefinované chování.
Jednoduché celočíselné indexové výrazy v tomto režimu navíc používají přímo
cílové ABI registry a neprovádějí obecný `push`/`pop` spill kolekce.

Jazyková sémantika ani veřejné ABI se nemění. Compiler a runtime zůstávají pure
LSL a generují statický syscall-only Linux x86_64 ELF.
