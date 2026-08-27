# Hermetic command stand-in for the per-user package installer tests.

hash = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
first = arg(1)
if first == "-f":
    source = arg(3)
    destination = arg(4)
    call writefile(destination, readfile(source))
    call unlink(source)
elif first == "0644":
    exit(0)
elif first.startswith("-"):
    url = arg(arg_count() - 1)
    if url.endswith(".sha256"):
        if "/bad/" in url:
            print "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
        else:
            print hash
        end
    elif url.endswith(".lsl"):
        print "function registry_answer():"
        print "    return 42"
        print "end"
    else:
        exit(22)
    end
else:
    print hash, " ", first
end
