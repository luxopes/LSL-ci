x = 0
function f():
    global x
    for x in [1, 2]:
        print x
    end
end
call f()
print x
