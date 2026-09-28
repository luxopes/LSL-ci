# Knihovna tui

`load tui`

Malý terminálový UI toolkit pro celoobrazovkové klávesnicí ovládané LSL
aplikace. Přepne terminál do cbreak režimu (čtení po klávesách, bez
echa), používá alternativní obrazovku a nabízí ANSI rendering a
normalizovaný dekodér kláves. Čisté LSL nad fd runtime a nástrojem
`stty` — žádné curses.

## Třída Terminal

```lsl
term = tui.Terminal()      # nebo tui.open()
call term.enter()          # cbreak + alternativní obrazovka
call term.leave()          # vždy obnovit terminál!
```

### Kreslení

```lsl
call term.clear()          call term.clear_line()
call term.move(row, col)   call term.text_at(row, col, text)
call term.emit(text)       call term.flush()
```

### Styl

```lsl
call term.reset_style()    call term.set_fg(code)   call term.set_bg(code)
call term.bold()           call term.invert()
```

### Vstup a rozměry

```lsl
call term.query_size()     # aktualizuje term.rows / term.cols
call term.read_byte(timeout)
call term.read_key()       # normalizované klávesy: "up", "down", "char:x", ...
```

## Pomocníci

```lsl
tui.fit(text, width)       # zarovná/oseká text na šířku
tui.open()                 # nový Terminal
```

## Příklad

```lsl
load tui, time

term = tui.Terminal()
call term.enter()
call term.query_size()
call term.move(1, 1)
call term.emit("Ahoj, LSL!")
call term.flush()
call time.sleep(1)
call term.leave()
```

Po chybách a zrušení vždy obnovte terminál — nejlépe přes `try`/`else`
s `term.leave()` v obou větvích.

## Související stránky

- `lsl man fd` — nízkoúrovňové I/O pod tui
- `lsl man httpserver` — síťové aplikace
