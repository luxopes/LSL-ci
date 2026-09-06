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
require(len(items) == 1 and items[0]["name"] == "textkit", "valid catalog")
require(len(catalog.search(items, "HELP")) == 1, "case-insensitive description search")
require(len(catalog.search(items, "absent")) == 0, "no-match search")
require(catalog.decode("{\"schema\":1,\"packages\":[]}") == [], "empty catalog")
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
require(len(inventory) == 1 and inventory[0]["scope"] == "bundled", "bundled inventory excludes directories/private modules")
require(not exists(home + "/.local"), "read-only inventory created HOME state")
require(catalog.find_installed(inventory, "random") != None, "bundled library check")
require(catalog.find_installed(inventory, "absent") == None, "missing library check")
directory = package.user_directory(home)
call writefile(directory + "/textkit.lsl", "print 1")
call writefile(directory + "/random.lsl", "print 2")
inventory = catalog.installed(home, bundled)
require(len(inventory) == 3, "user inventory")
require(catalog.find_installed(inventory, "random")["scope"] == "bundled", "bundled priority")
require(catalog.find_installed(inventory, "textkit")["scope"] == "user", "user library check")
require(console.clean("ok" + chr(27) + chr(0) + chr(155)) == "ok   ", "terminal control sanitization")
require(manual.resolve("random")[0] == "16-random", "manual topic")
require(manual.lines("abcde" + chr(10) + "žluť", 3) == ["abc", "de", "žlu", "ť"], "Unicode wrapping")
require(manual.find_line(["one", "Two", "three"], "two", 2) == 1, "manual search wraps")
for topic in ["../README", "does-not-exist", "0"]:
    rejected = False
    try:
        call manual.resolve(topic)
    else:
        rejected = True
    end
    require(rejected, "manual unsafe/unknown/ambiguous topic")
end
call update_install.cleanup_scratch(work)
print "catalog and manual conformance passed"
