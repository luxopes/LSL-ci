# 📋 Referenční příručka všech funkcí LSL

Kompletní seznam všech funkcí, metod a built-in příkazů jazyka LSL 0.6.5.
Každá položka obsahuje název, signaturu a stručný popis.

---

## <span class="badge badge-builtin">BUILT-IN</span> 1. Built-in funkce *(dostupné všude bez importu)*

### <span class="badge badge-builtin">VÝSTUP</span> Výstup

| Funkce | Popis |
|---|---|
| `print(arg1, arg2, ...)` | Vypíše argumenty oddělené mezerou, zakončí novým řádkem. |
| `printl(text)` | Kompatibilní formátovaný výpis — výrazy v `{...}` se nahradí hodnotami. |
| `l"text {expr}"` | First-class interpolovaný String; lze přiřadit, vrátit a předat jako argument. |

### <span class="badge badge-builtin">VSTUP</span> Vstup

| Funkce | Popis |
|---|---|
| `input "výzva"` | Vypíše výzvu, přečte řádek ze stdin, vrátí String bez koncového LF. |

### <span class="badge badge-builtin">KONVERZE</span> Konverze typů

| Funkce | Popis |
|---|---|
| `Int(value)` | Převede hodnotu na celé číslo (Int). |
| `Float(value)` | Převede hodnotu na desetinné číslo (Float). |
| `String(value)` | Převede hodnotu na textový řetězec. |
| `Bool(value)` | Převede hodnotu na pravdivostní (Bool). |
| `List(value)` | Převede hodnotu na seznam, nebo vytvoří prázdný. |
| `Tuple(value)` | Převede hodnotu na Tuple, nebo vytvoří prázdný. |
| `Dictionary(value)` | Převede hodnotu na Dictionary, nebo vytvoří prázdný. |
| `IntArray()` | Vytvoří prázdné pole celých čísel (neboxované Int64). |
| `FloatArray()` | Vytvoří prázdné pole desetinných čísel (neboxované Float64). |
| `ByteArray()` | Vytvoří prázdné pole bytů (0–255). |

### <span class="badge badge-builtin">INTROSPEKCE</span> Zjištění typu

| Funkce | Popis |
|---|---|
| `type(value)` | Vrátí řetězec s názvem typu hodnoty (např. `"Int"`, `"String"`). |

### <span class="badge badge-builtin">MATEMATIKA</span> Matematické

| Funkce | Popis |
|---|---|
| `min(a, b, ...)` | Vrátí nejmenší z argumentů. |
| `max(a, b, ...)` | Vrátí největší z argumentů. |
| `sum(collection)` | Vrátí součet prvků kolekce. |
| `abs(x)` | Vrátí absolutní hodnotu čísla. |
| `sqrt(x)` | Vrátí druhou odmocninu jako Float; pro záporné číslo vyvolá `ValueError`. |
| `round(x)` | Zaokrouhlí Float na nejbližší celé číslo. |

### <span class="badge badge-builtin">BITY</span> Bitové operátory

| Operátor | Popis |
|---|---|
| `a & b` | Bitový AND dvou `Int`. |
| `a \| b` | Bitový OR dvou `Int`. |
| `a ~ b` | Bitový XOR dvou `Int` (`^` je mocnina). |
| `~a` | Bitový NOT, tedy jedničkový doplněk. |
| `a << b` | Posun vlevo; `b >= 64` dává `0`, záporné `b` vyvolá `ValueError`. |
| `a >> b` | Aritmetický posun vpravo, tedy `a // 2^b`; `b >= 64` dává `0` nebo `-1` podle znaménka. |
| `popcount(x)` | Vrátí počet jedničkových bitů raw 64bitového `Int`. |
| `trailing_zeros(x)` | Vrátí počet nulových bitů zprava; pro `0` vrací `64`. |

Operandy musí být `Int` nebo `Bool`, výsledek je vždy `Int`. Literály lze psát
s prefixem `0x`, `0o` nebo `0b`. Složená přiřazení `&=`, `|=`, `~=`, `<<=`
a `>>=` fungují stejně jako `+=`.

### <span class="badge badge-builtin">ZNAKY</span> Znaky

| Funkce | Popis |
|---|---|
| `chr(code)` | Vrátí znak (String) pro daný Unicode code point. |
| `ord(char)` | Vrátí Unicode code point prvního znaku řetězce. |

### Čas (základní)

| Funkce | Popis |
|---|---|
| `clock()` | Vrátí monotónní čas v sekundách (Float). |

### <span class="badge badge-builtin">VLÁKNA</span> Vlákna a atomické operace

| Funkce | Popis |
|---|---|
| `cpu_count()` | Vrátí počet CPU v affinity masce procesu; při chybě `1`. |
| `thread_spawn(function)` | Spustí bezargumentovou funkci ve sdíleném worker vláknu a vrátí tid, nebo `-1`. |
| `thread_join(tid)` | Počká na worker; vrátí `0`, nebo `126` pro neznámý tid. |
| `atomic_add(array, index, delta)` | Atomicky přičte `delta` do slotu `IntArray` a vrátí původní hodnotu. |
| `atomic_xchg(array, index, value)` | Atomicky vymění slot `IntArray` a vrátí původní hodnotu. |
| `atomic_cas(array, index, expected, desired)` | Provede compare-and-swap a vrátí původní hodnotu slotu. |
| `atomic_pause()` | Vloží CPU pause pro čekací spin smyčku. |

