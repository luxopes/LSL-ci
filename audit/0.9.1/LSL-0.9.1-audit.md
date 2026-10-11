# Audit LSL 0.9.1

Commit `0928f4798a2245813f25711d50ea50577da90ade`, tag `v0.9.1`. Audit lokální, bez úprav produkčního zdrojového kódu a bez push.

První kolo: 20 skupin potvrzených problémů. Druhé kolo přidává 14 skupin, celkem 34 otevřených nálezů (AUD-091-01 až AUD-091-34). Priority jsou moje posouzení dopadu: P1 tiché špatné výsledky nebo protokolová chyba; P2 krajní numerické vstupy či nástroje. Nejde o tvrzení, že všechny chyby vznikly až v 0.9.1. Známý Float parser je zahrnut jednou. Podobné projevy hypot, mean/median, floor/ceil a HTTP statusů jsou sloučené.

37 samostatných LSL sond, 4 požadavky přes lokální TCP a jedno přímé spuštění ověřovače ELF. Negativní kontrolní testy toku proměnných byly správně odmítnuty. Nepožaduji změnu dokumentovaného modulo 2^64 pro obecné Int operace; u math.gcd/lcm upozorňuji na potřebu vymezit a hlídat matematický kontrakt.

## 1. Rozbalování přepisuje dosud nepřečtené hodnoty (P1)

Místo: `compiler/pure/parser.lsl:307`.

unpack_statements čte holder[index] až při zápisu do jednotlivých cílů. Nejdřív zachytit všechny prvky do dočasných hodnot.

Očekáváno: [2, 1].

Reprodukce:

```lsl
a = [1, 2]
a[1], a[0] = a
print a
```

Skutečnost:

```text
[1, 1]
exit=0, compile_exit=0
```

## 2. Nepřesný decimal → Float (P1)

Místo: `compiler/pure/dynamic_stdlib.lsl:1117`.

Známá chyba převodu decimal do binary64, stále v 0.9.1. Float("0.49999999999999994") chybně vrací přesně 0.5. Použít správně zaokrouhlený parser. Nejde o nově objevenou regresi.

Očekáváno: False.

Reprodukce:

```lsl
print Float("0.49999999999999994") == 0.5
```

Skutečnost:

```text
True
exit=0, compile_exit=0
```

## 3. Overflow počtu desetinných míst Float (P2)

Místo: `stdlib/math.lsl:73`.

point + places přeteče. Totéž math.trunc. Kontrolovat mezní digits před součtem; dostatečně velký kladný počet míst má ponechat číslo.

Očekáváno: 1.5.

Reprodukce:

```lsl
load math
print math.round(1.5, 9223372036854775807)
```

Skutečnost:

```text
0.0
exit=0, compile_exit=0
```

## 4. Overflow negace digits Int.MIN (P2)

Místo: `stdlib/math.lsl:122`.

-places přeteče pro -9223372036854775808; rang pak nemá průchody a jednotka zůstane 1. Explicitně ošetřit dolní mez. Float varianta s 0.015 také chybně ponechá číslo kvůli součtu.

Očekáváno: 0.

Reprodukce:

```lsl
load math
print math.round(123, -9223372036854775807 - 1)
```

Skutečnost:

```text
123
exit=0, compile_exit=0
```

## 5. round velkého Int na 10^19 tiše vrací nulu (P2)

Místo: `stdlib/math.lsl:122`.

Větev -places >= 19 ignoruje zaokrouhlení poloviny od nuly. Rozlišit -19 od menších places a zkontrolovat overflow.

Očekáváno: Overflow/ValueError: výsledek 10000000000000000000 není Int64.

Reprodukce:

```lsl
load math
print math.round(5000000000000000000, -19)
```

Skutečnost:

```text
0
exit=0, compile_exit=0
```

## 6. trunc odmítá reprezentovatelný výsledek pro Int.MIN (P2)

Místo: `stdlib/math.lsl:122`.

Paušální zákaz vstupu Int.MIN vyhodí chybu i když výsledek fits Int64. Pracovat se záporným zbytkem bez abs/negace MIN.

Očekáváno: -9223372036854775800.

Reprodukce:

```lsl
load math
print math.trunc(-9223372036854775807 - 1, -1)
```

Skutečnost:

```text
error[ValueError]: value is outside the Int range
 help: check that the value has the expected range, length or format
exit=1, compile_exit=0
```

## 7. floor/ceil převádí příliš velký Float na nesmyslný záporný Int (P1)

