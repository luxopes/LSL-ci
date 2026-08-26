# LSL 0.6.5

LSL 0.6.5 je výkonnostní a stabilizační vydání. Celočíselný backend drží
horké lokály v registrech, sdílí registry mezi disjunktními živými intervaly
a čisté `Int` výrazové stromy emituje Sethi–Ullmanovým pořadím bez
zásobníkových `push`/`pop`. Proměnné posuny, násobení mocninou dvou a čisté
unchecked `IntArray` operace mají přímé fast pathy včetně RMW s paměťovým
cílem. Globály jsou ve state bloku, takže je pro lokály dostupný i `r12`.

Převod `String(Float)` už při hledání nejkratší round-trip reprezentace
nevytváří heapový String a Float pro každý kandidát. Kandidát vzniká ve
stackovém bufferu a porovnává raw IEEE-754 bity; `Float(String)` během
desetinné akumulace mutuje jediný privátní Float box. Omezovaná kolekce po
formátování brání neomezenému růstu dlouhých smyček, aniž by krátkým programům
přidávala globální GC pauzu. Reprodukce 60 000 převodů klesla z přibližně
5,1 GiB na 31 MiB RSS a současně zmizela layoutově závislá korupce výpisu.

Runtime navíc používá thread-local blok pro stav výjimek a vrchol zásobníku,
uchovává záznam ukončeného workeru až do `thread_join` a přidává
`cpu_count()`, `popcount()` a `trailing_zeros()`. Dvoufázová inference
parametrů lépe specializuje rekurzivní funkce a inference návratů vidí typy
globálů.

Vydání zachovává zdrojovou kompatibilitu řady 0.6. Nový conformance test hlídá
správnost Float textu, přesný round-trip a omezený růst registru objektů;
úplná testovací sada, self-host fixed point, instalovaná kopie a audit
statických ELF artefaktů jsou součástí release kontroly.

Finální compiler fixed point je
`84adb2928bdb9115a4949906319b7845e111c165eb1f075c38754f7f3def3fca`; CLI má
SHA-256 `b76b88da7bd434006c5b63a9f84efb7b6ef719d9982107a774d9533b663b06ae`.
