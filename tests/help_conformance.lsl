function require(condition, message):
    if not condition:
        Error(TestFailure: message)
    end
end

topic = "print"
call require(help(topic) == None, "help return value")
function dynamic_topic(value):
    return help(value)
end
call require(dynamic_topic("len") == None, "runtime help topic")
rejected = False
try:
    call help(42)
else:
    rejected = "TypeError" in last_error()
end
call require(rejected, "non-String help topic")
# Neznámé téma vypíše zprávu a program pokračuje.
call require(help("no_such_help_topic") == None, "unknown help topic")
print "help conformance passed"