Místo: `stdlib/math.lsl:14,23`.

floor(1e20) → -9223372036854775808, ceil → -9223372036854775807. Před Int(number) ověřit konečnost a rozsah jako check_integral.

Očekáváno: Chyba rozsahu; nikoli záporné číslo.

Reprodukce:

```lsl
load math
print math.floor(1e20)
```

Skutečnost:

```text
-9223372036854775808
exit=0, compile_exit=0
```

## 8. exp předčasně přetéká pro konečný výsledek (P2)

Místo: `stdlib/math.lsl:305`.

Pevná mez number > 709 je příliš nízká; exp(709.5) se vejde do Float64. Použít správné meze a škálování exponentu.

Očekáváno: Přibližně 1.3549863193146328e308.

Reprodukce:

```lsl
load math
print math.exp(709.5)
```

Skutečnost:

```text
inf
exit=0, compile_exit=0
```

## 9. exp ztrácí reprezentovatelné subnormály (P2)

Místo: `stdlib/math.lsl:305`.

Pro záporné x nejdříve počítá exp(abs(x)), které přeteče, a pak 1/inf. Počítat záporný exponent přímo nebo bezpečně škálovat.

Očekáváno: Přibližně 4.47628622567513e-309.

Reprodukce:

```lsl
load math
print math.exp(-710.0)
```

Skutečnost:

```text
0.0
exit=0, compile_exit=0
```

## 10. hypot má zbytečný overflow i underflow (P2)

Místo: `stdlib/math.lsl:471`.

hypot(1e200,1e200) → inf; hypot(1e-200,1e-200) → 0.0. Škálovat největší absolutní hodnotou před umocněním.

Očekáváno: Přibližně 1.414213562373095e200.

Reprodukce:

```lsl
load math
print math.hypot(1e200, 1e200)
```

Skutečnost:

```text
inf
exit=0, compile_exit=0
```

## 11. is_close považuje NaN a různá nekonečna za blízká (P1)

Místo: `stdlib/math.lsl:477`.

NaN proti 1 → True; +inf proti 1 → True; +inf proti -inf → True. Ošetřit rovnost, NaN a inf před odečítáním a výpočtem tolerance. Základní Float porovnání NaN přitom v kontrolním testu funguje.

Očekáváno: False.

Reprodukce:

```lsl
load math
print math.is_close(0.0 / 0.0, 1.0, 1e-9, 0.0)
```

Skutečnost:

```text
True
exit=0, compile_exit=0
```

## 12. gcd může vrátit záporný výsledek (P2)

Místo: `stdlib/math.lsl:253`.

abs(Int.MIN) zůstane záporné kvůli wrap Int64. Funkce pak vrací záporné gcd. Ošetřit overflow kladného výsledku.

Očekáváno: Chyba rozsahu nebo BigInt 9223372036854775808.

Reprodukce:

```lsl
load math
print math.gcd(-9223372036854775807 - 1, 0)
```

Skutečnost:

```text
-9223372036854775808
exit=0, compile_exit=0
```

## 13. lcm tiše vrací nesprávný výsledek po overflow (P2)

Místo: `stdlib/math.lsl:264`.

lcm(Int.MAX,2) → 2. Int operace mají dokumentovaný wrap, ale matematické API tak vrací nesprávné lcm bez indikace; přidat kontrolu rozsahu jako factorial.

Očekáváno: Chyba rozsahu nebo BigInt 18446744073709551614.

Reprodukce:

```lsl
load math
print math.lcm(9223372036854775807, 2)
```

Skutečnost:

```text
2
exit=0, compile_exit=0
```

## 14. mean a median přetékají na konečných výsledcích (P2)

Místo: `stdlib/math.lsl:485,513`.

mean([1e308,1e308]) a median stejného seznamu → inf. Mezisoučet přeteče, i když výsledná hodnota je konečná. Bezpečný průměr a škálované sčítání.

Očekáváno: 1e308.

Reprodukce:

```lsl
load math
print math.mean([1e308, 1e308])
```

Skutečnost:

```text
inf
exit=0, compile_exit=0
```

## 15. sin vrací NaN pro konečný platný argument (P2)

Místo: `stdlib/math.lsl:383`.

Redukce úhlu převádí počet otoček do Int64 přes floor. Pro 1e20 je mimo rozsah; výsledný úhel rozbije Taylorovu řadu. Nutná redukce pro velké Float argumenty nebo explicitní zdokumentovaná chyba rozsahu.

