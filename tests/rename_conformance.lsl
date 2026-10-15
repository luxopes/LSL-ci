# __lsl_rename: přejmenování souboru i adresáře, existující cíl se
# nepřepíše, chybějící zdroj je chyba (Linux, Windows, macOS).
stamp = String(Int(monotonic() * 1000000.0))
root = "lsl-rename-" + stamp
unsafe:
    check(__lsl_mkdir_private(root) == 0, "create test directory")
    call writefile(root + "/a.txt", "first")
    call writefile(root + "/b.txt", "second")
    print __lsl_rename(root + "/a.txt", root + "/c.txt") == 0
    print exists(root + "/a.txt"), readfile(root + "/c.txt")
    print __lsl_rename(root + "/c.txt", root + "/b.txt") < 0
    print readfile(root + "/b.txt"), readfile(root + "/c.txt")
    print __lsl_rename(root + "/missing", root + "/d.txt") < 0
    check(__lsl_mkdir_private(root + "/dir") == 0, "create subdirectory")
    call writefile(root + "/dir/inner.txt", "inner")
    print __lsl_rename(root + "/dir", root + "/moved") == 0
    print readfile(root + "/moved/inner.txt")
    call unlink(root + "/moved/inner.txt")
    call rmdir(root + "/moved")
    call unlink(root + "/b.txt")
    call unlink(root + "/c.txt")
    call rmdir(root)
    print exists(root)
end
