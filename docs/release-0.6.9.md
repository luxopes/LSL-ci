# LSL 0.6.9

LSL 0.6.9 je stabilizační vydání bez změny syntaxe. Zaměřuje se na korektní
veřejné dynamické ABI a na chyby, které se projevovaly až v reálných
aplikacích s callbacky, hodnotami typu `Any` a typovanými kolekcemi. Aktualizuje
živý manuál, zejména kapitolu 12; nový kopírovaný snapshot manuálu není potřeba.

Hlavní změny:

- dynamické `len`, indexace, zápis, mazání, iterace, `append`, `clear`, `keys`,
  `pop` a ostatní metody ověřují runtime typ receiveru, indexu a hodnoty před
  přístupem k objektovému layoutu;
- veřejné dynamické operátory a redukce zachovávají tagovaný výsledek pro
  `Int`, `Bool` i `Float`; oprava pokrývá také `//`, `%`, `sum`, `min`, `max`,
  řetězenou aritmetiku a kolizi číselné hodnoty s živou heap adresou;
- `List + List`, `String * Int`, smíšené numerické redukce a řazení čísel nebo
  Stringů mají kontrolovaný dispatch; nekompatibilní typy končí zachytitelnou
  `TypeError` místo čtení nesprávného layoutu;
- `ByteArray` podporuje slicing, dynamická indexace a iterace správně boxují
  prvky `IntArray`, `FloatArray` a `ByteArray` a jejich zápis kontroluje typ i
  rozsah;
- konverze `List`, `Tuple`, `RealArray` a `Dictionary` normalizují typovaná
  pole a bezpečně odmítají neiterovatelné nebo neplatné položky;
- veřejné String, file, process a binary-I/O hranice kontrolují argumenty;
  `writebytes(List)` navíc ověřuje každý byte, zatímco self-host compiler má
  oddělený důvěryhodný raw entrypoint;
- mazání chybějícího klíče Dictionary vrací `KeyError`; metody a builtiny
  kontrolují receiver i počet argumentů a `arg()` ani privátní intrinsicy už
  na chybné aritě nespadnou mimo strukturovanou diagnostiku;
- regresní corpus přidává samostatné boundary testy pro dynamické builtiny,
  kolekce, metody, numeriku, slicing, konverze a pointerové kolize.

Veřejný a interní ABI zůstávají úmyslně oddělené: aplikační `Any` hodnoty jsou
tagované, zatímco staticky známá aritmetika a self-host compiler mohou držet
raw skaláry. Privátní `__lsl_*` rozhraní nadále není sandbox ani veřejné plugin
API; bezpečnostní model je v [docs/security.md](security.md).

Vydání prošlo bitově shodným třígeneračním self-hostem, fixed-point režimem,
fast i full sadou, instalovaným compilerm, kontrolou konfigurace a auditem
všech release ELF. Kontrolní součty distribucí jsou v
`docs/developer_guides/downloads/SHA256SUMS`.