Očekáváno: Přibližně -0.6452512852657808.

Reprodukce:

```lsl
load math
print math.sin(1e20)
```

Skutečnost:

```text
nan
exit=0, compile_exit=0
```

## 16. Čas odmítá zlomek poslední sekundy roku 9999 (P2)

Místo: `stdlib/time.lsl:41`.

Horní mez 253402300799.0 vylučuje poslední téměř celou sekundu. Kontrolovat rozsah do začátku roku 10000 (exkluzivně) a ošetřit zaokrouhlení.

Očekáváno: 9999-12-31T23:59:59.500000+00:00.

Reprodukce:

```lsl
load time
print time.iso8601(253402300799.5)
```

Skutečnost:

```text
error[ValueError]: time value is outside years 1..9999
 help: check that the value has the expected range, length or format
exit=1, compile_exit=0
```

## 17. HTTP odmítá platný znak tečka v názvu hlavičky (P2)

Místo: `stdlib/httpserver.lsl:190`.

X.Test: ok → HTTP 400. Implementovat token/tchar podle RFC 9110 §5.1 a §5.6.2; tečka je dokonce doporučená pro interoperabilní nové názvy.

Očekáváno: HTTP 200 pro platný požadavek.

Požadavek a odpověď jsou v `http_results.json`; server v `http_probe.lsl`.

```text
HTTP/1.1 400 Bad Request
Content-Length: 39
Content-Type: text/plain; charset=utf-8
Connection: close
X-Content-Type-Options: nosniff
Referrer-Policy: no-referrer

400 Bad Request
header name is invalid
```

## 18. HTTP ponechá nepovolený CR uvnitř hodnoty hlavičky (P1)

Místo: `stdlib/httpserver.lsl:336`.

X-Test: one\rtwo je přijat s HTTP 200 a původní hodnota je předána handleru. RFC 9110 §5.5 vyžaduje odmítnutí nebo nahrazení CR/LF/NUL. Ověřit každý field-value po rozdělení CRLF. Test prokazuje parser mismatch; neprokazuje zneužití za konkrétní proxy.

Očekáváno: Odmítnutí požadavku nebo nahrazení CR mezerou před zpracováním.

Požadavek a odpověď jsou v `http_results.json`; server v `http_probe.lsl`.

```text
HTTP/1.1 200 OK
Content-Length: 2
Content-Type: text/plain; charset=utf-8
Connection: close
X-Content-Type-Options: nosniff
Referrer-Policy: no-referrer

ok
```

## 19. HTTP posílá tělo u odpovědí, které tělo mít nesmějí (P1)

Místo: `stdlib/httpserver.lsl:556`.

Reálný socket dostal BADBODY pro 204 i 304; 204 má Content-Length: 7. RFC 9110 §15.3.5, §15.4.5 a §8.6. Centralizovat pravidla framingu pro jednotlivé statusy i stream.

Očekáváno: 204 a 304 bez těla; 204 též bez Content-Length.

Požadavek a odpověď jsou v `http_results.json`; server v `http_probe.lsl`.

```text
HTTP/1.1 204 Response
Content-Length: 7
Content-Type: text/plain; charset=utf-8
Connection: close
X-Content-Type-Options: nosniff
Referrer-Policy: no-referrer

BADBODY
```

## 20. Ověřovací nástroje nefungují z čistého release checkoutu (P2)

Místo: `tools/qbe/verify_image.py:64; tools/qbe/verify.py:118`.

verify_image.py padá před první kontrolou na build/qbe/runtime.o; skutečný runtime je compiler/qbe/runtime.o. verify.py má stejnou pevnou závislost na konci (statické potvrzení, v tomto auditu znovu celý neproběhl). Přidat explicitní runtime parametr nebo odvodit release cestu.

Očekáváno: Úspěšné spuštění s explicitním compiler/backend/build-directory.

Příkaz a traceback: `verify_image.stderr`.

## Další potvrzená nekonzistence kontraktu (nezapočtená mezi 20)

`time.parse_iso8601("0001-01-01T00:00:00+01:00")` přijme vstup a vrátí `-62135600400.0`; `time.iso8601` tento výsledek odmítne jako mimo roky 1..9999. Je potřeba rozhodnout, zda má parser přijímat širší rozsah UTC než formatter. Samotné parsování validního lokálního času nelze bez vyjasnění kontraktu označit za chybu. Reprodukce `time_parse_range.lsl`.

## Spuštění

