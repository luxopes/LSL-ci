# Modul mdns: ohlášení služby DNS-SD a její nalezení v témže procesu,
# jednou přes Avahi (D-Bus) a jednou vlastním mDNS (multicast se smyčkou
# zpět, i na loopbacku). Jméno instance je jedinečné (PID a čas), výsledky
# se filtrují podle něj a tisknou se jen stálé údaje (žádné adresy).
load mdns
load glib

SERVICE_TYPE = "_lslmdns._tcp"
token = String(glib.getpid()) + "-" + String(glib.monotonic_time() % 1000000)
TXT = {"v": "1", "id": "0123456789abcdef", "name": "Žluťoučký kůň"}

function mine(results, name):
    return [service for service in results if service["name"] == name]
end

function show(label, results, name, port):
    matches = mine(results, name)
    print label, "found:", len(matches) > 0
    if len(matches) == 0:
        return 0
    end
    first = matches[0]
    families = dedup([service["protocol"] for service in matches])
    print label, "port:", first["port"], "type:", first["type"], "domain:", first["domain"]
    print label, "txt:", first["txt"]["v"], first["txt"]["id"], first["txt"]["name"]
    print label, "host .local:", first["host"].endswith(".local"), "ipv4:", "ipv4" in families
    print label, "local:", first["local"], "backend:", first["backend"]
    print label, "consistent:", len([s for s in matches if s["port"] == port and s["address"] != "" and s["interface_name"] != ""]) == len(matches)
    return 0
end

# Pumpuje události, dokud seznam událostí neobsahuje wanted (nejvýš ms).
function wait_for(events, wanted, ms):
    waited = 0
    while not (wanted in events) and waited < ms:
        call mdns.pump(100)
        waited += 100
    end
    return wanted in events
end

function wait_state(handle, wanted, ms):
    waited = 0
    while mdns.state(handle) != wanted and waited < ms:
        call mdns.pump(100)
        waited += 100
    end
    return mdns.state(handle)
end

# --- volba backendu a chyby argumentů ---

try:
    call mdns.use_backend("bonjour")
else:
    print "bad backend:", String(last_error()).startswith("ValueError")
end
try:
    call mdns.announce("x" * 64, SERVICE_TYPE, 1, TXT)
else:
    print "long name:", String(last_error()).startswith("ValueError")
end
try:
    call mdns.announce("ok", "luxdrop", 1, TXT)
else:
    print "bad type:", String(last_error()).startswith("ValueError")
end
try:
    call mdns.state(999999)
else:
    print "bad handle:", String(last_error()).startswith("ValueError")
end

# --- Avahi ---

print "avahi available:", mdns.avahi_available()
call mdns.use_backend("avahi")
print "backend:", mdns.backend()
avahi_name = "LSL mdns test " + token
handle = mdns.announce(avahi_name, SERVICE_TYPE, 47923, TXT)
print "avahi state:", wait_state(handle, "established", 5000)
call show("avahi", mdns.browse(SERVICE_TYPE, 4000), avahi_name, 47923)

avahi_events = []
function on_avahi(event, service):
    if service["name"] == avahi_name:
        avahi_events.append(event)
        if event != "removed":
            avahi_events.append(event + " v=" + service["txt"]["v"])
        end
    end
    return 0
end
watch = mdns.browse_start(SERVICE_TYPE, on_avahi)
print "avahi event added:", wait_for(avahi_events, "added v=1", 5000)
call mdns.pump(500)
call mdns.update_txt(handle, {"v": "2", "id": "0123456789abcdef", "name": "Žluťoučký kůň"})
print "avahi event updated:", wait_for(avahi_events, "updated v=2", 5000)
print "avahi browse after update:", [service["txt"]["v"] for service in mine(mdns.browse(SERVICE_TYPE, 4000), avahi_name)][0]
call mdns.withdraw(handle)
print "avahi event removed:", wait_for(avahi_events, "removed", 5000)
print "avahi browse_stop:", mdns.browse_stop(watch), mdns.browse_stop(watch)
print "avahi after withdraw:", len(mine(mdns.browse(SERVICE_TYPE, 1500), avahi_name))

# --- vlastní mDNS (raw) ---

call mdns.use_backend("raw")
print "backend:", mdns.backend()
raw_name = "LSL mdns raw " + token
raw_handle = mdns.announce(raw_name, SERVICE_TYPE, 47924, TXT)
print "raw state:", mdns.state(raw_handle)
call show("raw", mdns.browse(SERVICE_TYPE, 2500), raw_name, 47924)

raw_events = []
function on_raw(event, service):
    if service["name"] == raw_name:
        raw_events.append(event)
        if event != "removed":
            raw_events.append(event + " v=" + service["txt"]["v"])
        end
    end
    return 0
end
raw_watch = mdns.browse_start(SERVICE_TYPE, on_raw)
print "raw event added:", wait_for(raw_events, "added v=1", 5000)
call mdns.update_txt(raw_handle, {"v": "3", "id": "0123456789abcdef", "name": "Žluťoučký kůň"})
print "raw event updated:", wait_for(raw_events, "updated v=3", 5000)
call mdns.withdraw(raw_handle)
print "raw event removed:", wait_for(raw_events, "removed", 5000)
print "raw browse_stop:", mdns.browse_stop(raw_watch)
print "raw after withdraw:", len(mine(mdns.browse(SERVICE_TYPE, 1500), raw_name))
