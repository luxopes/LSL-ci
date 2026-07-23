# Hermetic Lux/apt stand-in selected by argv shape.
if arg_count() == 3:
    action = arg(1)
    package = arg(2)
    if package.startswith("lux-"):
        print "lux", action, package
        exit(0)
    end
    exit(42)
end

arguments = []
index = 1
while index < arg_count():
    arguments.append(arg(index))
    index += 1
end
print "apt", "|".join(arguments)
if arguments[len(arguments) - 1] == "apt-fail":
    exit(43)
end