### <span class="badge badge-builtin">SOUBORY</span> Soubory (textové)

| Funkce | Popis |
|---|---|
| `readfile(path)` | Přečte celý soubor jako UTF-8 String. |
| `writefile(path, text)` | Zapíše text do souboru (přepíše existující). |
| `appendfile(path, text)` | Připojí text na konec souboru. |
| `exists(path)` | Vrátí `True`, pokud cesta existuje. |

### <span class="badge badge-builtin">BINÁRNÍ</span> Soubory (binární)

| Funkce | Popis |
|---|---|
| `readbytes(path)` | Přečte celý soubor jako ByteArray. |
| `writebytes(path, data)` | Zapíše ByteArray do souboru. |

### <span class="badge badge-builtin">FS</span> Souborový systém

| Funkce | Popis |
|---|---|
| `cwd()` | Vrátí absolutní cestu aktuálního pracovního adresáře. |
| `chdir(path)` | Změní pracovní adresář. |
| `mkdir(path)` | Vytvoří adresář. |
| `remove_path(path)` | Smaže soubor nebo prázdný adresář. |

### <span class="badge badge-builtin">PROCES</span> Proces a argumenty

| Funkce | Popis |
|---|---|
| `arg(index)` | Vrátí argument programu na dané pozici (0 = jméno programu). |
| `arg_count()` | Vrátí počet argumentů programu. |
| `args` | Globální List všech argumentů. |
| `run(program, arguments)` | Spustí program s argumenty, vrátí exit status. |
| `capture(program, arguments)` | Spustí program a vrátí jeho stdout jako String. |
| `capture_stream(program, arguments, callback)` | Spustí program a streamuje výstup po částech do callbacku. |
| `capture_input(program, arguments, input_text)` | Spustí program, pošle mu vstup, vrátí stdout. |
| `capture_status()` | Vrátí exit status posledního `capture()` volání. |
| `exit(status)` | Ukončí program s daným exit kódem. |

### <span class="badge badge-builtin">CHYBY</span> Chybové

| Funkce | Popis |
|---|---|
| `last_error()` | Vrátí text poslední chyby zachycené `safe`/`try`, nebo `None`. |

### Ostatní

| Funkce | Popis |
|---|---|
| `len(value)` | Vrátí délku řetězce, seznamu, slovníku nebo pole. |
| `help()` | Vypíše základní nápovědu. |

---

## <span class="badge badge-methods">METODY</span> 2. Metody vestavěných typů

### <span class="badge badge-methods">String</span> String

| Metoda | Popis |
|---|---|
| `s.lower()` | Vrátí řetězec s malými písmeny. |
| `s.upper()` | Vrátí řetězec s velkými písmeny. |
| `s.strip()` | Odstraní bílé znaky na začátku a konci. |
| `s.lstrip()` | Odstraní bílé znaky na začátku. |
| `s.rstrip()` | Odstraní bílé znaky na konci. |
| `s.split(separator)` | Rozdělí řetězec podle oddělovače na List. |
| `s.replace(old, new)` | Nahradí všechny výskyty `old` za `new`. |
| `s.join(list)` | Spojí seznam řetězců do jednoho, oddělené `s`. |
| `s.startswith(prefix)` | Vrátí `True`, pokud řetězec začíná na `prefix`. |
| `s.endswith(suffix)` | Vrátí `True`, pokud řetězec končí na `suffix`. |
| `s.find(sub)` | Vrátí index prvního výskytu `sub`, nebo `-1`. |
| `s.count(sub)` | Vrátí počet výskytů podřetězce `sub`. |
| `s.title()` | Vrátí řetězec s prvními písmeny slov velkými. |
| `s.capitalize()` | Vrátí řetězec s prvním písmenem velkým. |

### <span class="badge badge-methods">List</span> List

| Metoda | Popis |
|---|---|
| `lst.append(x)` | Přidá prvek na konec seznamu. |
| `lst.extend(other)` | Připojí všechny prvky jiného seznamu na konec. |
| `lst.insert(i, x)` | Vloží prvek na pozici `i`. |
| `lst.pop()` | Vrátí a odstraní poslední prvek. |
| `lst.pop(i)` | Vrátí a odstraní prvek na pozici `i`. |
| `lst.remove(x)` | Odstraní první výskyt hodnoty `x`. |
| `lst.clear()` | Smaže všechny prvky seznamu. |
| `lst.index(x)` | Vrátí index prvního výskytu hodnoty `x`. |
| `lst.count(x)` | Vrátí počet výskytů hodnoty `x`. |
| `lst.sort()` | Seřadí seznam na místě. |
| `lst.reverse()` | Obrátí pořadí prvků na místě. |
| `lst.copy()` | Vrátí mělkou kopii seznamu. |

### <span class="badge badge-methods">Dictionary</span> Dictionary

| Metoda | Popis |
|---|---|
| `d.get(key, default)` | Vrátí hodnotu pro klíč, nebo `default` (či `None`). |
| `d.keys()` | Vrátí List všech klíčů. |
| `d.values()` | Vrátí List všech hodnot. |
| `d.items()` | Vrátí List dvojic `(key, value)`. |
| `d.update(other)` | Přidá/aktualizuje klíče z jiného Dictionary. |
| `d.pop(key)` | Vrátí a odstraní hodnotu pro klíč. |
| `d.pop(key, default)` | Vrátí hodnotu nebo `default`, pokud klíč neexistuje. |
| `d.clear()` | Vyprázdní celý slovník. |
| `d.setdefault(key, default)` | Nastaví hodnotu, pokud klíč neexistuje; vrátí ji. |
| `d.copy()` | Vrátí mělkou kopii slovníku. |

