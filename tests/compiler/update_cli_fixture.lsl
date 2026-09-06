# lsl: internal-abi
# Test-only old frontend: preserve the actual CLI's raw ABI as well as logic.
# Reports 0.7.6 to exercise the public signed upgrade end to end without
# changing a production manifest or possessing its private signing key.
load update
load update_install

if arg(1) == "version":
    print "0.7.6"
elif arg(1) == "compile":
    exit(run_clean(update_install.dirname(executable_path()) + "/lslc", [arg(2), arg(3)]))
elif arg(1) == "update":
    call update.main("0.7.6")
else:
    exit(2)
end
