load catalog
load console
load json
load manual
load package
load update_install

function require(condition, message):
    if not condition:
        Error(TestFailure: message)
    end
end

function rejects(value):
    rejected = False
    try:
        call catalog.decode(json.encode(value))
    else:
        rejected = True
    end
    call require(rejected, "unsafe catalog accepted")
end

entry = {"name": "textkit", "version": "1.0.0", "description": "Text helpers", "license": "MIT", "source": "textkit.lsl", "sha256": "c34ee3495502162dcd7281e7c22dade9d59321397fecf344e7098f638208ea87", "size": 49}
items = catalog.decode(json.encode({"schema": 1, "packages": [entry]}))
call require(len(items) == 1 and items[0]["name"] == "textkit", "valid catalog")
call require(len(catalog.search(items, "HELP")) == 1, "case-insensitive description search")
call require(len(catalog.search(items, "absent")) == 0, "no-match search")
call require(catalog.decode("{\"schema\":1,\"packages\":[]}") == [], "empty catalog")
call rejects({"schema": True, "packages": []})
call rejects({"schema": 2, "packages": []})
call rejects({"schema": 1, "packages": [entry, entry]})
for pair in [("name", "../evil"), ("name", "BadName"), ("source", "https://evil.test/x.lsl"), ("source", "../textkit.lsl"), ("sha256", "bad"), ("sha256", 1), ("size", True), ("size", 0), ("size", 1048577), ("description", chr(27) + "[2J"), ("description", "bad" + chr(155)), ("version", "1.0"), ("version", "v1.0.0")]:
    bad = Dictionary(entry)
    bad[pair[0]] = pair[1]
    call rejects({"schema": 1, "packages": [bad]})
end
work = update_install.private_work("/tmp")
home = work + "/empty-home"
call mkdir(home)
bundled = work + "/bundled"
call mkdir(bundled)
call writefile(bundled + "/random.lsl", "print 1")
call writefile(bundled + "/_private.lsl", "print 1")
call mkdir(bundled + "/directory.lsl")
inventory = catalog.installed(home, bundled)
call require(len(inventory) == 1 and inventory[0]["scope"] == "bundled", "bundled inventory excludes directories/private modules")
call require(not exists(home + "/.local"), "read-only inventory created HOME state")
call require(catalog.find_installed(inventory, "random") != None, "bundled library check")
call require(catalog.find_installed(inventory, "absent") == None, "missing library check")
directory = package.user_directory(home)
call writefile(directory + "/textkit.lsl", "print 1")
call writefile(directory + "/random.lsl", "print 2")
inventory = catalog.installed(home, bundled)
call require(len(inventory) == 3, "user inventory")
call require(catalog.find_installed(inventory, "random")["scope"] == "bundled", "bundled priority")
call require(catalog.find_installed(inventory, "textkit")["scope"] == "user", "user library check")
call writefile(directory + "/textkit.lsl.origin", "inventory marker")
inventory = catalog.installed(home, directory)
call require(len(inventory) == 2, "shared user/toolchain directory duplicated")
call require(catalog.find_installed(inventory, "random")["scope"] == "bundled", "shared directory core scope")
call require(catalog.find_installed(inventory, "textkit")["scope"] == "user", "shared directory package provenance scope")
call require(console.clean("ok" + chr(27) + chr(0) + chr(155)) == "ok   ", "terminal control sanitization")
call require(manual.resolve("random")[0] == "random", "manual library topic")
call require(manual.resolve("16-random")[0] == "16-random", "manual numbered chapter")
call require(manual.resolve("env")[0] == "env", "manual env topic")
call require(manual.resolve("requests")[0] == "requests", "manual requests topic")
call require("env.get(name, default_value=None)" in manual.content("docs/developer_guides", manual.resolve("env")), "manual library page content")
call require("raise_for_status" in manual.content("docs/developer_guides", manual.resolve("requests")), "manual requests page content")
call require(manual.lines("abcde" + chr(10) + "žluť", 3) == ["abc", "de", "žlu", "ť"], "Unicode wrapping")
call require(manual.find_line(["one", "Two", "three"], "two", 2) == 1, "manual search wraps")
for topic in ["../README", "does-not-exist", "0"]:
    rejected = False
    try:
        call manual.resolve(topic)
    else:
        rejected = True
    end
    call require(rejected, "manual unsafe/unknown/ambiguous topic")
end
call update_install.cleanup_scratch(work)
print "catalog and manual conformance passed"