### <span class="badge badge-methods">Tuple</span> Tuple

| Metoda | Popis |
|---|---|
| `t.index(x)` | Vrátí index prvního výskytu hodnoty `x`. |
| `t.count(x)` | Vrátí počet výskytů hodnoty `x`. |

### <span class="badge badge-methods">RealArray</span> RealArray

| Metoda | Popis |
|---|---|
| `a.index(x)` | Vrátí index prvního výskytu hodnoty. |
| `a.count(x)` | Vrátí počet výskytů hodnoty. |
| `a.copy()` | Vrátí kopii pole. |

### <span class="badge badge-methods">IntArray</span> IntArray

| Metoda | Popis |
|---|---|
| `a.append(x)` | Přidá celé číslo na konec pole. |
| `a.clear()` | Vyprázdní pole. |
| Podporuje: | `len()`, indexaci `[i]`, přiřazení `[i] = x`, slicing, iteraci (`for`). |

### <span class="badge badge-methods">FloatArray</span> FloatArray

| Metoda | Popis |
|---|---|
| `a.append(x)` | Přidá Float na konec pole. |
| `a.clear()` | Vyprázdní pole. |
| Podporuje: | `len()`, indexaci, přiřazení, slicing, iteraci. |

### <span class="badge badge-methods">ByteArray</span> ByteArray

| Metoda | Popis |
|---|---|
| `a.append(x)` | Přidá byte (Int 0–255) na konec pole. |
| `a.clear()` | Vyprázdní pole. |
| Podporuje: | `len()`, indexaci, přiřazení, slicing, iteraci, `readbytes()`, `writebytes()`. |

### <span class="badge badge-methods">FloatArray kernely</span> Nativní FloatArray kernely (volné funkce)

| Funkce | Popis |
|---|---|
| `float_zeros(n)` | Vytvoří FloatArray s `n` nulami. |
| `float_fill(arr, value)` | Vyplní celé FloatArray hodnotou. |
| `float_sum(arr)` | Vrátí součet všech prvků FloatArray (nativní kernel). |
| `float_dot(a, b)` | Vrátí skalární součin dvou FloatArray (nativní kernel). |
| `float_axpy(alpha, x, y)` | Provede `y = alpha * x + y` (in-place, nativní kernel). |
| `float_matmul(a, b, m, k, n)` | Vynásobí matice `(m×k) × (k×n)` a vrátí FloatArray `(m×n)`. |

---

## <span class="badge badge-module">MODULY</span> 3. Standardní moduly

### <span class="badge badge-module">lux</span> lux *(vestavěný)*

| Export | Popis |
|---|---|
| `lux.version` | Verze LSL (String, např. `"0.6"`). |
| `lux.name` | Název jazyka (String, `"Lux Simple Lang"`). |
| `lux.l(value)` | Alias pro `type(value)`. |
| `lux.identity(value)` | Vrátí hodnotu beze změny. |
| `lux.clamp(value, low, high)` | Ořízne hodnotu do rozsahu `<low, high>`. |
| `lux.is_empty(collection)` | Vrátí `True`, pokud je kolekce prázdná. |

### <span class="badge badge-module">math</span> math — matematika a statistika

| Export | Popis |
|---|---|
| `math.PI`, `math.TAU`, `math.E` | Běžné Float64 matematické konstanty. |
| `math.pi(decimal_places)` | Vygeneruje pí jako desetinný String s požadovaným počtem míst. |
| `math.exp(x)`, `math.log(x)` | Exponenciála a přirozený logaritmus. |
| `math.sin(x)`, `math.cos(x)`, `math.tan(x)` | Goniometrické funkce v radiánech. |
| `math.sigmoid(x)`, `math.tanh(x)` | Stabilní aktivační funkce. |
| `math.relu(x)`, `math.softplus(x)`, `math.swish(x)` | Další běžné aktivační funkce. |
| `math.mean(values)`, `math.median(values)` | Střední hodnota a medián. |
| `math.variance(values)`, `math.standard_deviation(values)` | Populační rozptyl a směrodatná odchylka. |
| `math.factorial(n)` | Faktoriál v běžném Int64. |
| `math.factorial_big(n)` | Faktoriál jako `bigint.BigInt`. |

### <span class="badge badge-module">bigint</span> bigint — celá čísla libovolné velikosti

```lsl
load bigint
number = bigint.BigInt("123456789012345678901234567890")
print number.power(2).text()
```

`BigInt` a kompatibilní `SuperInt` poskytují metody `text`, `add`,
`subtract`, `multiply`, `floor_divide`, `divide`, `modulo`, `power`,
`compare`, `equals`, `negate`, `absolute`, `is_zero` a `to_int`.

### <span class="badge badge-module">json</span> json — JSON codec

| Funkce | Popis |
|---|---|
| `json.encode(value)` | Serializuje hodnotu do JSON řetězce. |
| `json.decode(text)` | Naparsuje JSON řetězec na LSL hodnotu. |
| `json.pretty(value)` | Jako `encode`, ale s odřádkováním (aktuálně kompaktní + LF). |

