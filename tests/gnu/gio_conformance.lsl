# Modul gio na cíli linux-x86_64-gnu: volání metod D-Bus, vlastnosti, chyby
# jako DBusError, odběr signálů, vlastní jméno a signál, sledování jména.
# Bez sběrnice relace se test spustí znovu pod dbus-run-session; bez něj
# vypíše SKIP.
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

DBUS = "org.freedesktop.DBus"
PATH = "/org/freedesktop/DBus"
NAME = "cz.luxai.LslGioTest"
seen = []
appeared = []
vanished = []
custom = []

bus = gio.session_bus()
print("owner of the bus driver:", gio.call(bus, DBUS, PATH, DBUS, "GetNameOwner", "('org.freedesktop.DBus',)"))
try:
    call gio.call(bus, DBUS, PATH, DBUS, "NoSuchMethod", "")
    print("missing method: no error")
else:
    print("missing method:", "UnknownMethod" in String(last_error()))
end
try:
    call gio.call(bus, DBUS, PATH, DBUS, "GetNameOwner", "(this is not a variant")
    print("bad params: no error")
else:
    print("bad params:", "DBusError" in String(last_error()))
end
features = gio.get_property(bus, DBUS, PATH, DBUS, "Features")
print("Features is a list:", features.startswith("["))

function on_owner_changed(sender, path, interface, signal, params):
    if NAME in params:
        seen.append(signal + " " + params)
    end
end

function on_custom(sender, path, interface, signal, params):
    custom.append(interface + "." + signal + params)
end

function on_appeared(name, owner):
    appeared.append(name + " " + owner)
end

function on_vanished(name):
    vanished.append(name)
end

function step():
    if len(appeared) == 0:
        return True
    end
    if len(custom) == 0:
        call gio.emit_signal(bus, "/cz/luxai/Test", "cz.luxai.Test", "Ping", "('hello', 7)")
        return True
    end
    if len(vanished) == 0:
        call gio.call(bus, DBUS, PATH, DBUS, "ReleaseName", "('" + NAME + "',)")
        return True
    end
    call glib.main_quit()
    return False
end

function give_up():
    print("timeout")
    call glib.main_quit()
    return False
end

call gio.subscribe(bus, DBUS, DBUS, "NameOwnerChanged", PATH, on_owner_changed)
call gio.subscribe(bus, "", "cz.luxai.Test", "", "", on_custom)
call gio.watch_name(bus, NAME, on_appeared, on_vanished)
print("RequestName:", gio.call(bus, DBUS, PATH, DBUS, "RequestName", "('" + NAME + "', uint32 0)"))
call glib.timeout_add(5, step)
call glib.timeout_add(10000, give_up)
call glib.main()
print("appeared:", len(appeared), [x.startswith(NAME + " :") for x in appeared])
print("custom signal:", custom)
print("vanished:", vanished)
print("owner changes:", len(seen), [x.startswith("NameOwnerChanged ('" + NAME + "'") for x in seen])
