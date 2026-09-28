# Knihovna time

`load time`

Hodinový čas, monotónní měření a uspání čistě přes syscally.

## Funkce

### time.time() → Float

Unix timestamp (wall clock).

### time.now() → Float

Alias `time.time()`.

### time.monotonic() → Float

Monotónní sekundy — pro měření intervalů a timeoutů. Není ovlivněno
změnami systémového času.

### time.perf_counter() → Float

Vysoké rozlišení, rovněž monotónní. Vhodné pro jemné benchmarky.

### time.sleep(seconds)

Uspí program na daný počet sekund (Float, syscall `clock_nanosleep`).

## Příklad

```lsl
load time

print time.time()

start = time.monotonic()
call time.sleep(0.1)
elapsed = time.monotonic() - start
print elapsed   # ~0.1 sekundy
```

Pro měření intervalů vždy používejte `monotonic`/`perf_counter`, ne
`time`/`now` — wall clock může změnit správce systému.

## Související stránky

- `lsl man math` — numerické funkce
- `lsl man random` — náhodná čísla
