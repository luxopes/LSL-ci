# Typed stores retain checked public semantics and evaluate operands once.
function require(condition, message):
    if not condition:
        Error(TestFailure: message)
    end
end
function dynamic(value):
    return value
end
function update(collection, index, item):
    collection[index] = item
end
values = IntArray()
values.append(10)
values.append(20)
values.append(30)
alias = values
values[0] = 9223372036854775807
values[-1] = -9223372036854775808
values[True] = 42
call require(alias[0] == 9223372036854775807 and alias[1] == 42 and alias[2] == -9223372036854775808, "raw values, alias, negative/Bool indices")
values[-3] += 1
call require(values[0] == -9223372036854775808, "wrapping compound assignment")
anchor = __lsl_box_int(37)
address = __lsl_address(anchor)
values[0] = address
call require(values[0] == address, "integer/address collision")
call update(values, dynamic(1), dynamic(77))
call require(values[1] == 77, "Any fallback")
for bad in [-9223372036854775808, -4, 3, 9223372036854775807]:
    caught = 0
    try:
        values[Int(bad)] = 1
        caught = 2
    else:
        caught = 1
    end
    call require(caught == 1, "invalid indexed assignment must fail")
end
caught = 0
try:
    call update(values, 0, True)
    caught = 2
else:
    caught = 1
end
call require(caught == 1, "invalid indexed assignment must fail")
caught = 0
try:
    call update(values, 0, dynamic(1.5))
    caught = 2
else:
    caught = 1
end
call require(caught == 1, "invalid indexed assignment must fail")
caught = 0
try:
    call update(values, 1.5, 1)
    caught = 2
else:
    caught = 1
end
call require(caught == 1, "invalid indexed assignment must fail")
empty = IntArray()
caught = 0
try:
    empty[0] = 1
    caught = 2
else:
    caught = 1
end
call require(caught == 1, "invalid indexed assignment must fail")
order = []
function rhs():
    order.append("value")
    return 9
end
function position():
    order.append("index")
    values.clear()
    values.append(0)
    return -1
end
values[position()] = rhs()
call require(len(order) == 2 and order[0] == "value" and order[1] == "index", "evaluation order/count")
call require(len(alias) == 1 and alias[0] == 9, "length/data loaded after index side effects")
call gc()
call require(values[0] == 9, "live collection across GC")
print "QBE typed IntArray stores passed"