### <span class="badge badge-module">lconf</span> lconf — dependency manifest

| Funkce | Popis |
|---|---|
| `lconf.decode(text)` | Naparsuje `config.lconf` text, vrátí `{apt, lux, lsl}` Listy. |
| `lconf.encode(manifest)` | Serializuje manifest zpět do textu. |
| `lconf.parse(text, path)` | Jako `decode`, ale `path` se použije v chybových hláškách. |

### <span class="badge badge-module">http</span> http — HTTP(S) klient

| Funkce | Popis |
|---|---|
| `http.get(url)` | HTTP GET, vrátí `{status, text, ok}`. |
| `http.post(url, body, headers, timeout)` | HTTP POST, `body` se automaticky serializuje (pokud je Dict/List). |
| `http.post_stream(url, body, headers, timeout, on_chunk)` | Streamovaný POST — `on_chunk(chunk)` je callback. |

### <span class="badge badge-module">env</span> env — proměnné prostředí

| Funkce | Popis |
|---|---|
| `env.get(name, default)` | Vrátí hodnotu proměnné prostředí, nebo `default`. |
| `env.has(name)` | Vrátí `True`, pokud proměnná existuje. |
| `env.require(name)` | Vrátí hodnotu; pokud neexistuje, vyvolá chybu. |

### <span class="badge badge-module">time</span> time — čas a časovače

| Funkce | Popis |
|---|---|
| `time.time()` | Unix timestamp (Float sekundy od epochy, wall clock). |
| `time.now()` | Alias pro `time.time()`. |
| `time.monotonic()` | Monotónní čas (Float sekundy), neovlivněný změnou systémového času. |
| `time.perf_counter()` | Alias pro `time.monotonic()` (high-resolution). |
| `time.sleep(seconds)` | Uspí proces na daný počet sekund (Float). |

### <span class="badge badge-module">os</span> os — spouštění programů *(bez shellu!)*

| Funkce | Popis |
|---|---|
| `os.run(command)` | Spustí příkaz (String nebo List), zdědí stdio, vrátí exit status. |
| `os.system(command)` | Alias pro `os.run()`. |
| `os.capture(command)` | Spustí příkaz a vrátí stdout jako String. |
| `os.capture_result(command)` | Spustí příkaz, vrátí `{stdout, stderr, status, ok}`. |
| `os.check(command)` | Spustí příkaz, vrátí stdout; při chybě vyvolá `OSCommandError`. |
| `os.run_argv(program, arguments)` | Explicitní dvouargumentová varianta `run`. |
| `os.capture_argv(program, arguments)` | Explicitní dvouargumentová varianta `capture`. |
| `os.which(name)` | Najde executable v `PATH`, vrátí cestu nebo `None`. |

### <span class="badge badge-module">process</span> process — rozšířené procesní API

| Funkce | Popis |
|---|---|
| `process.capture_result(program, arguments)` | Spustí program, vrátí `{stdout, stderr, status, ok}`. |
| `process.capture_input_result(program, arguments, input_text)` | Jako `capture_result`, ale pošle programu vstup. |
| `process.check(program, arguments)` | Spustí, vrátí stdout; při nenulovém statusu `ProcessError`. |
| `process.check_input(program, arguments, input_text)` | Jako `check`, ale s poslaným vstupem. |

### <span class="badge badge-module">system</span> system — správa systému (LuxOS/Debian)

