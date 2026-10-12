function require(value, message):
    if not value:
        Error(TestFailure: message)
    end
end

# None musí projít přímým výpisem, interpolací i dynamickými hranicemi.
print last_error()
printl "initial error: {last_error()}"
call require(type(last_error()) == "None" and not last_error(), "initial last_error is not None")
call require([last_error()] == [None], "last_error None changed inside a collection")

function current_error():
    return last_error()
end
callback = current_error
call require(callback() == None, "last_error None changed through a callback")
safe:
    call last_error().startswith("unused")
end
call require(last_error().startswith("TypeError:"), "None method call did not raise a catchable error")
saved = last_error()
safe:
    call gc()
end
call require(last_error() == None, "successful safe retained a stale error")
call require(saved.startswith("TypeError:"), "saved error did not survive reset and GC")

for attempt in rang(3):
    safe:
        if attempt != 1:
            Error(Probe: "failure")
        end
    end
    if attempt == 1:
        call require(last_error() == None, "success after failure retained error")
    else:
        call require(last_error() == "Probe: failure", "safe lost the current error")
    end
end
try:
    call require(True, "success")
else:
    Error(TestFailure: "successful try entered else")
end
call require(last_error() == None, "successful try retained error")
try:
    Error(Probe: "try failure")
else:
    call require(last_error() == "Probe: try failure", "try handler lost error")
end
call require(last_error() == "Probe: try failure", "try did not retain caught error")

safe:
    safe:
        Error(Inner: "caught")
    end
    call require(last_error() == "Inner: caught", "nested safe lost inner error")
end
call require(last_error() == None, "successful outer safe retained inner error")
try:
    safe:
        Error(Inner: "caught")
    end
else:
    Error(TestFailure: "handled inner error escaped")
end
call require(last_error() == None, "successful outer try retained inner error")
safe:
    try:
        Error(Inner: "caught")
    else:
        Error(Outer: "propagated")
    end
end
call require(last_error() == "Outer: propagated", "try handler error did not propagate")

function early_return(use_try):
    if use_try:
        try:
            safe:
                Error(Inner: "return")
            end
            return 42
        else:
            return -1
        end
    end
    safe:
        safe:
            Error(Inner: "return")
        end
        return "result"
    end
    return None
end
call require(early_return(False) == "result" and last_error() == None, "safe return did not clear error or preserve result")
call require(early_return(True) == 42 and last_error() == None, "try return did not clear error or preserve result")
for attempt in rang(2):
    safe:
        safe:
            Error(Inner: "continue")
        end
        continue
    end
end
call require(last_error() == None, "safe continue retained error")
loop:
    try:
        safe:
            Error(Inner: "break")
        end
        break
    else:
        Error(TestFailure: "break entered handler")
    end
end
call require(last_error() == None, "try break retained error")

function worker():
    call require(type(last_error()) == "None", "worker inherited main error")
    safe:
        Error(Worker: "isolated")
    end
    call require(last_error() == "Worker: isolated", "worker error missing")
    return None
end
safe:
    Error(Main: "retained")
end
thread = thread_spawn(worker)
call thread_join(thread)
call require(last_error() == "Main: retained", "worker changed main error")
safe:
    call gc()
end
print last_error()
print "last_error types, recovery, nesting, control flow and threads passed"
