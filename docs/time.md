# Modul `time`

Standardní modul `time` poskytuje wall-clock čas, monotónní měření a uspání
aktuálního procesu pouze přes Linux syscalls.

```lsl
load time

started = time.perf_counter()
call time.sleep(0.05)
elapsed = time.perf_counter() - started
print "elapsed", elapsed
print "unix seconds", time.time()
```

## API

- `time.time()` — `Float` sekund od Unix epochy z `CLOCK_REALTIME`;
- `time.now()` — alias `time.time()`;
- `time.monotonic()` — `Float` sekund z `CLOCK_MONOTONIC`;
- `time.perf_counter()` — alias monotónního high-resolution měření;
- `time.sleep(seconds)` — uspí aktuální thread alespoň na zadanou dobu a vrátí
  `None`.

`sleep` přijímá hodnotu převoditelnou přes `Float`. Záporná hodnota vyvolá
`ValueError: sleep duration cannot be negative`; NaN, Infinity nebo hodnota,
kterou Linux nelze zapsat jako `timespec`, vyvolá
`ValueError: invalid sleep duration`. Přerušení signálem (`EINTR`) pokračuje se
zbývajícím časem.

Pro intervaly a timeouty používejte `monotonic`/`perf_counter`, protože změna
systémového času je nemůže posunout zpět. `time`/`now` používejte pouze pro
kalendářní timestamp. Modul neobsahuje timezone ani formátování kalendáře.

Čas je ambientní vstup, proto je `load time` v čistém `lsl config` režimu
zakázán. Vestavěný `clock()` zůstává kompatibilním monotónním primitivem;
aplikační kód má preferovat pojmenované API modulu.
