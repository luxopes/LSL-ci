program = executable_path()

function dirname(path):
    index = len(path) - 1
    while index >= 0 and path[index] != "/":
        index -= 1
    end
    if index <= 0:
        return "/"
    end
    return path[0:index]
end

server_root = dirname(program)

function stable_argument(value):
    if value == server_root:
        return "/tmp"
    elif value.startswith(server_root + "/"):
        return "/tmp/lsl-" + value[len(server_root) + 1:len(value)]
    end
    return value
end

function joined_arguments():
    values = []
    index = 1
    while index < arg_count():
        values.append(stable_argument(arg(index)))
        index += 1
    end
    return "|".join(values)
end

if program.endswith("-apt"):
    print "apt", joined_arguments()
    exit(0)
elif program.endswith("-systemctl"):
    if arg(1) == "is-active":
        if arg(3) == "active.service":
            exit(0)
        elif arg(3) == "error.service":
            exit(4)
        end
        exit(3)
    elif arg(arg_count() - 1) == "fail.service":
        exit(5)
    end
    print "systemctl", joined_arguments()
    exit(0)
elif program.endswith("-account"):
    if arg(1) == "group":
        if arg(2) == "existing":
            exit(0)
        end
        exit(2)
    elif arg(1) == "-u":
        if arg(2) == "existing":
            exit(0)
        end
        exit(1)
    end
    print "account", joined_arguments()
    exit(0)
elif program.endswith("-file-tool"):
    if arg_count() == 3 and arg(1) == "-d" and arg(2).endswith("XXXXXX"):
        temporary = arg(2)[0:len(arg(2)) - 6] + "ABC123"
        call __lsl_mkdir_private(temporary)
        print temporary
        exit(0)
    elif arg(1) == "-f":
        source = arg(3)
        destination = arg(4)
        call writefile(destination, readfile(source))
        call unlink(source)
    end
    print "file", joined_arguments()
    exit(0)
elif program.endswith("-mount-tool"):
    if arg(1) == "-q":
        if arg(3) == server_root + "/system-active-mount":
            exit(0)
        end
        exit(1)
    end
    print "mount", joined_arguments()
    exit(0)
elif program.endswith("-lux"):
    if arg(1) == "status":
        print "generation: test-generation"
    elif arg(1) == "generations":
        print "* test-generation"
    else:
        print "lux", joined_arguments()
    end
    exit(0)
end

exit(127)
