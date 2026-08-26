# LSL 0.6.7

LSL 0.6.7 je integrační a bezpečnostní hardening vydání. Jazyková syntaxe se
nemění; aktuální manuál byl doplněn o změny procesního, HTTP a native rozhraní,
takže není potřeba nový kopírovaný snapshot celého manuálu.

Compiler nově vytváří statické PIE (`ET_DYN`) s nulovou virtuální bází. Kód je
RIP-relative, Linux při každém spuštění volí jiný load bias a druhý program
header výslovně deklaruje RW, ne-executable `PT_GNU_STACK`. Výsledný ELF má
stále jediný `R E PT_LOAD`, žádný interpreter, dynamickou sekci ani relocace.

HTTP nadále používá systémový `/usr/bin/curl`, protože jeho TLS implementace a
správa certifikátů jsou zralejší než nový vlastní TLS stack. URL, hlavičky a
tělo se ale už nepředávají v argv: validovaný curl config jde přes stdin.
Vzdálené požadavky vyžadují HTTPS (plaintext HTTP je povolen jen pro loopback),
hlavičky odmítají CR/LF injection a velikosti i timeouty mají pevné limity.
Nový builtin `capture_input_stream` umí současně posílat stdin a průběžně
zpracovávat stdout.

Process plugin ABI v1 používá u `plugin.request` JSON stdin a kontroluje také
exit status workeru. Původní argv transport je dostupný jen explicitně jako
`plugin.request_argv` pro přechod starých workerů. Nedůvěryhodný C++/CUDA kód
má běžet jako samostatný omezený worker; `native` zůstává jen pro důvěryhodné
self-contained kernely v procesu. Native loader nově kontroluje všechny
přístupy proti velikosti mapování a odmítá relocation, dynamic, chybné string,
symbol i executable-section tabulky před voláním kódu.

Test runner vytváří pro každý PID vlastní kořen, včetně compilerů, installeru,
package HOME a fixtures. CLI scratch ELF i config wrapper jsou rovněž unikátní
pro proces. Dva souběžné fast suites prošly bez kolize. Při rozdílu agregace se
hlásí první odlišný byte a zachová se `aggregate.actual` i
`aggregate.expected` v izolovaném adresáři.

Podporovaný release target zůstává Linux x86-64. LSL compiler, GC a codegen
nejsou vydávány za externě bezpečnostně auditovaný control-plane runtime:
TLS/OIDC, databáze a auditní kořen služby mají zůstat v hostitelské platformě,
zatímco LSL je vhodný pro krátkodobé sandboxované workery a testery.

Vydání prošlo třífázovým bitovým fixed pointem, plným test suite, paralelními
fast suites, instalací do čistého prefixu, živým loopback curl testem a auditem
všech generovaných ELF. Finální compiler fixed point má SHA-256
`d4dd94ec7fa3f491a58ff4cf84e49a04a399363b9aa513394c2472fe9269e894`; CLI má
SHA-256 `305f1a00d50566a76422e2a8388a4f31d6eb9619c9f94a0fd8efac44efa93e1a`.
