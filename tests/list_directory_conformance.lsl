# __lsl_list_directory: jména položek adresáře bez "." a "..", UTF-8,
# chyba FileError pro neexistující cestu (Linux, Windows, macOS).
stamp = String(Int(monotonic() * 1000000.0))
root = "lsl-list-directory-" + stamp
unsafe:
    check(__lsl_mkdir_private(root) == 0, "create test directory")
    call writefile(root + "/alpha.lsl", "x")
    call writefile(root + "/beta.txt", "y")
    call writefile(root + "/čeština s mezerou.txt", "z")
    check(__lsl_mkdir_private(root + "/sub") == 0, "create subdirectory")
    names = __lsl_list_directory(root)
    call names.sort()
    print names
    print len(__lsl_list_directory(root + "/sub"))
    failed = False
    try:
        call __lsl_list_directory(root + "/missing")
    else:
        failed = True
        print last_error()
    end
    print failed
    call rmdir(root + "/sub")
    for name in names:
        call unlink(root + "/" + name)
    end
    call rmdir(root)
    print exists(root)
end