| Funkce | Popis |
|---|---|
| `system.install(package)` | Nainstaluje balíček (lux, fallback apt). |
| `system.update(package)` | Aktualizuje balíček. |
| `system.remove(package)` | Odstraní balíček. |
| `system.refresh()` | Aktualizuje seznamy balíčků (`apt update`). |
| `system.enable_service(name)` | Povolí a spustí systemd službu. |
| `system.disable_service(name)` | Zastaví a zakáže systemd službu. |
| `system.restart_service(name)` | Restartuje systemd službu. |
| `system.service_active(name)` | Vrátí `True`, pokud služba běží. |
| `system.set_hostname(name)` | Nastaví hostname systému. |
| `system.set_timezone(zone)` | Nastaví časovou zónu (např. `"Europe/Prague"`). |
| `system.set_locale(locale)` | Nastaví locale (např. `"C.UTF-8"`). |
| `system.ensure_group(name)` | Vytvoří skupinu, pokud neexistuje (idempotentní). |
| `system.remove_group(name)` | Smaže skupinu. |
| `system.ensure_user(name, shell, groups)` | Vytvoří/aktualizuje uživatele (idempotentní). |
| `system.remove_user(name)` | Smaže uživatele. |
| `system.write_file(path, content, mode)` | Atomicky zapíše soubor s danými právy. |
| `system.write_owned_file(path, content, mode, owner, group)` | Atomicky zapíše soubor s vlastníkem. |
| `system.ensure_directory(path, mode)` | Vytvoří adresář s danými právy. |
| `system.remove_file(path)` | Smaže soubor. |
| `system.ensure_mount(device, target, fs, options)` | Zajistí připojení souborového systému. |
| `system.unmount(target)` | Odpojí souborový systém. |
| `system.check_system(config_path)` | Zvaliduje konfiguraci LuxOS. |
| `system.apply_system(config_path)` | Aplikuje konfiguraci LuxOS. |
| `system.dry_run_system(config_path)` | Suchá zkouška aplikace konfigurace. |
| `system.lux_status()` | Vrátí stav LuxOS. |
| `system.generations()` | Vrátí seznam generací. |
| `system.rollback(generation)` | Vrátí systém na danou generaci. |
| `system.rollback_dry(generation)` | Suchá zkouška rollbacku. |
| `system.install_with(p, lux, apt)` | `install` s explicitními cestami k nástrojům. |
| `system.update_with(p, lux, apt)` | `update` s explicitními cestami. |
| `system.remove_with(p, lux, apt)` | `remove` s explicitními cestami. |
| `system.refresh_with(apt)` | `refresh` s explicitní cestou k apt. |
| `system.enable_service_with(n, sc)` | `enable_service` s explicitní cestou k systemctl. |
| `system.disable_service_with(n, sc)` | `disable_service` s explicitní cestou. |
| `system.restart_service_with(n, sc)` | `restart_service` s explicitní cestou. |
| `system.service_active_with(n, sc)` | `service_active` s explicitní cestou. |
| `system.set_hostname_with(n, cmd)` | `set_hostname` s explicitní cestou. |
| `system.set_timezone_with(z, cmd)` | `set_timezone` s explicitní cestou. |
| `system.set_locale_with(l, cmd)` | `set_locale` s explicitní cestou. |
| `system.ensure_group_with(n, g, ga)` | `ensure_group` s explicitními cestami. |
| `system.remove_group_with(n, gd)` | `remove_group` s explicitní cestou. |
| `system.ensure_user_with(n, s, g, i, ua, um)` | `ensure_user` s explicitními cestami. |
| `system.remove_user_with(n, ud)` | `remove_user` s explicitní cestou. |
| `system.write_file_with(p, c, m, o, g, t)` | `write_file` s explicitními nástroji. |
| `system.ensure_directory_with(p, m, mk, ch)` | `ensure_directory` s explicitními cestami. |
| `system.ensure_mount_with(d, t, fs, o, mp, mk, mo)` | `ensure_mount` s explicitními cestami. |
| `system.unmount_with(t, um)` | `unmount` s explicitní cestou. |
| `system.check_system_with(c, l)` | `check_system` s explicitní cestou k lux. |
| `system.apply_system_with(c, d, l)` | `apply_system` s explicitní cestou. |
| `system.lux_status_with(l)` | `lux_status` s explicitní cestou. |
| `system.generations_with(l)` | `generations` s explicitní cestou. |
| `system.rollback_with(g, d, l)` | `rollback` s explicitní cestou. |

### <span class="badge badge-module">config</span> config — konfigurační primitiva *(pro `lsl config`)*

| Funkce | Popis |
|---|---|
| `config.option(type, default, description)` | Deklaruje konfigurační volbu s typem, výchozí hodnotou a popisem. |
| `config.required(type, description)` | Deklaruje povinnou volbu (bez defaultu). |
| `config.mkOverride(priority, value)` | Nastaví hodnotu s explicitní prioritou slučování. |
| `config.mkDefault(value)` | Nastaví výchozí hodnotu (priorita 100, lze přepsat). |
| `config.mkForce(value)` | Vynutí hodnotu (priorita 1000, přepíše vše). |
| `config.lazy(thunk)` | Odloží vyhodnocení bezargumentové funkce na materializaci. |
| `config.mkIf(condition, value)` | Pokud `condition == False`, hodnotu vynechá. |

### <span class="badge badge-module">ai</span> ai — AI orchestrace (OpenAI-compatible)

| Funkce | Popis |
|---|---|
| `ai.request(endpoint, token, model, messages, options)` | Odešle požadavek na AI API, vrátí Dictionary s odpovědí. |
| `ai.stream(endpoint, token, model, messages, options, on_event)` | Streamovaná varianta — `on_event(event)` je callback. |
| `ai.stream_text(text, on_chunk, cancel)` | Parsuje SSE stream na textové chunky. |
| `ai.content(response)` | Extrahuje text první odpovědi z AI response Dictionary. |

### <span class="badge badge-module">display</span> display — otevření okna (X11 / framebuffer)

| Funkce | Popis |
|---|---|
| `display.open(width, height, title)` | Otevře okno (X11 nebo framebuffer), vrátí objekt displeje. |
| `display.open_framebuffer()` | Otevře framebuffer napřímo (`/dev/fb0`). |
| `display.x11_available()` | Vrátí `True`, pokud je dostupný X11 server. |
| `display.open_device(name)` | Otevře specifické zařízení. |

**Objekt displeje** *(vrácený `display.open`)*:

| Člen / Metoda | Popis |
|---|---|
| `d.width` | Šířka okna v pixelech. |
| `d.height` | Výška okna v pixelech. |
| `d.should_close()` | Vrátí `True`, pokud uživatel zavřel okno. |
| `d.present(pixels, width, height)` | Vykreslí pixely do okna a provede GC. |
| `d.poll()` | Vrátí List událostí `[(druh, a, b), ...]`. |
| `d.close()` | Zavře okno a uvolní prostředky. |

### <span class="badge badge-module">gfx</span> gfx — grafika a rasterizace

**Barvy**:

