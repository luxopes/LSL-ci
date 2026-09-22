# Frozen terminal-Snake movement and renderer, shared by both compiler baselines.
load term

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
