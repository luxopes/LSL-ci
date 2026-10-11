x = 1
function f():
    global x
    del(x)
end
call f()
print x