| Funkce | Popis |
|---|---|
| `gfx.rgb(r, g, b)` | Složí barvu z R, G, B složek (0–255) do Int. |
| `gfx.red(color)` | Extrahuje červenou složku. |
| `gfx.green(color)` | Extrahuje zelenou složku. |
| `gfx.blue(color)` | Extrahuje modrou složku. |
| `gfx.mix_color(bottom, top, alpha)` | Alpha-blend dvou barev (0–255 alpha). |

**Rasterizéry** *(nad raw IntArray pixely)*:

| Funkce | Popis |
|---|---|
| `gfx.raster_clear(pixels, w, h, color)` | Vyplní celou plochu barvou. |
| `gfx.raster_set(pixels, w, h, x, y, color)` | Nastaví jeden pixel. |
| `gfx.raster_hline(pixels, w, h, x, y, length, color)` | Vodorovná čára. |
| `gfx.raster_vline(pixels, w, h, x, y, length, color)` | Svislá čára. |
| `gfx.raster_fill_rect(pixels, w, h, x, y, rw, rh, color)` | Vyplněný obdélník. |
| `gfx.raster_rect(pixels, w, h, x, y, rw, rh, color)` | Obrys obdélníku. |
| `gfx.raster_line(pixels, w, h, x0, y0, x1, y1, color)` | Úsečka (Bresenham). |
| `gfx.raster_blit(dst, dw, dh, src, sw, sh, dx, dy)` | Překopíruje pixely z `src` do `dst`. |
| `gfx.raster_copy_rect(dst, dw, dh, src, sw, sh, x, y, w, h)` | Překopíruje obdélníkovou oblast. |
| `gfx.raster_fill_circle(pixels, w, h, cx, cy, r, color)` | Vyplněný kruh. |
| `gfx.raster_fill_pill(pixels, w, h, x, y, rw, rh, color)` | Zaoblený obdélník ("pill"). |
| `gfx.raster_glyph(pixels, w, h, x, y, offset, color)` | Vykreslí jeden znak (8×16 font). |
| `gfx.raster_text(pixels, w, h, x, y, text, color)` | Vykreslí text (8×16 font). |
| `gfx.raster_glyph_scaled(pixels, w, h, x, y, offset, color, scale)` | Znak zvětšený celočíselným faktorem. |
| `gfx.raster_text_scaled(pixels, w, h, x, y, text, color, scale)` | Text zvětšený celočíselným faktorem. |
| `gfx.raster_glyph_aa(pixels, w, h, x, y, offset, color, alpha, scale)` | Anti-aliased znak. |
| `gfx.raster_text_aa(pixels, w, h, x, y, text, color, alpha, scale)` | Anti-aliased text (2×2 supersampling). |
| `gfx.raster_gradient(pixels, w, h, top_color, bottom_color)` | Diagonální gradient. |
| `gfx.raster_round_rect(pixels, w, h, x, y, rw, rh, radius, color, alpha, feather)` | Anti-aliased zaoblený obdélník s alpha-blendingem. |
| `gfx.raster_round_rect_grad(pixels, w, h, x, y, rw, rh, radius, top, bottom, alpha, feather)` | Zaoblený obdélník s vertikálním gradientem. |
| `gfx.raster_shadow(pixels, w, h, x, y, rw, rh, radius, color, alpha, blur)` | Měkký stín. |

**Surface** *(objekt vytvořený `gfx.surface()`)*:

| Funkce / Metoda | Popis |
|---|---|
| `gfx.surface(width, height, color)` | Vytvoří kreslicí plochu s daným pozadím. |
| `s.clear(color)` | Vyplní celou plochu barvou. |
| `s.get(x, y)` | Vrátí barvu pixelu. |
| `s.set(x, y, color)` | Nastaví barvu pixelu. |
| `s.hline(x, y, length, color)` | Vodorovná čára. |
| `s.vline(x, y, length, color)` | Svislá čára. |
| `s.fill_rect(x, y, w, h, color)` | Vyplněný obdélník. |
| `s.rect(x, y, w, h, color)` | Obrys obdélníku. |
| `s.line(x0, y0, x1, y1, color)` | Úsečka. |
| `s.blit(src_pixels, sw, sh, dx, dy)` | Překopíruje pixely z jiného zdroje. |
| `s.text(x, y, value, color)` | Vykreslí text (vrací šířku v pixelech). |
| `s.glyph(x, y, offset, color)` | Vykreslí jeden znak. |
| `s.save_ppm(path)` | Uloží plochu jako binární P6 PPM soubor. |
| `s.pixels` | IntArray s pixely (jeden Int = 0xRRGGBB na pixel). |
| `s.width` | Šířka plochy. |
| `s.height` | Výška plochy. |

**Měření textu**:

| Funkce | Popis |
|---|---|
| `gfx.text_width(value)` | Vrátí šířku textu v pixelech. |
| `gfx.text_height()` | Vrátí výšku řádku textu (vždy 16). |

### <span class="badge badge-module">ui</span> ui — widgety

| Funkce | Popis |
|---|---|
| `ui.label(x, y, text)` | Vytvoří textový popisek. |
| `ui.button(x, y, w, h, text, on_click)` | Vytvoří tlačítko s callbackem. |
| `ui.checkbox(x, y, text, checked)` | Vytvoří zaškrtávací pole. |
| `ui.new_state()` | Vytvoří Dictionary `{running, key, mouse_x, mouse_y}`. |
| `ui.process(widgets, state, events)` | Zpracuje události — hover, klik, Esc, zavření. |
| `ui.paint(pixels, w, h, widgets, background)` | Vykreslí všechny widgety na plochu. |

