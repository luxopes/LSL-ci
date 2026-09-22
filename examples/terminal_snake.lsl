# Spust v terminalu: lsl snake.lsl
# Potrebna knihovna: lsl install term
load term
load time
load random

function nove_jidlo(had, sirka, vyska):
    volna = [(x, y) for y in rang(vyska) for x in rang(sirka) if (x, y) not in had]
    if len(volna) == 0:
        return None
    end
    return random.choice(volna)
end

function krok(had, smer, jidlo, sirka, vyska):
    hlava = (had[0][0] + smer[0], had[0][1] + smer[1])
    ji = hlava == jidlo

    # Pri beznem pohybu se pole ocasu prave uvolni.
    telo = had
    if not ji:
        telo = had[0:len(had) - 1]
    end

    if hlava[0] < 0 or hlava[0] >= sirka or hlava[1] < 0 or hlava[1] >= vyska or hlava in telo:
        return "naraz"
    end

    call had.insert(0, hlava)
    if ji:
        return "jidlo"
    end
    call had.pop()
    return "pohyb"
end

function vykresli(had, jidlo, sirka, vyska):
    okraj = "+"
    for i in rang(sirka):
        okraj += "-"
    end
    okraj += "+\n"

    obraz = term.home() + okraj
    for y in rang(vyska):
        obraz += "|"
        for x in rang(sirka):
            bod = (x, y)
            if bod == had[0]:
                obraz += "@"
            elif bod in had:
                obraz += "o"
            elif bod == jidlo:
                obraz += "*"
            else:
                obraz += " "
            end
        end
        obraz += "|\n"
    end
    return obraz + okraj + "Skore: " + String(len(had) - 3) + "\nWASD = pohyb | Q = konec\n"
end

function main():
    sirka = 30
    vyska = 15
    interval = 0.15
    velikost = term.size()
    if velikost[0] < vyska + 5 or velikost[1] < sirka + 3:
        Error(GameError: "Zvetsi terminal alespon na 33 sloupcu a 20 radku.")
    end

    had = [(6, 7), (5, 7), (4, 7)]
    smer = (1, 0)
    jidlo = nove_jidlo(had, sirka, vyska)
    klavesy = {"w": (0, -1), "s": (0, 1), "a": (-1, 0), "d": (1, 0)}
    lze_zatocit = True
    konec = "Hra ukoncena."
    chyba = None
    stav = term.raw_full()

    try:
        call term.write(term.clear() + term.cursor(False))
        call term.write(vykresli(had, jidlo, sirka, vyska))
        dalsi_krok = time.monotonic() + interval

        loop:
            # Cteni ceka nejdele do dalsiho kroku, ne donekonecna.
            cekani = max(1, Int((dalsi_krok - time.monotonic()) * 1000.0))
            klavesa = term.getch_timeout(cekani)

            if klavesa == ord("q") or klavesa == ord("Q") or klavesa == 3 or klavesa == 4 or klavesa == -1:
                break
            end

            if klavesa >= 0 and lze_zatocit:
                znak = chr(klavesa).lower()
                if znak in klavesy:
                    novy = klavesy[znak]
                    opacny = (-smer[0], -smer[1])
                    if novy != smer and novy != opacny:
                        smer = novy
                        lze_zatocit = False
                    end
                end
            end

            if time.monotonic() >= dalsi_krok:
                vysledek = krok(had, smer, jidlo, sirka, vyska)
                if vysledek == "naraz":
                    konec = "Naraz! Konec hry."
                    break
                elif vysledek == "jidlo":
                    jidlo = nove_jidlo(had, sirka, vyska)
                end

                call term.write(vykresli(had, jidlo, sirka, vyska))
                if jidlo == None:
                    konec = "Zaplnil jsi celou plochu. Vyhral jsi!"
                    break
                end

                lze_zatocit = True
                dalsi_krok = time.monotonic() + interval
            end
        end
    else:
        chyba = last_error()
    end

    call term.restore(stav)
    call term.write(term.cursor(True) + "\n")
    if chyba != None:
        Error(GameError: String(chyba))
    end
    print konec, "Skore:", len(had) - 3
end

call main()
