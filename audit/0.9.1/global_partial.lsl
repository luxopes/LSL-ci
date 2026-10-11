x = 1
function f():
    if False:
        global x
    end
    x = 2
end
call f()
print x