**Barvy tématu**:

| Konstanta | Popis |
|---|---|
| `ui.color_background` | Barva pozadí. |
| `ui.color_text` | Barva textu. |
| `ui.color_muted` | Tlumená barva. |
| `ui.color_accent` | Zvýrazňovací barva. |
| `ui.color_accent_text` | Barva textu na zvýraznění. |
| `ui.color_border` | Barva okrajů. |
| `ui.color_field` | Barva vstupního pole. |

### <span class="badge badge-module">css</span> css — deklarativní stylování

| Funkce | Popis |
|---|---|
| `css.parse(text)` | Naparsuje CSS řetězec do Dictionary `selektor → {vlastnost: hodnota}`. |
| `css.rule(sheet, selector)` | Vrátí Dictionary vlastností pro daný selektor. |
| `css.value(rules, key, fallback)` | Vrátí hodnotu vlastnosti, nebo `fallback`. |
| `css.color(text)` | Naparsuje barvu (`#rgb`, `#rrggbb`, `rgb(...)`, `rgba(...)`). |
| `css.alpha(text)` | Vrátí alpha složku (0.0–1.0) z `rgba()` barvy. |
| `css.is_gradient(text)` | Vrátí `True`, pokud hodnota je `linear-gradient(...)`. |
| `css.gradient_top(text)` | Vrátí horní barvu gradientu. |
| `css.gradient_bottom(text)` | Vrátí dolní barvu gradientu. |
| `css.number(text)` | Naparsuje číselnou hodnotu vlastnosti. |

### <span class="badge badge-module">input</span> input — evdev klávesnice

| Funkce / Konstanta | Popis |
|---|---|
| `input.open_keyboard_device()` | Otevře zařízení klávesnice (`/dev/input`). |
| `input.read_key_events(handle)` | Přečte události klávesnice z handle. |
| `input.key_esc` | Kód klávesy Escape. |
| `input.key_enter` | Kód klávesy Enter. |
| `input.key_left` | Kód šipky vlevo. |
| `input.key_right` | Kód šipky vpravo. |
| `input.key_up` | Kód šipky nahoru. |
| `input.key_down` | Kód šipky dolů. |
| `input.key_backspace` | Kód Backspace. |
| `input.key_tab` | Kód Tabulátoru. |
| `input.key_space` | Kód mezerníku. |

### <span class="badge badge-module">fd</span> fd — low-level souborové deskriptory

| Funkce | Popis |
|---|---|
| `fd.open(path, flags)` | Otevře soubor přes syscall `open`. |
| `fd.read(handle, buffer, count)` | Přečte data do ByteArray. |
| `fd.write(handle, buffer, count)` | Zapíše data z ByteArray. |
| `fd.seek(handle, position)` | Posune pozici v souboru. |
| `fd.close(handle)` | Zavře deskriptor. |
| `fd.ioctl(handle, request, buffer)` | Provede `ioctl` syscall. |
| `fd.mmap(handle, length, offset)` | Namapuje soubor do paměti. |
| `fd.socket(domain, kind)` | Vytvoří socket. |
| `fd.connect_unix(path)` | Připojí se na Unix domain socket. |
| `fd.read_all(path)` | Přečte celý soubor jako ByteArray. |
| `fd.read_text(path)` | Přečte celý soubor jako String. |

### <span class="badge badge-module">native</span> native — in-process ET_DYN ABI

| Funkce | Popis |
|---|---|
| `native.open(path)` | Načte self-contained ET_DYN image, vrátí handle. |
| `native.symbol(library, name)` | Vyhledá symbol v SHT_DYNSYM, vrátí opaque Function. |
| `native.call(func, [args...])` | Zavolá nativní funkci s max 6 Int argumenty, vrátí Int. |
| `native.close(library)` | Uvolní nativní knihovnu. |

### <span class="badge badge-module">plugin</span> plugin — procesní plugin ABI

| Funkce | Popis |
|---|---|
| `plugin.request(executable, operation, payload)` | Spustí plugin jako proces, komunikuje přes JSON argv/stdout. |
| `plugin.request_input(executable, operation, payload)` | Jako `request`, ale JSON posílá přes stdin i nad limitem jednoho argv. |

### <span class="badge badge-module">cuda</span> cuda — volitelný CUDA backend

| Funkce | Popis |
|---|---|
| `cuda.configure(worker, policy, min_elements)` | Nastaví worker a politiku programu (`auto`, `required`, `off`). |
| `cuda.probe()` | Spustí ověřovací CUDA kernel a vrátí metadata zařízení, nebo `None`. |
| `cuda.available()` | Vrátí True pouze po úspěšném ověřovacím device kernelu. |
| `cuda.devices()` | Vrátí metadata CUDA zařízení; v `auto` režimu při nedostupnosti `[]`. |
| `cuda.device_count()` | Počet dostupných zařízení. |
| `cuda.backend()` | Aktuálně dostupný backend: `"cuda"` nebo `"cpu"`. |
| `cuda.sum_data(data)` | GPU sum nad FloatArray s CPU fallbackem. |
| `cuda.dot_data(a, b)` | GPU dot nad FloatArray s CPU fallbackem. |
| `cuda.axpy_data(alpha, x, y)` | GPU AXPY in-place s CPU fallbackem. |
| `cuda.matmul_data(a, b, m, k, n)` | GPU matmul s CPU fallbackem. |

