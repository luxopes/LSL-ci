# Knihovna random

`load random`

Náhodná čísla ve stylu Pythonu: reprodukovatelný MT19937 generátor
`Random(seed)` a systémový `SystemRandom`. Modulové funkce používají
sdílený implicitní generátor.

## Modulové funkce

```lsl
random.seed(a=None, version=2)   random.getstate()   random.setstate(state)
random.random()                  # Float v [0, 1)
random.getrandbits(k)            random.randbytes(n)
random.randrange(start, stop=None, step=1)
random.randint(a, b)             # včetně obou mezí
random.choice(seq)
random.choices(population, weights=None, cum_weights=None, k=1)
random.sample(population, k, counts=None)
random.shuffle(x)                # na místě
random.uniform(a, b)
random.triangular(low=0.0, high=1.0, mode=None)
random.gauss(mu=0.0, sigma=1.0)         random.normalvariate(mu=0.0, sigma=1.0)
random.lognormvariate(mu, sigma)        random.expovariate(lambd=1.0)
random.gammavariate(alpha, beta)        random.betavariate(alpha, beta)
random.vonmisesvariate(mu, kappa)       random.paretovariate(alpha)
random.weibullvariate(alpha, beta)      random.binomialvariate(n=1, p=0.5)
```

## Třídy

```lsl
rng = random.Random(42)         # deterministický MT19937
sys = random.SystemRandom()     # entropie z jádra
```

Obě třídy mají stejné metody jako modulové funkce (`seed`, `getstate`,
`setstate`, `random`, `randrange`, `randint`, `getrandbits`, `randbytes`,
`choice`, `choices`, `sample`, `shuffle`, `uniform` a rozdělení).
`random.SystemRandom` je podtřída `Random`; semínko a stav ignoruje.

## Příklad

```lsl
load random

rng = random.Random(42)
print rng.randint(1, 6), rng.choice(["a", "b", "c"])
print rng.sample([1, 2, 3, 4, 5], 2)
```

## Chyby

- `RandomError` — neplatné parametry (prázdný výběr, záporné váhy,
  semínko mimo rozsah apod.).

## Související stránky

- `lsl man 16-random` — podrobná kapitola o generátoru a kompatibilitě
- `lsl man math` — deterministické numerické funkce
- `lsl man time` — čas a měření
