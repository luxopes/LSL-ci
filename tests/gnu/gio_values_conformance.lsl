# Modul gio s hodnotami LSL místo textu GVariant: převody oběma směry (bez
# sběrnice), volání a vlastnosti s hodnotami, odběr signálu s hodnotami,
# vlastní objekt na sběrnici volaný z jiného procesu (gdbus) včetně chyby,
# sledování souboru. Bez sběrnice relace se test spustí znovu pod
# dbus-run-session; bez něj vypíše SKIP.
load env
load glib
load gio

if env.get("DBUS_SESSION_BUS_ADDRESS") == None:
    launcher = glib.find_program_in_path("dbus-run-session")
    if launcher == "":
        print("SKIP: no dbus-run-session")
    else:
        exit(run(launcher, ["--", executable_path()]))
    end
    exit(0)
end

function from_text(text):
    variant = gio.variant_parse(text)
    value = gio.variant_to_value(variant)
    call gio.variant_unref(variant)
    return value
end

function to_text(value, signature):
    variant = gio.value_to_variant(value, signature)
    text = gio.variant_text(variant)
    call gio.variant_unref(variant)
    return text
end

print from_text("(uint32 4, 'text', true, 2.5, [1, 2], {'a': <1>, 'b': <'x'>})")
print from_text("<int64 -3>"), from_text("@mi nothing"), from_text("@ms 'yes'")
print from_text("('/org/path', signature 'as', byte 255, int16 -2, uint16 65535, uint64 42, handle 3)")
print to_text(["a", 4], "(su)")
print to_text(["x", "y"], "as"), to_text([], "as")
print to_text({"b": True, "n": ["u", 5], "s": "t", "d": 1.5, "i": 7}, "a{sv}")
print to_text([1, [["a", 2], ["b", 3]], False], "(ia(si)b)")
print to_text(None, "mi"), to_text(3, "mi"), to_text(["o", "/a/b"], "v"), to_text(-9, "x"), to_text(255, "y")
try:
    print to_text("x", "i")
else:
    print "mismatch:", "DBusError" in String(last_error())
end
try:
    print to_text([1], "(ii)")
else:
    print "short tuple:", "DBusError" in String(last_error())
end

DBUS = "org.freedesktop.DBus"
PATH = "/org/freedesktop/DBus"
NAME = "cz.luxai.LslValuesTest"
OBJECT = "/cz/luxai/Values"
IFACE = "cz.luxai.Values"
XML = "<node><interface name='cz.luxai.Values'><method name='Echo'><arg type='s' name='text' direction='in'/><arg type='i' name='n' direction='in'/><arg type='s' direction='out'/><arg type='i' direction='out'/></method><method name='Fail'/><signal name='Note'><arg type='s'/><arg type='a{si}'/></signal></interface></node>"

bus = gio.session_bus()
print gio.call_values(bus, DBUS, PATH, DBUS, "GetNameOwner", [DBUS], "(s)", -1)
print type(gio.get_property_value(bus, DBUS, PATH, DBUS, "Features")) == "List"
print "Features" in gio.get_all_properties(bus, DBUS, PATH, DBUS).keys()
print gio.call_timeout(bus, DBUS, PATH, DBUS, "GetId", "", 2000).startswith("('")
print gio.call_values(bus, DBUS, PATH, DBUS, "RequestName", [NAME, 0], "(su)", -1)

calls = []
notes = []
events = []
child_done = []
directory = "lsl-gio-values-" + String(Int(monotonic() * 1000000.0))
check(mkdir(directory) == 0, "temp directory")

function on_method(sender, path, interface, method, values, invocation):
    calls.append([path, interface, method, values])
    if method == "Echo":
        call gio.return_value(invocation, [values[0], values[1] + 1], "(si)")
    else:
        call gio.return_error(invocation, "cz.luxai.Values.Error", "no can do")
    end
    return 0
end

function on_note(sender, path, interface, signal, values):
    notes.append([interface + "." + signal, values])
end

function on_file(path, event, other):
    events.append([path.split("/")[len(path.split("/")) - 1], event, other])
end

function on_child(pid, status):
    child_done.append(status)
    return 0
end

registration = gio.register_object(bus, OBJECT, XML, on_method)
print registration > 0
call gio.subscribe_values(bus, "", IFACE, "Note", "", on_note)
monitor = gio.file_monitor(directory, on_file)
print monitor != 0

stage = 0
function step():
    global stage
    if stage == 0:
        stage = 1
        call glib.spawn_watched(["sh", "-c", "gdbus call --session --dest " + NAME + " --object-path " + OBJECT + " --method " + IFACE + ".Echo hello 41 > " + directory + "/echo.txt; gdbus call --session --dest " + NAME + " --object-path " + OBJECT + " --method " + IFACE + ".Fail > " + directory + "/fail.txt 2>&1; rm " + directory + "/echo.txt " + directory + "/fail.txt"], on_child)
        return True
    elif stage == 1:
        if len(child_done) == 0:
            return True
        end
        stage = 2
        call gio.emit_values(bus, OBJECT, IFACE, "Note", ["hi", {"k": 1}], "(sa{si})")
        return True
    elif stage == 2:
        if len(notes) == 0:
            return True
        end
        stage = 3
        call writefile(directory + "/watched.txt", "x")
        return True
    end
    if len([e for e in events if e[0] == "watched.txt" and e[1] == gio.FILE_CREATED]) == 0:
        return True
    end
    call glib.main_quit()
    return False
end

function give_up():
    print "timeout", stage, child_done, notes, events
    call glib.main_quit()
    return False
end

call glib.timeout_add(20, step)
call glib.timeout_add(15000, give_up)
call glib.main()

print calls
print notes
echo_lines = [e for e in events if e[0] == "echo.txt"]
print len(echo_lines) > 0, [e for e in events if e[0] == "watched.txt"][0]
print gio.unregister_object(bus, registration)
call gio.file_monitor_cancel(monitor)
call unlink(directory + "/watched.txt")
print rmdir(directory)
print "done"
