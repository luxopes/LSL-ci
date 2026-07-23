program = executable_path()

function joined_arguments():
    values = []
    index = 1
    while index < arg_count():
        values.append(arg(index))
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
    if arg_count() == 2 and arg(1).endswith("XXXXXX"):
        print "/tmp/lsl-system-managed-temp"
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
        if arg(3) == "/tmp/lsl-system-active-mount":
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