Konfigurace prostředí: `LSL_CUDA_WORKER`, `LSL_CUDA=auto|required|off` a
`LSL_CUDA_DEVICE`; `LSL_CUDA_MIN_ELEMENTS` má výchozí hodnotu 400 000 000
pracovních jednotek.

### <span class="badge badge-module">tensor</span> tensor — CPU/CUDA tenzory

| Funkce | Popis |
|---|---|
| `tensor.from_values(values, shape)` | Vytvoří Tensor z plochého seznamu hodnot. |
| `tensor.zeros(shape)` | Vytvoří Tensor vyplněný nulami. |
| `tensor.sum_data(data)` | Součet FloatArray přes CUDA nebo CPU fallback. |
| `tensor.dot_data(a, b)` | Skalární součin dvou FloatArray (přímý, bez Tensor obalu). |
| `tensor.axpy_data(alpha, x, y)` | AXPY operace přímo nad FloatArray. |
| `tensor.matmul_data(a, b, m, k, n)` | Maticové násobení přímo nad FloatArray. |

**Třída Tensor**:

| Konstruktor / Metoda | Popis |
|---|---|
| `Tensor(data, shape, strides, offset, dtype)` | Vytvoří manuálně (obvykle přes `from_values`). |
| `t.rank()` | Počet dimenzí. |
| `t.size()` | Celkový počet prvků. |
| `t.get([i, j, ...])` | Vrátí prvek na daných indexech. |
| `t.set([i, j, ...], value)` | Nastaví prvek. |
| `t.reshape(shape)` | Změní tvar (stejný počet prvků). |
| `t.view(shape, strides, offset)` | Zero-copy pohled (sdílí data). |
| `t.sum()` | Součet všech prvků (nativní kernel). |
| `t.dot(other_data)` | Skalární součin (vyžaduje rank-1 tenzor). |
| `t.axpy(alpha, x_data)` | AXPY in-place. |
| `t.matmul(other_data, other_shape)` | Maticové násobení, vrátí nový Tensor. |
| `t.shape` | List rozměrů. |
| `t.data` | Podkladový FloatArray. |
| `t.dtype` | Typ prvků (např. `"Float64"`). |

### <span class="badge badge-module">luxos</span> luxos — LuxOS aktivační runtime

| Funkce | Popis |
|---|---|
| `luxos.defaults()` | Vrátí výchozí konfiguraci. |
| `luxos.apply(config)` | Aplikuje konfiguraci (balíčky, uživatelé, MOTD, identita). |
| `luxos.apply_manifest()` | Aplikuje manifest z aktuálního `config.lconf` a konfigurace. |
| `luxos.previous_manifest()` | Vrátí manifest předchozí generace. |
| `luxos.latest_generation()` | Vrátí poslední známou generaci. |
| `luxos.record_generation(config)` | Zaznamená vyhodnocenou konfiguraci jako novou generaci. |

### <span class="badge badge-module">configure</span> configure — konfigurační evaluátor *(interní)*

| Funkce | Popis |
|---|---|
| `configure.collect(path, seen, active, order)` | Rekurzivně sesbírá moduly v post-order pořadí. |

---

## <span class="badge badge-kw">KLÍČOVÁ SLOVA</span> 4. Klíčová slova a řídící konstrukce

| Konstrukce | Popis |
|---|---|
| `if` *podmínka* `:` | Začátek podmíněného bloku. |
| `elif` *podmínka* `:` | Další podmínka v `if` řetězci. |
| `else:` | Výchozí větev podmínky. |
| `end` | Ukončuje blok (`if`, `for`, `while`, `loop`, `function`, `class`, `safe`, `try`). |
| `for` *var* `in` *iterable* `:` | Smyčka přes iterovatelnou hodnotu. |
| `while` *podmínka* `:` | Smyčka, dokud podmínka platí. |
| `loop:` | Nekonečná smyčka. |
| `break` | Ukončí nejvnitřnější smyčku. |
| `continue` | Přeskočí zbytek iterace, pokračuje další. |
| `function` *jméno* `(`*param*`)` `:` | Definuje funkci. |
| `return` *value* | Vrátí hodnotu z funkce. |
| `call` *funkce* `(`*args*`)` | Zavolá funkci a zahodí návratovou hodnotu. |
| `class` *Jméno* `(`*podmínka*`)` `:` | Definuje třídu. |
| `ctype Public` / `ctype Private` | Viditelnost třídy mimo modul. |
| `load` *modul* | Importuje modul. |
| `from` *modul* `load` *jméno* | Selektivní import. |
| `from` *modul* `load` *jméno* `as` *alias* | Import s přejmenováním. |
| `safe:` | Blok odolný chybám — chyba se potlačí. |
| `try:` | Blok s fallbackem. |
| `else:` *(v `try`)* | Provede se, pokud `try` selhal. |
| `Error(`*Typ*`: "`*zpráva*`")` | Vyvolá vlastní chybu. |
| `check(`*podmínka*`, "`*zpráva*`")` | Ověří podmínku, jinak chyba. |
| `del(`*x*`)` | Smaže proměnnou, prvek kolekce nebo člen instance. |
| `rang(stop)` / `rang(start, stop)` / `rang(start, stop, step)` | Generátor číselných řad. |
| `range(...)` | Alias pro `rang`. |
