# Prerequisite: lsl install term. No explicit collections or frame delays.
# Usage: benchmark FRAMES LOGPATH > /dev/null
load snake_core as game
load term
load time
load fd

function rss():
    for line in fd.read_text_limit("/proc/self/status", 65536).split("\n"):
        if line.startswith("VmRSS:"):
            return Int(line[6:len(line)].strip().split(" ")[0])
        end
    end
    return -1
end

frames = Int(arg(1))
snake = [(6, 7), (5, 7), (4, 7)]
food = (20, 10)
direction = (1, 0)
checksum = 0
started = time.monotonic()
for frame in rang(frames):
    if direction == (1, 0) and snake[0][0] == 28:
        direction = (0, 1)
    elif direction == (0, 1) and snake[0][1] == 13:
        direction = (-1, 0)
    elif direction == (-1, 0) and snake[0][0] == 1:
        direction = (0, -1)
    elif direction == (0, -1) and snake[0][1] == 1:
        direction = (1, 0)
    end
    check(game.krok(snake, direction, food, 30, 15) == "pohyb", "movement collision")
    check(len(snake) == 3, "snake length changed")
    rendered = game.vykresli(snake, food, 30, 15)
    checksum += len(rendered)
    call term.write(rendered)
end
elapsed = time.monotonic() - started
resident = rss()
call writefile(arg(2), "frames=" + String(frames) + "\nseconds=" + String(elapsed) + "\nrss_kib=" + String(resident) + "\nchecksum=" + String(checksum) + "\n")
