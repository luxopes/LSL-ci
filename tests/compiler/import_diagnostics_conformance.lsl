load update_install

cli = arg(1)
work = update_install.private_work("/tmp")
source = work + "/case.lsl"
output = work + "/case"
for text in ["load missing_library_probe\n", "from missing_library_probe load value\n", "load nested\n"]:
    call writefile(source, text)
    call writefile(work + "/nested.lsl", "load missing_library_probe\n")
    for arguments in [[source], ["compile", source, output]]:
        result = capture(cli, arguments)
        diagnostic = result + capture_stderr()
        check(capture_status() == 1, "missing module accepted")
        check("error[E3001]" in diagnostic and "missing_library_probe" in diagnostic, "missing module name/code absent")
        check("lsl install missing_library_probe" in diagnostic and "lsl search missing_library_probe" in diagnostic, "missing installation instructions")
        check(not exists(output), "failed import created an executable")
        if text == "load nested\n":
            check("nested.lsl:1:" in diagnostic, "transitive import source missing")
        else:
            check("case.lsl:1:" in diagnostic, "import location missing")
        end
    end
end
call writefile(work + "/local_probe.lsl", "value = 42\n")
call writefile(source, "load local_probe\nprint local_probe.value\n")
result = capture(cli, [source])
check(capture_status() == 0 and result == "42\n", "local library resolution broken")
call mkdir(work + "/unreadable_probe.lsl")
call writefile(source, "load unreadable_probe\n")
result = capture(cli, [source])
diagnostic = result + capture_stderr()
check(capture_status() == 1 and "error[E3002]" in diagnostic, "unreadable existing module reported as missing")
call rmdir(work + "/unreadable_probe.lsl")
call update_install.cleanup_scratch(work)
print "missing direct/selective/transitive imports explain installation and source location"
