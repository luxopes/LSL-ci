function is_even(n):
    if n == 0:
        return True
    end
    return is_odd(n - 1)
end
function is_odd(n):
    if n == 0:
        return False
    end
    return is_even(n - 1)
end
print is_even(4), is_odd(3), is_even(7), is_odd(6)
function all_pos(lst, i):
    if i >= len(lst):
        return True
    end
    if lst[i] <= 0:
        return False
    end
    return all_pos(lst, i + 1)
end
print all_pos([1, 2, 3], 0), all_pos([1, -2, 3], 0)
function fib(n):
    if n < 2:
        return n
    end
    return fib(n - 1) + fib(n - 2)
end
print fib(10), fib(15)
function fsum(lst, i):
    if i >= len(lst):
        return 0.0
    end
    return lst[i] + fsum(lst, i + 1)
end
print fsum([1.5, 2.5, 3.0], 0)