Sondy byly kompilovány dodaným `compiler/lslc --unsafe SOURCE OUTPUT compiler/pure/luxir`. Režim unsafe povoluje také syscall knihovny; první chybu rozbalování lze reprodukovat i v safe režimu. `probe.py` a `probe_extra.py` obsahují přesné příkazy a limity. Při přesunu upravte jejich proměnnou root na checkout 0.9.1. JSON soubory obsahují stdout, stderr, exit a čas každé sondy. Numerické referenční výsledky exp/hypot/sin ověřeny proti Python math na stejném hostu; ostatní vyplývají přímo z přesné aritmetiky či kalendáře.

## HTTP specifikace

https://www.rfc-editor.org/rfc/rfc9110.html — §5.1, §5.5, §5.6.2, §8.6, §15.3.5, §15.4.5.

## Doporučené pořadí oprav

1. Snapshot všech RHS prvků před jakýmkoli zápisem při rozbalování.
2. Ochrany is_close pro NaN/inf a kontrolované převody floor/ceil.
3. HTTP validace field-value a framing odpovědí bez těla.
4. Přesný Float parser a ošetření extrémních digits.
5. Stabilní numerické algoritmy exp/hypot/statistika/redukce úhlu.
6. Časové hranice a cesty release nástrojů.

# Pokračování auditu — dalších 14 skupin

TODO obsahuje všech 34 položek. Ve druhém kole byly provedeny samostatné numerické/JSON/BigInt sondy, 20 konfigurací (včetně kontrol), dva importní merge scénáře, výkonové sondy a další tři HTTP požadavky. Nebyly měněny produkční zdroje compileru ani knihoven. Prioritám a striktním kontraktům math/mkIf lze dát vlastní rozhodnutí maintainerů; pozorované výsledky jsou doložené.

## AUD-091-21: BigInt přijímá nekánonický nulový stav (P2)

Místo: `stdlib/bigint.lsl:80`.

Konstruktor přijme {"sign":0,"digits":"5"}; text() je 0 a is_zero() True, ale absolute().text() je 5. Zkontrolovat invariant reprezentace v _parts.

Očekáváno: Odmítnout sign=0 s digits!=0 nebo normalizovat digits na 0.

```lsl
load bigint
x = bigint.BigInt({"sign": 0, "digits": "5"})
print x.text(), x.is_zero(), x.absolute().text()
```

Skutečný výstup:

```text
0 True 5
exit=0
```

## AUD-091-22: JSON odmítá platný výstup přesně na hranici 4 MiB (P2)

Místo: `stdlib/json.lsl:99`.

Bool větev odečte 5 bajtů ještě před rozlišením true/false a true refunduje až poté. ["x"*4194295,True] má přesně 4194304 bajtů, ale je odmítnut; kontrolní stejně dlouhý JSON s False projde. Odečítat skutečnou délku tokenu.

Očekáváno: Délka zakódovaného JSON 4194304.

```lsl
load json
s = "x" * 4194295
print len(json.encode([s, True]))
```

Skutečný výstup:

```text
error[JsonError]: encoded JSON exceeds 4 MiB
 help: handle expected errors with try: ... else: ... end or safe: ... end
exit=1
```

## AUD-091-23: printr obchází zákaz I/O v čisté konfiguraci (P1)

Místo: `stdlib/configure.lsl:180`.

lsl config vypíše UNEXPECTED-OUTPUT před JSON a vrátí exit 0. Nové printr chybí v zakázaných identifikátorech; synchronizovat pravidla pro všechny výstupní builtin funkce.

Očekáváno: Staticky odmítnout stejně jako print.

```lsl
printr "UNEXPECTED-OUTPUT"
config = {"value": 1}
```

Skutečný výstup:

```text
UNEXPECTED-OUTPUT{"value":1}
exit=0
```

## AUD-091-24: Čistá konfigurace přijímá ambientní hodiny a CPU vstup (P1)

Místo: `stdlib/configure.lsl:180`.

monotonic() vrátí hostitelský čas v JSON; cpu_count() také projde. Doplnit purity kontrolu podle kategorií builtinů, ne pouze historického seznamu jmen.

Očekáváno: Odmítnout ambientní vstupy podle docs/configuration.md a docs/time.md.

```lsl
config = {"stamp": monotonic()}
```

Skutečný výstup:

```text
{"stamp":1335.975355217}
exit=0
```

## AUD-091-25: Konfigurační lexer neignoruje blokové komentáře (P2)

