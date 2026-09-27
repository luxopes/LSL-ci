# Optional network test, independent of the default/offline suite.
# Args: secure parent directory, compiled update_cli_fixture, lsl-install,
#       optional expected stable version (default 0.8.6).
load fd
load update_install

function require(condition, message):
    if not condition:
        Error(TestFailure: message)
    end
end

function main():
    expected_version = arg(4)
    if expected_version == None:
        expected_version = "0.8.6"
    end
    work = update_install.private_work(arg(1))
    print "Isolated online updater test:", work
    prefix = work + "/.local"
    call update_install.bounded(arg(3), [prefix], 16777216, 120)
    call writebytes(prefix + "/bin/lsl", readbytes(arg(2)))
    call writefile(prefix + "/bin/unrelated", "untouched")
    # HOME points to this test's private directory, never the real user's.
    output = capture_clean(update_install.tool("env"), ["-i", "HOME=" + work, prefix + "/bin/lsl", "update"])
    call require(capture_status() == 0, "online update failed: " + output + capture_stderr())
    print output.strip()
    call update_install.health(prefix, expected_version, work)
    store = prefix + "/lib/lsl-updates"
    old = update_install.target(store, "previous")
    call update_install.health(old, "0.7.6", work)
    call require(readfile(prefix + "/bin/unrelated") == "untouched", "unrelated binary changed")
    call require(not exists(store + "/pending"), "online transaction left a journal")
    print "Production HTTPS/signature/download/install/activation and retained old compiler passed."
    call update_install.cleanup_scratch(work)
end

call main()
