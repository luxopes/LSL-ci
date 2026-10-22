# Modul glib na cíli linux-x86_64-gnu: hlavní smyčka, časovače, idle, signály
# UNIXu, spouštění programů s hlídáním potomka, chyba v obsluze (program běží
# dál, zpráva jde na stderr) a pomůcky. Nepotřebuje displej ani sběrnici.
load glib

events = {}
ticks = 0
start = glib.monotonic_time()

function note(name):
    events[name] = events.get(name, 0) + 1
end

function on_tick():
    global ticks
    ticks += 1
    call note("tick")
    return ticks < 3
end

function on_idle():
    call note("idle")
    return False
end

function on_usr1():
    call note("usr1")
    return False
end

function on_child(pid, status):
    call note("child status " + String(status))
    return 0
end

function on_bad():
    call note("bad")
    missing = {}
    return missing["key"]
end

function done():
    return events.get("tick", 0) == 3 and events.get("idle", 0) == 1 and events.get("usr1", 0) == 1 and events.get("child status 768", 0) == 1 and events.get("bad", 0) == 1
end

function on_check():
    if done() or glib.monotonic_time() - start > 10000000:
        call glib.main_quit()
        return False
    end
    return True
end

call glib.timeout_add(2, on_tick)
call glib.idle_add(on_idle)
call glib.unix_signal_add(10, on_usr1)
call glib.timeout_add(1, on_bad)
pid = glib.spawn_watched(["sh", "-c", "exit 3"], on_child)
print("spawn gives pid:", pid > 0)
print("missing program:", glib.spawn(["lsl-no-such-program-xyz"]))
call glib.spawn(["sh", "-c", "sleep 0.05; kill -USR1 " + String(glib.getpid())])
call glib.timeout_add(5, on_check)
removed = glib.timeout_add(100000, on_check)
print("source_remove:", glib.source_remove(removed))
call glib.main()
for name in sorted(events.keys()):
    print(name, events[name])
end
print("all events:", done())
print("escape:", glib.markup_escape("<a> & \"b\""))
print("sh in PATH:", glib.find_program_in_path("sh").endswith("/sh"), glib.find_program_in_path("lsl-no-such-program-xyz"))
print("dirs:", len(glib.home_dir()) > 0, len(glib.user_config_dir()) > 0, len(glib.host_name()) > 0)
print("monotonic grows:", glib.monotonic_time() > start)