Místo: `stdlib/configure.lsl:28`.

/* readfile("not-executed") */ chybně skončí Impure configuration identifier readfile. Sdílet lexer jazyka nebo podporovat blokové komentáře.

Očekáváno: Přijmout čistou konfiguraci s komentářem.

```lsl
/* readfile("not-executed") */
config = {"value": 1}
```

Skutečný výstup:

```text
Impure configuration identifier readfile in /workspace/scratch/602efea1b046/lsl-release-091/audit/0.9.1/config_block_comment.lsl at 1
exit=1
```

## AUD-091-26: Konfigurační lexer odmítá validní escaped a raw stringy (P2)

Místo: `stdlib/configure.lsl:28`.

"a\"b" je odmítnuto jako Unterminated configuration string. Kontrola konce stringu ignoruje stav escaped. Také validní raw string s koncovým backslashem odmítá; zachovat odlišnou raw sémantiku.

Očekáváno: Přijmout validní řetězec obsahující escaped quote.

```lsl
config = {"value": "a\"b"}
```

Skutečný výstup:

```text
Unterminated configuration string in /workspace/scratch/602efea1b046/lsl-release-091/audit/0.9.1/config_escaped_quote.lsl at 1
exit=1
```

## AUD-091-27: Tabulátor vypne options i assertions; komentář vytváří falešný export (P1)

Místo: `stdlib/configure.lsl:295`.

has_export hledá substring name + " =" nebo name + "=". options/assertions s tabulátorem před = se tiše ignorují: nepravdivá assertion i missing required option skončí exit 0 s {}. Naopak # options = v komentáři vyvolá chybu neexistující proměnné. Odvozovat exporty z tokenů/AST.

Očekáváno: Nepravdivá assertion musí skončit chybou; chybějící required option také.

```lsl
assertions	= [[False, "must fail"]]
config = {}
```

Skutečný výstup:

```text
{}
exit=0
```

Kontroly se standardní mezerou chybu správně ohlásí. Tabulátor vynechá obě kontroly; komentář naopak vyvolá falešnou deklaraci. Viz results_config_extra.json.

## AUD-091-28: Float options odmítají skutečný Float (P2)

Místo: `stdlib/configure.lsl, generované dynamic_type`.

dynamic_type neobsahuje typový kód 6 (Float), proto je hodnota 1.5 označena Any a Float option/default odmítnut. Doplnit Float i regresi pro Float|None.

Očekáváno: Přijmout Float 1.5 a výchozí Float hodnotu.

```lsl
load config
options = {"rate": config.option("Float", 1.5, "rate")}
config = {}
```

Skutečný výstup:

```text
Invalid option type rate Float Any declared in /workspace/scratch/602efea1b046/lsl-release-091/audit/0.9.1/config_float_option.lsl
exit=1
```

## AUD-091-29: Sentinel pro chybějící option koliduje s platnou Dictionary hodnotou (P2)

Místo: `stdlib/configure.lsl, missing sentinel a get_path`.

Required Dictionary option s touto hodnotou skončí Missing required option. Porovnání používá strukturální == na běžném Dictionary sentinelu. Vrátit existenci zvlášť nebo použít nezaměnitelnou identitu.

Očekáváno: Přijmout existující Dictionary hodnotu {"__missing":True}.

```lsl
load config
options = {"data": config.required("Dictionary", "data")}
config = {"data": {"__missing": True}}
```

Skutečný výstup:

```text
Missing required option data declared in /workspace/scratch/602efea1b046/lsl-release-091/audit/0.9.1/config_missing_sentinel.lsl
exit=1
```

## AUD-091-30: mkIf(False, ...) v List nevynechá položku (P2)

Místo: `stdlib/configure.lsl, materialize List větev`.

Výsledek je {"items":[1,{"__omit":true},3]}; interní omit marker uniká do uživatelského JSON. Stejnou filtraci jako u Dictionary použít i pro List, nebo výslovně omezit a zdokumentovat kontrakt mkIf.

Očekáváno: {"items":[1,3]}.

```lsl
load config
config = {"items": [1, config.mkIf(False, 2), 3]}
```

Skutečný výstup:

```text
{"items":[1,{"__omit":true},3]}
exit=0
```

## AUD-091-31: Průchod String a validace dlouhých řetězců mají kvadratický čas (P1)

Místo: `compiler/pure/heap_runtime_linux_x86_64.lsl:2270,2309; stdlib/lconf.lsl:11`.

