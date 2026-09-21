# Install optional graphics first: lsl install display ; lsl install gfx
# Run: lsl examples/snake.lsl. Arrow keys turn, Escape closes the game.
load display
load gfx
load input
load random
load time

cols = 24
rows = 18
cell = 24
step = 0.12

function new_food(snake):
    free = [(x, y) for y in rang(rows) for x in rang(cols) if (x, y) not in snake]
    if len(free) == 0:
        return None
    end
    return random.choice(free)
end

snake = [(6, 9), (5, 9), (4, 9)]
direction = (1, 0)
food = new_food(snake)
keys = {input.key_left: (-1, 0), input.key_right: (1, 0), input.key_up: (0, -1), input.key_down: (0, 1)}

d = display.open(cols * cell, rows * cell, "Snake LSL")
screen = gfx.surface(cols * cell, rows * cell, gfx.rgb(20, 24, 30))
running = True
can_turn = True
next_move = time.monotonic() + step

while running and not d.should_close():
    for event in d.poll():
        if event[0] == "close":
            running = False
        elif event[0] == "key" and event[2] == input.press:
            key = event[1]
            if key == input.key_esc:
                running = False
            elif key in keys and can_turn:
                wanted = keys[key]
                opposite = (-direction[0], -direction[1])
                if wanted != direction and wanted != opposite:
                    direction = wanted
                    can_turn = False
                end
            end
        end
    end
    if not running or d.should_close():
        break
    end

    now = time.monotonic()
    if now >= next_move:
        next_move = now + step
        can_turn = True
        head = (snake[0][0] + direction[0], snake[0][1] + direction[1])
        eating = head == food

        # Ocas při běžném kroku uvolní svoje políčko.
        body = snake
        if not eating:
            body = snake[0:len(snake) - 1]
        end
        if head[0] < 0 or head[0] >= cols or head[1] < 0 or head[1] >= rows or head in body:
            print "Konec hry!"
            break
        end

        call snake.insert(0, head)
        if eating:
            food = new_food(snake)
            if food == None:
                print "Vyhrál jsi!"
                break
            end
        else:
            call snake.pop()
        end
    end

    call screen.clear(gfx.rgb(20, 24, 30))
    call screen.fill_rect(food[0] * cell, food[1] * cell, cell - 2, cell - 2, gfx.rgb(240, 80, 80))
    for part in snake:
        call screen.fill_rect(part[0] * cell, part[1] * cell, cell - 2, cell - 2, gfx.rgb(80, 220, 120))
    end
    call d.present(screen.pixels, screen.width, screen.height)
    call d.wait_frame()
end

call d.close()
print "Skóre:", len(snake) - 3
