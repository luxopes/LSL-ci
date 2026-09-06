# Random — náhodná čísla a výběry

Od LSL 0.7.8 je `random` součástí standardní knihovny, bez instalace balíčku.
Implementace včetně MT19937, SHA-512 seedování a rozdělení je pouze v LSL.

```lsl
load random

call random.seed(42)
print random.random()
print random.randrange(10)
print random.randint(1, 6)
print random.choices(["A", "B"], weights=[1, 3], k=8)

rng = random.Random("můj experiment")
data = [rng.normalvariate(mu=0, sigma=1) for i in rang(20)]
call rng.shuffle(data)
print rng.sample(data, 3)
print {i:rng.random() for i in rang(4)}
```

## Generátory a stav

`Random(x=None)` má vlastní stav MT19937; modulové funkce sdílejí jeden
generátor. `SystemRandom(x=None)` používá Linux `getrandom` a stejné metody,
ale `seed` ignoruje a `getstate/setstate` odmítá. Selhání OS entropie
vyvolá chybu, nespadne na slabý časový seed.

MT19937 není kryptograficky bezpečný: nepoužívejte jej pro hesla, tokeny ani
klíče. Pro takové náhodné bajty použijte `SystemRandom().randbytes(n)`.

| Metoda / modulová funkce | Význam |
|---|---|
| `seed(a=None, version=2)` | Seed z Int, Bool, Float, String, ByteArray nebo BigInt; None načte OS entropii. |
| `random()` | Float s 53 náhodnými bity v intervalu [0, 1). |
| `getstate()` | Oddělený snapshot `(3, Tuple(624 slov + index), gauss_cache)`. |
| `setstate(state)` | Ověří celý snapshot před změnou generátoru; přijímá verze 2 a 3. |
| `getrandbits(k)` | 0–63 bitů vrací Int, 64–4096 bitů BigInt. |
| `randbytes(n)` | Nový ByteArray o n bajtech. |

String seed v režimu 2 se převádí na UTF-8 a rozšiřuje SHA-512 stejně jako
v Pythonu. Režim 1 je starší zúžené textové seedování. Int seed používá
absolutní hodnotu, včetně INT64_MIN. Float seed používá číselný hash jako
64bitový CPython; NaN je odmítnut, protože jeho seed není reprodukovatelný.

Každá veřejná operace nad jedním generátorem je uzamčená, včetně Gaussian
cache a změny seedu. Po chybě se zámek uvolní. Pořadí volání mezi vlákny
není deterministické. Neměňte přímo implementační atribut `state`.

```lsl
saved = rng.getstate()
first = rng.random()
call rng.setstate(saved)
check(first == rng.random(), "obnovení generátoru")
```

## Celá čísla a kolekce

| Funkce | Význam |
|---|---|
| `randrange(start, stop=None, step=1)` | Výběr z polouzavřeného rozsahu; záporný krok je podporován. |
| `randint(a, b)` | Včetně obou mezí. |
| `choice(seq)` | Jeden prvek neprázdné sekvence. |
| `choices(population, weights=None, cum_weights=None, k=1)` | k výběrů s opakováním, volitelně vážených. |
| `sample(population, k, counts=None)` | Výběr bez opakování pozic; counts udávají násobnosti. |
| `shuffle(x)` | Promíchá sekvenci na místě, vrací None. |

Rozsahy podporují Int64 i BigInt. S BigInt mezí/krokem je výsledkem BigInt;
rozsah mezi Int mezemi vrací Int i přes celou šířku Int64. Float není
automaticky přijímán jako celé číslo. Rozsah může mít nejvýše 4096 bitů.

Výběry přijímají List, Tuple, String a typovaná pole. Dictionary není
sekvence: použijte `mapping.keys()`, `values()` nebo `items()`.
`shuffle` vyžaduje měnitelnou sekvenci. Váhy musí být nezáporné,
konečné a mít kladný součet; kumulativní váhy musí být neklesající.
`weights` a `cum_weights` nelze zadat zároveň.

## Rozdělení

- `uniform(a, b)`, `triangular(low=0.0, high=1.0, mode=None)`
- `normalvariate(mu=0.0, sigma=1.0)`, `gauss(mu=0.0, sigma=1.0)`
- `lognormvariate(mu, sigma)`, `expovariate(lambd=1.0)`
- `gammavariate(alpha, beta)`, `betavariate(alpha, beta)`
- `vonmisesvariate(mu, kappa)`, `paretovariate(alpha)`
- `weibullvariate(alpha, beta)`, `binomialvariate(n=1, p=0.5)`

Gamma beta je měřítko, nikoli rate. U exponential je parametr rate a může
být záporný, ne nulový. U lognormal jsou mu a sigma parametry podkladového
normálního rozdělení. Binomial vrací počet úspěchů v n pokusech.

## Kompatibilita a limity

Rozhraní je inspirované [Python random](https://docs.python.org/3/library/random.html),
nejde o spouštění Pythonu ani úplný drop-in překladač Python programů.
MT19937 a seedování zachovávají reprodukovatelnou posloupnost `random()`
a `getrandbits()`; testy obsahují referenční vektory CPythonu.
Vyšší rozdělení a `sample` nemusí při stejném seedu spotřebovat stejné
množství náhody nebo vrátit stejné výsledky jako Python. Float výpočty
používají LSL math, takže je možný rozdíl zaokrouhlení.

LSL nemá Python arbitrární int jako základní typ, immutable bytes, pickle
ani dynamické přepisování generátorových metod v Python subclasses.
Chyby veřejné operace jsou zachytitelné přes `try/else`; `last_error()`
obsahuje `RandomError` a původní příčinu (např. TypeError).

Pro omezení práce platí: nejvýše 1 MiB seedových bajtů, 4096 bitů BigInt
seedu, 4096 bitů na `getrandbits`/rozsah, 1 048 576 bajtů na
`randbytes` a stejný limit pro k/n výběrů a binomial pokusů.
Binomial je O(n); von Mises odmítá kappa > 1e12. Reálné parametry musí
být konečné; NaN/Infinity nejsou platné váhy. `_random_hash` je privátní
seedový helper, nikoli veřejná kryptografická knihovna.

Výchozí hodnoty a pojmenované argumenty fungují pro deklarované funkce,
metody a konstruktory. Výchozí hodnota musí být immutable literál
(číslo, text, Bool nebo None); proměnlivé defaulty, *args/**kwargs,
keyword-only parametry a keyword volání builtinů nejsou součástí LSL 0.7.8.
Funkci s defaulty zatím nelze uložit jako Function hodnotu: použijte
wrapper s explicitními parametry. Vedlejší efekty v argumentech zapisujte
do samostatných příkazů; Python pořadí vyhodnocování není kontrakt LSL.

Algoritmy: [MT19937 referenční jádro](https://raw.githubusercontent.com/python/cpython/3.14/Modules/_randommodule.c),
[FIPS SHA-512](https://www.rfc-editor.org/rfc/rfc6234),
Box–Muller (gauss), Kinderman–Monahan (normalvariate),
Marsaglia–Tsang (gamma) a virtuální Fisher–Yates (sample).
Licence původního MT19937 je zachovaná v komentáři `stdlib/random.lsl`.
