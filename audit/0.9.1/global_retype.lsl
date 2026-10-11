x = 1
function f():
    global x
    x = "hi"
end
call f()
print x, type(x)
