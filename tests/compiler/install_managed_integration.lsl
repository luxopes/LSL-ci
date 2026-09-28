# Optional integration: SECURE_PARENT OLD_INSTALLER NEW_INSTALLER.
# Parent must have safe ancestors (not /tmp or a group-writable checkout).
load fd
load update_install

function require(condition, message):
    if not condition:
        Error(TestFailure: message)
    end
end

function main():
    work = update_install.private_work(arg(1))
    prefix = work + "/.local"
    call update_install.bounded(arg(2), [prefix], 16777216, 120)
    old_version = update_install.bounded(prefix + "/bin/lsl", ["version"], 1048576, 30).strip()
    call update_install.health(prefix, old_version, work)
    expected_cli = arg(3)[:len(arg(3)) - len("lsl-install")] + "lsl"
    new_version = update_install.bounded(expected_cli, ["version"], 1048576, 30).strip()
    for attempt in rang(2):
        output = capture_clean("/usr/bin/env", ["-i", "HOME=" + work, arg(3), prefix])
        call require(capture_status() == 0, "installer migration/reinstall failed: " + output + capture_stderr())
        call update_install.health(prefix, new_version, work)
        # Při shodné verzi musí instalátor skutečně vyměnit i obsah binárky.
        call require(readbytes(prefix + "/bin/lsl") == readbytes(expected_cli), "same-version reinstall retained the old CLI")
        store = prefix + "/lib/lsl-updates"
        call require(fd.read_text_limit(store + "/previous/version", 64).strip() == old_version, "installer did not retain previous version")
        output = capture_clean("/usr/bin/env", ["-i", "HOME=" + work, prefix + "/bin/lsl", "update", "--rollback"])
        call require(capture_status() == 0, "rollback after reinstall failed: " + output + capture_stderr())
        call update_install.health(prefix, old_version, work)
        original_cli = arg(2)[:len(arg(2)) - len("lsl-install")] + "lsl"
        call require(readbytes(prefix + "/bin/lsl") == readbytes(original_cli), "rollback did not restore original CLI bytes")
    end
    call update_install.cleanup_scratch(work)
    print "Legacy migration, managed reinstall and rollback passed."
end

call main()