10k/20k/40k ASCII znaků: for c in x 0.146/0.591/2.273 s; lconf.valid_dependency 0.307/1.232/4.887 s. Byte kontrola 40k znaků 0.0012 s, 1 MiB 0.0122 s. String index volá runtime_length a znovu hledá znak od počátku. Iterovat byte offsetem s UTF-8 dekódováním a cache délky; zachovat Unicode sémantiku. lconf.encode pro 1MiB jméno překročilo 20s limit; to není důkaz chyby formátu.

Očekáváno: Lineární postup po UTF-8 codepointech, nikoli opakované procházení prefixu.

```lsl
n = Int(arg(1))
x = "x" * n
count = 0
if arg(2) == "bytes":
    for i in rang(__lsl_text_byte_length(x)):
        count += __lsl_text_byte(x, i) // 120
    end
else:
    for c in x:
        count += 1
    end
end
print count
```

Plná měření: string_iteration_performance.json. Podíl tohoto problému na selfhost kompilaci nebyl profilován.

## AUD-091-32: HTTP request-line přijímá neplatnou metodu i control znak v targetu (P1)

Místo: `stdlib/httpserver.lsl:336`.

Metoda G\tET i target /one\rtwo jsou přijaty s 200 a nezměněné předány handleru. Validovat method token a request-target podle RFC 9112 §3.1/3.2. Nejde o pouhou toleranci whitespace oddělovačů: znak zůstává uvnitř komponenty.

Očekáváno: Odmítnout invalid request-line před zavoláním handleru.

```lsl
load httpserver, json
function handler(request):
    return json.encode({"method": request["method"], "target": request["target"], "header": request["headers"].get("x-test", "")})
end
listener = httpserver.listen_ipv4("127.0.0.1", 0, 16)
print httpserver.local_port(listener)
print httpserver.serve_listener(listener, -1, handler, 3, False)
```

Reálné socketové odpovědi: http_request_line.json. https://www.rfc-editor.org/rfc/rfc9112.html §3.1 a §3.2. Exploit proti konkrétní proxy nebyl testován.

## AUD-091-33: Merge List/Dictionary ztrácí prioritu mkForce/mkDefault (P1)

Místo: `stdlib/configure.lsl, deep_merge`.

Sloučení dvou wrapperů stejné priority vrátí holý List/Dictionary (priorita se změní na 500). Výsledek force scénáře [1,2,3]; tři mkDefault seznamy dají [1,2] místo [1,2,3]. Uchovat obal s původní prioritou ve výsledku merge.

Očekáváno: Po dvou mkForce([1])/mkForce([2]) obyčejná [3] nesmí vyhrát: [1,2].

```lsl
load config
imports = ["a.lsl", "b.lsl"]
config = {"items": [3]}
```

Skutečné výsledky: results_config_priority.json; dvě importní reprodukce config_priority_force/main.lsl a config_priority_default/main.lsl.

## AUD-091-34: Chybný default option se nekontroluje, je-li hodnota explicitně zadána (P2)

Místo: `stdlib/configure.lsl, option validation wrapper`.

config.option("Int","bad default",...) s config.port=123 projde. Default se typově kontroluje pouze při chybějící hodnotě. Validovat descriptor/default nezávisle na výsledném stromu.

Očekáváno: Odmítnout String default pro Int option podle dokumentovaného kontraktu.

```lsl
load config
options = {"port": config.option("Int", "bad default", "port")}
config = {"port": 123}
```

Skutečné výsledky: results_config_priority.json; dvě importní reprodukce config_priority_force/main.lsl a config_priority_default/main.lsl.


## Další projevy již evidované chyby Float parseru (AUD-091-02)

`Float("1."+"0"*400)` → NaN; `Float("1"+"0"*400+"e-400")` → inf. Obě čísla jsou přesně 1.0 a délka je pod veřejným limitem 4096 znaků. `json.decode("1."+"0"*400)` proto chybně ohlásí hodnotu mimo finite Float range. Nesčítáno jako další samostatné chyby.

## Otevřené ověření

Podezření na rozdíl mezi 1MiB limitem lconf.decode a chybějícím limitem encode nebylo zařazeno do potvrzených chyb: velká reprodukce narazila na kvadratickou validaci a timeout. Také signed zero v decimal math není počítáno bez vyjasnění API kontraktu. Kontrolní median nemutoval vstup; změna původního shape nemutovala Tensor; globální delete vyvolal kontrolovanou NameError.
