# DNS-SD (Bonjour/Zeroconf) pro cíl linux-x86_64-gnu: ohlášení služby
# (announce/update_txt/withdraw) a hledání služeb (blokující browse a
# událostní browse_start pro hlavní smyčku GLib).
#
# Dva backendy: Avahi přes systémovou sběrnici D-Bus (org.freedesktop.Avahi,
# výchozí, když démon běží) a vlastní mDNS přes UDP multicast
# 224.0.0.251:5353 (modul net), když Avahi na sběrnici není.
# use_backend("avahi" | "raw" | "auto") volbu vynutí.
#
# Modul je psaný v běžném (tagged) ABI nad moduly gio, glib a net, takže
# sám nevolá C a hodnoty jsou obyčejné hodnoty LSL. Chyby: MDNSError
# (Avahi, soket), ValueError (špatné argumenty).
#
# Výsledek hledání je Dictionary: name, type, domain, host, address
# (IPv6 link-local se zónou "fe80::…%wlan0"), port, txt (String → String),
# interface (index), interface_name, protocol ("ipv4"/"ipv6"), local (služba
# z tohoto stroje) a backend.
load gio
load glib
load net
load time

AVAHI = "org.freedesktop.Avahi"
AVAHI_SERVER = "org.freedesktop.Avahi.Server"
AVAHI_GROUP = "org.freedesktop.Avahi.EntryGroup"
AVAHI_BROWSER = "org.freedesktop.Avahi.ServiceBrowser"
AVAHI_RESOLVER = "org.freedesktop.Avahi.ServiceResolver"
# AVAHI_LOOKUP_RESULT_LOCAL: záznam pochází z tohoto stroje
AVAHI_RESULT_LOCAL = 8
GROUP_STATES = ["uncommitted", "registering", "established", "collision", "failure"]

MDNS_GROUP = "224.0.0.251"
MDNS_PORT = 5353
TYPE_A = 1
TYPE_PTR = 12
TYPE_TXT = 16
TYPE_AAAA = 28
TYPE_SRV = 33
TYPE_ANY = 255
# Doby platnosti záznamů (RFC 6762 10): jméno stroje a SRV 120 s, ostatní 75 min.
TTL_HOST = 120
TTL_OTHER = 4500

# Stav modulu (zápis do globálních proměnných z funkce je lokální, proto
# slovníky, které se jen mění).
config = {"backend": "auto", "avahi": None}
counter = {"next": 1}
# handle -> záznam ohlášené služby, id -> záznam hledání
services = {}
browsers = {}
# Avahi: spojení, cesta objektu -> [druh, id, klíč] a signály objektů,
# jejichž cesta ještě není známá (démon je může poslat dřív, než přijde
# odpověď metody, která objekt vytvořila).
avahi = {"bus": 0, "subscribed": False}
avahi_paths = {}
avahi_pending = {}
interface_names = {}
# Vlastní mDNS: soket, rozhraní IPv4 a mezipaměť záznamů z odpovědí.
raw = {"fd": -1, "watch": 0, "timer": 0, "links": [], "links_at": 0.0, "host": []}
cache = {"ptr": {}, "srv": {}, "txt": {}, "addr": {}}

# --- volba backendu ---

# "auto" (Avahi, když běží, jinak vlastní mDNS), "avahi" nebo "raw".
# Platí pro následující announce/browse; už běžící zůstávají na svém.
function use_backend(name):
    if name != "auto" and name != "avahi" and name != "raw":
        Error(ValueError: "unknown mDNS backend " + String(name) + " (use auto, avahi or raw)")
    end
    config["backend"] = name
    return name
end

# Backend, který použije další announce/browse: "avahi" nebo "raw".
# Vynucený "avahi" bez démona na sběrnici je MDNSError.
function backend():
    if config["backend"] == "raw":
        return "raw"
    end
    if avahi_available():
        return "avahi"
    end
    if config["backend"] == "avahi":
        Error(MDNSError: "Avahi is not available on the system bus")
    end
    return "raw"
end

# Běží démon Avahi na systémové sběrnici? (zjistí se jednou)
function avahi_available():
    if config["avahi"] == None:
        ok = False
        try:
            bus = gio.system_bus()
            reply = gio.call_values(bus, AVAHI, "/", AVAHI_SERVER, "GetState", [], "", 2000)
            # 1 = registering, 2 = running
            ok = reply[0] == 1 or reply[0] == 2
        else:
            ok = False
        end
        config["avahi"] = ok
    end
    return config["avahi"]
end

function _next_id():
    value = counter["next"]
    counter["next"] = value + 1
    return value
end

function _error_text(error):
    text = String(error)
    for prefix in ["MDNSError: ", "DBusError: ", "OSError: "]:
        if text.startswith(prefix):
            text = text[len(prefix):len(text)]
        end
    end
    if text.startswith("GDBus.Error:"):
        text = text[12:len(text)]
    end
    return text
end

# --- kontrola a převod argumentů ---

function _domain(domain):
    text = String(domain)
    while text.endswith("."):
        text = text[0:len(text) - 1]
    end
    if text == "":
        return "local"
    end
    return text
end

function _check_type(service_type):
    parts = String(service_type).split(".")
    if len(parts) != 2 or not parts[0].startswith("_") or (parts[1] != "_tcp" and parts[1] != "_udp") or len(parts[0]) < 2:
        Error(ValueError: "service type must look like _name._tcp or _name._udp: " + String(service_type))
    end
    return parts
end

function _check_name(name):
    if type(name) != "String" or name == "":
        Error(ValueError: "service name must be a non-empty String")
    end
    if len(net.bytes(name)) > 63:
        Error(ValueError: "service name is longer than 63 bytes: " + name)
    end
    return name
end

function _check_port(port):
    if type(port) != "Int" or port < 0 or port > 65535:
        Error(ValueError: "port must be an Int 0-65535")
    end
    return port
end

# Položky TXT jako ByteArray "klíč=hodnota" (nejvýš 255 bajtů každá).
function _txt_entries(txt):
    if type(txt) != "Dictionary":
        Error(ValueError: "TXT must be a Dictionary of String to String")
    end
    entries = []
    for key in txt.keys():
        name = String(key)
        if name == "" or name.find("=") >= 0:
            Error(ValueError: "invalid TXT key: " + name)
        end
        entry = net.bytes(name + "=" + String(txt[key]))
        if len(entry) > 255:
            Error(ValueError: "TXT entry is longer than 255 bytes: " + name)
        end
        entries.append(entry)
    end
    return entries
end

# TXT pro Avahi (aay): seznam seznamů bajtů.
function _txt_lists(entries):
    result = []
    for entry in entries:
        result.append([value for value in entry])
    end
    return result
end

# Slovník TXT z položek (ByteArray); první výskyt klíče platí (RFC 6763 6.4).
function _txt_dict(entries):
    result = {}
    for entry in entries:
        size = len(entry)
        if size == 0:
            continue
        end
        split = -1
        index = 0
        while index < size:
            if entry[index] == 61:
                split = index
                break
            end
            index += 1
        end
        key = ""
        value = ""
        if split < 0:
            key = net.text(entry)
        else:
            key = net.text(entry, 0, split)
            value = net.text(entry, split + 1, size - split - 1)
        end
        if key != "" and not (key in result):
            result[key] = value
        end
    end
    return result
end

function _bytes_of(values):
    result = ByteArray()
    for value in values:
        result.append(value)
    end
    return result
end

# --- jména rozhraní ---

function interface_name(index):
    if index in interface_names:
        return interface_names[index]
    end
    for entry in net.interfaces():
        safe:
            interface_names[net.interface_index(entry[0])] = entry[0]
        end
    end
    return interface_names.get(index, "")
end

function _scoped(address, name):
    if address.lower().startswith("fe80") and name != "" and address.find("%") < 0:
        return address + "%" + name
    end
    return address
end

# --- veřejné API: ohlášení ---

# Ohlásí službu: name je jméno instance (UTF-8, nejvýš 63 bajtů), service_type
# "_luxdrop._tcp", txt Dictionary String → String. Vrací handle (Int) pro
# update_txt, withdraw a state. Neblokuje: Avahi jméno ověří (probing) na
# pozadí, výsledek ukáže state(handle).
function announce(name, service_type, port, txt=None, domain="local"):
    if txt == None:
        txt = {}
    end
    call _check_name(name)
    call _check_type(service_type)
    call _check_port(port)
    entries = _txt_entries(txt)
    handle = _next_id()
    record = {"handle": handle, "name": name, "type": service_type, "domain": _domain(domain), "port": port, "txt": txt, "entries": entries, "state": "registering", "path": "", "backend": backend(), "announce_at": []}
    if record["backend"] == "avahi":
        call _avahi_announce(record)
    else:
        call _raw_announce(record)
    end
    services[handle] = record
    return handle
end

# Nové TXT ohlášené služby (Avahi UpdateServiceTxt, vlastní mDNS znovu ohlásí).
function update_txt(handle, txt):
    record = _service(handle)
    entries = _txt_entries(txt)
    if record["backend"] == "avahi":
        call _avahi_call(record["path"], AVAHI_GROUP, "UpdateServiceTxt", [-1, -1, 0, record["name"], record["type"], record["domain"], _txt_lists(entries)], "(iiusssaay)")
    else:
        record["entries"] = entries
        call _raw_schedule(record)
    end
    record["txt"] = txt
    return True
end

# Stáhne službu (Avahi zruší skupinu, vlastní mDNS pošle „goodbye“ s TTL 0).
function withdraw(handle):
    record = _service(handle)
    if record["backend"] == "avahi":
        path = record["path"]
        safe:
            call _avahi_call(path, AVAHI_GROUP, "Free", [], "")
        end
        if path in avahi_paths:
            del(avahi_paths[path])
        end
    else:
        call _raw_goodbye(record)
    end
    del(services[handle])
    return True
end

# Stav ohlášení: "registering" (Avahi ověřuje jméno), "established",
# "collision" (jméno v síti už je, zvolte jiné), "failure", "uncommitted".
function state(handle):
    record = _service(handle)
    if record["backend"] == "avahi":
        safe:
            reply = _avahi_call(record["path"], AVAHI_GROUP, "GetState", [], "")
            if reply[0] >= 0 and reply[0] < len(GROUP_STATES):
                record["state"] = GROUP_STATES[reply[0]]
            end
        end
    end
    return record["state"]
end

function _service(handle):
    if not (handle in services):
        Error(ValueError: "unknown mDNS service handle " + String(handle))
    end
    return services[handle]
end

# --- veřejné API: hledání ---

# Blokující hledání: čeká nejvýš timeout_ms (Avahi skončí dřív, když má
# vše v mezipaměti vyřešené) a vrátí List slovníků služby. Stejná služba
# přijde pro každé rozhraní a protokol zvlášť. V GUI použijte browse_start.
function browse(service_type, timeout_ms=3000, domain="local"):
    id = _browse_open(service_type, domain, None)
    browser = browsers[id]
    limit = time.monotonic() + Float(timeout_ms) / 1000.0
    loop:
        now = time.monotonic()
        if now >= limit:
            break
        end
        if browser["backend"] == "avahi" and browser["all_for_now"] and len(browser["resolving"]) == 0:
            break
        end
        if browser["failed"] != "":
            break
        end
        call _wait(Int((limit - now) * 1000.0) + 1)
    end
    results = List(browser["results"].values())
    call browse_stop(id)
    if browser["failed"] != "" and len(results) == 0:
        Error(MDNSError: "browse " + String(service_type) + ": " + browser["failed"])
    end
    return results
end

# Hledání v hlavní smyčce GLib: handler(event, service) s event "added",
# "updated" (změna TXT nebo adresy) a "removed" (service s posledními
# známými údaji). Vrací id pro browse_stop. Program musí točit hlavní
# smyčku (gtk.main, glib.main) nebo volat pump().
function browse_start(service_type, handler, domain="local"):
    if type(handler) != "Function":
        Error(ValueError: "browse_start handler must be a Function")
    end
    return _browse_open(service_type, domain, handler)
end

function browse_stop(id):
    if not (id in browsers):
        return False
    end
    browser = browsers[id]
    if browser["backend"] == "avahi":
        for key in List(browser["resolvers"].keys()):
            call _avahi_free(browser["resolvers"][key], AVAHI_RESOLVER)
        end
        call _avahi_free(browser["path"], AVAHI_BROWSER)
    end
    del(browsers[id])
    return True
end

# Zpracuje události mDNS (a celé hlavní smyčky GLib) po dobu timeout_ms;
# pro programy bez glib.main/gtk.main, které služby ohlašují nebo sledují.
function pump(timeout_ms=0):
    limit = time.monotonic() + Float(timeout_ms) / 1000.0
    call glib.pump()
    loop:
        now = time.monotonic()
        if now >= limit:
            break
        end
        call _wait(Int((limit - now) * 1000.0) + 1)
    end
    return True
end

# Čeká na data soketu (nebo krátce spí) a projde hlavní smyčku.
function _wait(remaining_ms):
    step = remaining_ms
    if step > 20:
        step = 20
    end
    if raw["fd"] >= 0:
        call net.wait(raw["fd"], net.POLLIN, step)
    else:
        call time.sleep(Float(step) / 1000.0)
    end
    call glib.pump()
    return 0
end

function _browse_open(service_type, domain, handler):
    call _check_type(service_type)
    id = _next_id()
    browser = {"id": id, "type": service_type, "domain": _domain(domain), "handler": handler, "results": {}, "backend": backend(), "path": "", "resolvers": {}, "resolving": {}, "all_for_now": False, "failed": "", "next_query": 0.0, "interval": 1.0}
    browsers[id] = browser
    try:
        if browser["backend"] == "avahi":
            call _avahi_browse(browser)
        else:
            call _raw_browse(browser)
        end
    else:
        del(browsers[id])
        Error(MDNSError: _error_text(last_error()))
    end
    return id
end

# Předá událost obsluze; chyba obsluhy hledání nezastaví.
function _emit(browser, event, service):
    handler = browser["handler"]
    if handler == None:
        return 0
    end
    try:
        call handler(event, service)
    else:
        call eprint("mdns handler error: " + String(last_error()))
    end
    return 0
end

# Nové výsledky hledání proti předchozím: added, updated, removed.
function _publish(browser, results):
    previous = browser["results"]
    browser["results"] = results
    for key in results.keys():
        if not (key in previous):
            call _emit(browser, "added", results[key])
        elif previous[key] != results[key]:
            call _emit(browser, "updated", results[key])
        end
    end
    for key in previous.keys():
        if not (key in results):
            call _emit(browser, "removed", previous[key])
        end
    end
    return 0
end

# --- Avahi ---

function _avahi_bus():
    if not avahi["subscribed"]:
        avahi["bus"] = gio.system_bus()
        call gio.subscribe_values(avahi["bus"], AVAHI, "", "", "", _avahi_signal)
        avahi["subscribed"] = True
    end
    return avahi["bus"]
end

function _avahi_call(path, interface, method, values, signature):
    bus = _avahi_bus()
    reply = []
    try:
        reply = gio.call_values(bus, AVAHI, path, interface, method, values, signature, 10000)
    else:
        Error(MDNSError: "Avahi " + method + ": " + _error_text(last_error()))
    end
    return reply
end

function _avahi_free(path, interface):
    if path == "":
        return 0
    end
    safe:
        call _avahi_call(path, interface, "Free", [], "")
    end
    if path in avahi_paths:
        del(avahi_paths[path])
    end
    return 0
end

# Nový objekt Avahi: zapamatuje cestu a přehraje signály, které přišly dřív.
function _avahi_bind(path, route):
    avahi_paths[path] = route
    if path in avahi_pending:
        early = avahi_pending[path]
        del(avahi_pending[path])
        for item in early:
            call _avahi_route(route, item[0], item[1])
        end
    end
    return path
end

function _avahi_signal(sender, path, interface, signal, values):
    if path in avahi_paths:
        call _avahi_route(avahi_paths[path], signal, values)
        return 0
    end
    if len(avahi_pending) > 64:
        call avahi_pending.clear()
    end
    if not (path in avahi_pending):
        avahi_pending[path] = []
    end
    avahi_pending[path].append([signal, values])
    return 0
end

function _avahi_route(route, signal, values):
    kind = route[0]
    if kind == "group":
        if signal == "StateChanged" and route[1] in services:
            state_index = values[0]
            if state_index >= 0 and state_index < len(GROUP_STATES):
                services[route[1]]["state"] = GROUP_STATES[state_index]
            end
        end
        return 0
    end
    if not (route[1] in browsers):
        return 0
    end
    browser = browsers[route[1]]
    if kind == "browser":
        if signal == "ItemNew":
            call _avahi_item_new(browser, values)
        elif signal == "ItemRemove":
            call _avahi_item_remove(browser, values)
        elif signal == "AllForNow":
            browser["all_for_now"] = True
        elif signal == "Failure":
            browser["failed"] = String(values[0])
        end
    elif kind == "resolver":
        key = route[2]
        if signal == "Found":
            call _avahi_found(browser, key, values)
        elif signal == "Failure":
            if key in browser["resolving"]:
                del(browser["resolving"][key])
            end
        end
    end
    return 0
end

function _avahi_key(values):
    return String(values[0]) + chr(1) + String(values[1]) + chr(1) + values[2] + chr(1) + values[3].lower() + chr(1) + values[4].lower()
end

# ItemNew(interface, protocol, name, type, domain, flags): vlastní resolver
# pro každou dvojici rozhraní a protokolu; adresa stejné rodiny.
function _avahi_item_new(browser, values):
    key = _avahi_key(values)
    if key in browser["resolvers"]:
        return 0
    end
    browser["resolving"][key] = True
    safe:
        reply = _avahi_call("/", AVAHI_SERVER, "ServiceResolverNew", [values[0], values[1], values[2], values[3], values[4], values[1], 0], "(iisssiu)")
        browser["resolvers"][key] = reply[0]
        call _avahi_bind(reply[0], ["resolver", browser["id"], key])
    end
    if not (key in browser["resolvers"]):
        del(browser["resolving"][key])
    end
    return 0
end

function _avahi_item_remove(browser, values):
    key = _avahi_key(values)
    if key in browser["resolvers"]:
        call _avahi_free(browser["resolvers"][key], AVAHI_RESOLVER)
        del(browser["resolvers"][key])
    end
    if key in browser["resolving"]:
        del(browser["resolving"][key])
    end
    if key in browser["results"]:
        removed = browser["results"][key]
        del(browser["results"][key])
        call _emit(browser, "removed", removed)
    end
    return 0
end

# Found(interface, protocol, name, type, domain, host, aprotocol, address,
# port, txt, flags). Resolver zůstává živý a pošle Found znovu při změně.
function _avahi_found(browser, key, values):
    if key in browser["resolving"]:
        del(browser["resolving"][key])
    end
    entries = []
    for entry in values[9]:
        entries.append(_bytes_of(entry))
    end
    name = interface_name(values[0])
    protocol = "ipv4"
    if values[6] == 1:
        protocol = "ipv6"
    end
    service = {"name": values[2], "type": values[3], "domain": values[4], "host": values[5], "address": _scoped(values[7], name), "port": values[8], "txt": _txt_dict(entries), "interface": values[0], "interface_name": name, "protocol": protocol, "local": (values[10] & AVAHI_RESULT_LOCAL) != 0, "backend": "avahi"}
    results = browser["results"].copy()
    results[key] = service
    call _publish(browser, results)
    return 0
end

function _avahi_browse(browser):
    reply = _avahi_call("/", AVAHI_SERVER, "ServiceBrowserNew", [-1, -1, browser["type"], browser["domain"], 0], "(iissu)")
    browser["path"] = reply[0]
    call _avahi_bind(reply[0], ["browser", browser["id"]])
    return 0
end

function _avahi_announce(record):
    reply = _avahi_call("/", AVAHI_SERVER, "EntryGroupNew", [], "")
    path = reply[0]
    record["path"] = path
    call _avahi_bind(path, ["group", record["handle"]])
    try:
        call _avahi_call(path, AVAHI_GROUP, "AddService", [-1, -1, 0, record["name"], record["type"], record["domain"], "", record["port"], _txt_lists(record["entries"])], "(iiussssqaay)")
        call _avahi_call(path, AVAHI_GROUP, "Commit", [], "")
    else:
        message = _error_text(last_error())
        call _avahi_free(path, AVAHI_GROUP)
        Error(MDNSError: message)
    end
    return 0
end

# --- vlastní mDNS: kódování zpráv DNS ---

function _put16(buffer, value):
    buffer.append((value >> 8) & 255)
    buffer.append(value & 255)
    return 0
end

function _put32(buffer, value):
    buffer.append((value >> 24) & 255)
    buffer.append((value >> 16) & 255)
    buffer.append((value >> 8) & 255)
    buffer.append(value & 255)
    return 0
end

function _put_bytes(buffer, data):
    for value in data:
        buffer.append(value)
    end
    return 0
end

# Jméno jako posloupnost návěští (bez komprese; návěští smí obsahovat tečku).
function _put_name(buffer, labels):
    for label in labels:
        data = net.bytes(label)
        if len(data) == 0 or len(data) > 63:
            Error(ValueError: "invalid DNS label: " + label)
        end
        buffer.append(len(data))
        call _put_bytes(buffer, data)
    end
    buffer.append(0)
    return 0
end

function _u16(data, position):
    return (data[position] << 8) | data[position + 1]
end

function _u32(data, position):
    return (data[position] << 24) | (data[position + 1] << 16) | (data[position + 2] << 8) | data[position + 3]
end

# [návěští, pozice za jménem]; ukazatele komprese se sledují (nejvýš 32).
function _read_name(data, start):
    labels = []
    position = start
    after = -1
    jumps = 0
    loop:
        if position >= len(data):
            Error(ValueError: "truncated DNS name")
        end
        length = data[position]
        if length == 0:
            position += 1
            break
        end
        if (length & 192) == 192:
            if position + 1 >= len(data) or jumps > 32:
                Error(ValueError: "bad DNS name pointer")
            end
            if after < 0:
                after = position + 2
            end
            position = ((length & 63) << 8) | data[position + 1]
            jumps += 1
            continue
        end
        if position + 1 + length > len(data):
            Error(ValueError: "truncated DNS label")
        end
        labels.append(net.text(data, position + 1, length))
        position += 1 + length
    end
    if after < 0:
        after = position
    end
    return [labels, after]
end

function _name_key(labels):
    return chr(1).join([label.lower() for label in labels])
end

function _record(labels, record_type, flush, ttl, rdata):
    buffer = ByteArray()
    call _put_name(buffer, labels)
    call _put16(buffer, record_type)
    record_class = 1
    if flush:
        record_class = 32769
    end
    call _put16(buffer, record_class)
    call _put32(buffer, ttl)
    call _put16(buffer, len(rdata))
    call _put_bytes(buffer, rdata)
    return buffer
end

function _question(labels, record_type):
    buffer = ByteArray()
    call _put_name(buffer, labels)
    call _put16(buffer, record_type)
    call _put16(buffer, 1)
    return buffer
end

function _message(id, flags, questions, answers, additional):
    buffer = ByteArray()
    call _put16(buffer, id)
    call _put16(buffer, flags)
    call _put16(buffer, len(questions))
    call _put16(buffer, len(answers))
    call _put16(buffer, 0)
    call _put16(buffer, len(additional))
    for part in questions:
        call _put_bytes(buffer, part)
    end
    for part in answers:
        call _put_bytes(buffer, part)
    end
    for part in additional:
        call _put_bytes(buffer, part)
    end
    return buffer
end

function _hex(value):
    digits = "0123456789abcdef"
    if value == 0:
        return "0"
    end
    text = ""
    rest = value
    while rest > 0:
        text = digits[rest & 15] + text
        rest = rest >> 4
    end
    return text
end

# Text adresy IPv6 (RFC 5952: nejdelší běh nul zkrácený na "::").
function _ipv6_text(data, start):
    groups = []
    for index in range(8):
        groups.append(_u16(data, start + index * 2))
    end
    best = -1
    best_length = 0
    index = 0
    while index < 8:
        if groups[index] == 0:
            stop = index
            while stop < 8 and groups[stop] == 0:
                stop += 1
            end
            if stop - index > best_length and stop - index >= 2:
                best = index
                best_length = stop - index
            end
            index = stop
        else:
            index += 1
        end
    end
    words = [_hex(group) for group in groups]
    if best < 0:
        return ":".join(words)
    end
    return ":".join(words[0:best]) + "::" + ":".join(words[best + best_length:8])
end

function _ipv4_bytes(text):
    result = ByteArray()
    for part in text.split("."):
        result.append(Int(part))
    end
    return result
end

function _ipv4_word(text):
    parts = text.split(".")
    if len(parts) != 4:
        return -1
    end
    value = 0
    for part in parts:
        value = (value << 8) | Int(part)
    end
    return value
end

# --- vlastní mDNS: rozhraní a soket ---

# Rozhraní IPv4 pro multicast: [jméno, adresa, maska, index]; UP a
# MULTICAST, nebo loopback (služby na tomtéž stroji).
function _links():
    now = time.monotonic()
    if len(raw["links"]) > 0 and now - raw["links_at"] < 30.0:
        return raw["links"]
    end
    links = []
    for entry in net.interfaces():
        flags = entry[4]
        if entry[1] == "ipv4" and (flags & 1) != 0 and ((flags & 4096) != 0 or (flags & 8) != 0):
            index = 0
            safe:
                index = net.interface_index(entry[0])
            end
            links.append([entry[0], entry[2], entry[3], index])
        end
    end
    raw["links"] = links
    raw["links_at"] = now
    if raw["fd"] >= 0:
        for link in links:
            safe:
                call net.multicast_join(raw["fd"], MDNS_GROUP, link[1])
            end
        end
    end
    return links
end

# Rozhraní, ze kterého přišel datagram (podle adresy odesílatele: vlastní
# adresa, pak stejná podsíť); neznámé = ["", adresa, "", 0].
function _link_for(address):
    links = _links()
    for link in links:
        if link[1] == address:
            return link
        end
    end
    word = _ipv4_word(address)
    for link in links:
        mask = _ipv4_word(link[2])
        if word >= 0 and mask > 0 and (word & mask) == (_ipv4_word(link[1]) & mask):
            return link
        end
    end
    return ["", address, "", 0]
end

function _is_own(address):
    if address.startswith("127."):
        return True
    end
    for link in _links():
        if link[1] == address:
            return True
        end
    end
    return False
end

# Soket 0.0.0.0:5353 sdílený s jinými responzory (SO_REUSEADDR), ve
# skupině 224.0.0.251 na všech rozhraních a v hlavní smyčce GLib.
function _raw_open():
    if raw["fd"] >= 0:
        return raw["fd"]
    end
    fd = net.udp_open("ipv4")
    try:
        call net.udp_bind(fd, "0.0.0.0", MDNS_PORT)
        call net.multicast_ttl(fd, 255)
        call net.multicast_loop(fd, True)
    else:
        message = _error_text(last_error())
        safe:
            call net.close(fd)
        end
        Error(MDNSError: "cannot open mDNS socket: " + message)
    end
    raw["fd"] = fd
    raw["links"] = []
    call _links()
    host = glib.host_name().split(".")[0]
    if host == "":
        host = "localhost"
    end
    raw["host"] = [host, "local"]
    raw["watch"] = glib.fd_add(fd, glib.IO_IN, _raw_readable)
    raw["timer"] = glib.timeout_add(250, _raw_tick)
    return fd
end

function _send_link(link, packet):
    safe:
        call net.multicast_interface(raw["fd"], link[1])
        call net.sendto(raw["fd"], packet, MDNS_GROUP, MDNS_PORT)
    end
    return 0
end

function _raw_readable(fd, condition):
    loop:
        packet = net.recvfrom(fd, 9000, 0)
        if len(packet) == 0:
            break
        end
        try:
            call _raw_packet(packet[0], packet[1], packet[2])
        else:
            continue
        end
    end
    return True
end

# Periodická práce: opakovaná ohlášení, dotazy hledání, vypršení záznamů.
function _raw_tick():
    now = time.monotonic()
    for handle in List(services.keys()):
        record = services[handle]
        if record["backend"] == "raw" and len(record["announce_at"]) > 0 and record["announce_at"][0] <= now:
            record["announce_at"] = record["announce_at"][1:len(record["announce_at"])]
            call _raw_send_records(record, TTL_OTHER, TTL_HOST)
        end
    end
    for id in List(browsers.keys()):
        browser = browsers[id]
        if browser["backend"] == "raw" and browser["next_query"] <= now:
            call _raw_query(browser)
        end
    end
    expired = False
    for owner in List(cache["ptr"].keys()):
        entries = cache["ptr"][owner]
        for key in List(entries.keys()):
            if entries[key]["expires"] <= now:
                del(entries[key])
                expired = True
            end
        end
    end
    if expired:
        call _raw_refresh()
    end
    return True
end

# --- vlastní mDNS: odpovídač ---

function _service_labels(record):
    return _check_type(record["type"]) + record["domain"].split(".")
end

function _instance_labels(record):
    return [record["name"]] + _service_labels(record)
end

function _txt_rdata(entries):
    data = ByteArray()
    for entry in entries:
        data.append(len(entry))
        call _put_bytes(data, entry)
    end
    if len(data) == 0:
        data.append(0)
    end
    return data
end

function _srv_rdata(port):
    data = ByteArray()
    call _put16(data, 0)
    call _put16(data, 0)
    call _put16(data, port)
    call _put_name(data, raw["host"])
    return data
end

function _name_rdata(labels):
    data = ByteArray()
    call _put_name(data, labels)
    return data
end

# Záznamy služby: PTR typ → instance, SRV, TXT, PTR výčtu typů a A adresy
# rozhraní; ttl_other 0 = goodbye. Vrací [odpovědi, doplňující].
function _service_records(record, link, ttl_other, ttl_host, flush):
    instance = _instance_labels(record)
    service = _service_labels(record)
    answers = [_record(service, TYPE_PTR, False, ttl_other, _name_rdata(instance))]
    answers.append(_record(instance, TYPE_SRV, flush, min(ttl_other, ttl_host), _srv_rdata(record["port"])))
    answers.append(_record(instance, TYPE_TXT, flush, ttl_other, _txt_rdata(record["entries"])))
    answers.append(_record(["_services", "_dns-sd", "_udp"] + record["domain"].split("."), TYPE_PTR, False, ttl_other, _name_rdata(service)))
    additional = []
    if ttl_host > 0 and link[1] != "":
        additional.append(_record(raw["host"], TYPE_A, flush, ttl_host, _ipv4_bytes(link[1])))
    end
    return [answers, additional]
end

# Nevyžádaná odpověď (ohlášení nebo goodbye) na všech rozhraních.
function _raw_send_records(record, ttl_other, ttl_host):
    for link in _links():
        parts = _service_records(record, link, ttl_other, ttl_host, True)
        call _send_link(link, _message(0, 33792, [], parts[0], parts[1]))
    end
    return 0
end

# Ohlášení teď a znovu za 1 a 3 s (RFC 6762 8.3).
function _raw_schedule(record):
    call _raw_send_records(record, TTL_OTHER, TTL_HOST)
    now = time.monotonic()
    record["announce_at"] = [now + 1.0, now + 3.0]
    return 0
end

function _raw_announce(record):
    call _raw_open()
    record["state"] = "established"
    call _raw_schedule(record)
    return 0
end

function _raw_goodbye(record):
    record["announce_at"] = []
    call _raw_send_records(record, 0, 0)
    return 0
end

# Odpovědi na otázky dotazu pro vlastní služby. Dotaz z jiného portu než
# 5353 (legacy unicast, RFC 6762 6.7) dostane odpověď unicastem se stejným
# id, otázkami a TTL nejvýš 10 s; jinak multicast na rozhraní dotazu.
function _raw_answer(id, questions, question_data, address, port):
    link = _link_for(address)
    legacy = port != MDNS_PORT
    ttl_other = TTL_OTHER
    ttl_host = TTL_HOST
    if legacy:
        ttl_other = 10
        ttl_host = 10
    end
    answers = {}
    additional = {}
    for question in questions:
        key = _name_key(question[0])
        wanted = question[1]
        for handle in services.keys():
            record = services[handle]
            if record["backend"] != "raw":
                continue
            end
            parts = _service_records(record, link, ttl_other, ttl_host, not legacy)
            instance_key = _name_key(_instance_labels(record))
            service_key = _name_key(_service_labels(record))
            if (wanted == TYPE_PTR or wanted == TYPE_ANY) and key == service_key:
                answers[instance_key + "/ptr"] = parts[0][0]
                additional[instance_key + "/srv"] = parts[0][1]
                additional[instance_key + "/txt"] = parts[0][2]
                if len(parts[1]) > 0:
                    additional["host"] = parts[1][0]
                end
            elif (wanted == TYPE_PTR or wanted == TYPE_ANY) and key == _name_key(["_services", "_dns-sd", "_udp"] + record["domain"].split(".")):
                answers[service_key + "/types"] = parts[0][3]
            elif key == instance_key:
                if wanted == TYPE_SRV or wanted == TYPE_ANY:
                    answers[instance_key + "/srv"] = parts[0][1]
                    if len(parts[1]) > 0:
                        additional["host"] = parts[1][0]
                    end
                end
                if wanted == TYPE_TXT or wanted == TYPE_ANY:
                    answers[instance_key + "/txt"] = parts[0][2]
                end
            elif key == _name_key(raw["host"]) and (wanted == TYPE_A or wanted == TYPE_ANY) and len(parts[1]) > 0:
                answers["host"] = parts[1][0]
            end
        end
    end
    if len(answers) == 0:
        return 0
    end
    extra = []
    for key in additional.keys():
        if not (key in answers):
            extra.append(additional[key])
        end
    end
    if legacy:
        packet = _message(id, 33792, question_data, List(answers.values()), extra)
        safe:
            call net.sendto(raw["fd"], packet, address, port)
        end
    elif link[0] == "":
        for each in _links():
            call _send_link(each, _message(0, 33792, [], List(answers.values()), extra))
        end
    else:
        call _send_link(link, _message(0, 33792, [], List(answers.values()), extra))
    end
    return 0
end

# --- vlastní mDNS: příjem ---

function _raw_packet(data, address, port):
    if len(data) < 12:
        return 0
    end
    id = _u16(data, 0)
    flags = _u16(data, 2)
    counts = [_u16(data, 4), _u16(data, 6), _u16(data, 8), _u16(data, 10)]
    position = 12
    questions = []
    question_data = []
    for index in range(counts[0]):
        name = _read_name(data, position)
        if name[1] + 4 > len(data):
            return 0
        end
        questions.append([name[0], _u16(data, name[1]), _u16(data, name[1] + 2) & 32767])
        question_data.append(_question(name[0], _u16(data, name[1])))
        position = name[1] + 4
    end
    if (flags & 32768) == 0:
        if (flags & 30720) == 0:
            call _raw_answer(id, questions, question_data, address, port)
        end
        return 0
    end
    records = []
    for index in range(counts[1] + counts[2] + counts[3]):
        name = _read_name(data, position)
        start = name[1]
        if start + 10 > len(data):
            break
        end
        length = _u16(data, start + 8)
        if start + 10 + length > len(data):
            break
        end
        records.append([name[0], _u16(data, start), _u32(data, start + 4), start + 10, length])
        position = start + 10 + length
    end
    call _raw_learn(data, records, _link_for(address), address)
    return 0
end

# Mezipaměť jen pro hledané typy: PTR typ → instance (podle rozhraní), SRV
# a TXT instancí, adresy jejich strojů podle rozhraní. TTL 0 záznam maže.
function _raw_learn(data, records, link, address):
    wanted = {}
    for id in browsers.keys():
        browser = browsers[id]
        if browser["backend"] == "raw":
            wanted[_name_key(_check_type(browser["type"]) + browser["domain"].split("."))] = True
        end
    end
    if len(wanted) == 0:
        return 0
    end
    now = time.monotonic()
    changed = False
    for record in records:
        owner = record[0]
        record_type = record[1]
        ttl = record[2]
        if record_type == TYPE_PTR:
            key = _name_key(owner)
            if key in wanted:
                target = _read_name(data, record[3])[0]
                if not (key in cache["ptr"]):
                    cache["ptr"][key] = {}
                end
                entry_key = _name_key(target) + chr(2) + link[0]
                if ttl == 0:
                    if entry_key in cache["ptr"][key]:
                        del(cache["ptr"][key][entry_key])
                    end
                else:
                    cache["ptr"][key][entry_key] = {"labels": target, "expires": now + Float(ttl), "link": link, "local": _is_own(address)}
                end
                changed = True
            end
        elif (record_type == TYPE_SRV or record_type == TYPE_TXT) and len(owner) > 1 and (_name_key(owner[1:len(owner)]) in wanted):
            key = _name_key(owner)
            if record_type == TYPE_SRV:
                if ttl == 0:
                    if key in cache["srv"]:
                        del(cache["srv"][key])
                    end
                elif record[4] >= 7:
                    cache["srv"][key] = {"port": _u16(data, record[3] + 4), "host": _read_name(data, record[3] + 6)[0]}
                end
            else:
                if ttl == 0:
                    if key in cache["txt"]:
                        del(cache["txt"][key])
                    end
                else:
                    cache["txt"][key] = _raw_txt(data, record[3], record[4])
                end
            end
            changed = True
        end
    end
    hosts = {}
    for key in cache["srv"].keys():
        hosts[_name_key(cache["srv"][key]["host"])] = True
    end
    for record in records:
        if record[1] != TYPE_A and record[1] != TYPE_AAAA:
            continue
        end
        host_key = _name_key(record[0])
        if not (host_key in hosts):
            continue
        end
        slot = host_key + chr(2) + link[0]
        if not (slot in cache["addr"]):
            cache["addr"][slot] = {}
        end
        family = "ipv4"
        if record[1] == TYPE_AAAA:
            family = "ipv6"
        end
        if record[2] == 0:
            if family in cache["addr"][slot]:
                del(cache["addr"][slot][family])
            end
        elif record[1] == TYPE_A and record[4] == 4:
            cache["addr"][slot][family] = String(data[record[3]]) + "." + String(data[record[3] + 1]) + "." + String(data[record[3] + 2]) + "." + String(data[record[3] + 3])
        elif record[1] == TYPE_AAAA and record[4] == 16:
            cache["addr"][slot][family] = _scoped(_ipv6_text(data, record[3]), link[0])
        end
        changed = True
    end
    if changed:
        call _raw_refresh()
    end
    return 0
end

function _raw_txt(data, start, length):
    entries = []
    position = start
    while position < start + length:
        size = data[position]
        if position + 1 + size > start + length:
            break
        end
        entries.append(data[position + 1:position + 1 + size])
        position += 1 + size
    end
    return _txt_dict(entries)
end

# Výsledky všech hledání z mezipaměti: služba s PTR, SRV, TXT a adresou
# stroje na rozhraní, kde přišel PTR; jeden výsledek na rozhraní a rodinu.
function _raw_refresh():
    for id in List(browsers.keys()):
        browser = browsers[id]
        if browser["backend"] != "raw":
            continue
        end
        type_labels = _check_type(browser["type"])
        owner = _name_key(type_labels + browser["domain"].split("."))
        results = {}
        entries = cache["ptr"].get(owner, {})
        for entry_key in entries.keys():
            entry = entries[entry_key]
            labels = entry["labels"]
            instance_key = _name_key(labels)
            if len(labels) < 2 or not (instance_key in cache["srv"]) or not (instance_key in cache["txt"]):
                continue
            end
            srv = cache["srv"][instance_key]
            link = entry["link"]
            addresses = cache["addr"].get(_name_key(srv["host"]) + chr(2) + link[0], {})
            for family in ["ipv4", "ipv6"]:
                if family in addresses:
                    results[link[0] + chr(2) + family + chr(2) + instance_key] = {"name": labels[0], "type": browser["type"], "domain": browser["domain"], "host": ".".join(srv["host"]), "address": addresses[family], "port": srv["port"], "txt": cache["txt"][instance_key], "interface": link[3], "interface_name": link[0], "protocol": family, "local": entry["local"], "backend": "raw"}
                end
            end
        end
        call _publish(browser, results)
    end
    return 0
end

# Dotaz hledání: PTR typu a pro známé instance bez SRV/TXT nebo stroje bez
# adresy i jejich záznamy; opakuje se po 1, 2, 4 … nejvýš 60 s.
function _raw_query(browser):
    service = _check_type(browser["type"]) + browser["domain"].split(".")
    questions = [_question(service, TYPE_PTR)]
    entries = cache["ptr"].get(_name_key(service), {})
    for entry_key in entries.keys():
        labels = entries[entry_key]["labels"]
        instance_key = _name_key(labels)
        if not (instance_key in cache["srv"]):
            questions.append(_question(labels, TYPE_SRV))
        elif len(cache["addr"].get(_name_key(cache["srv"][instance_key]["host"]) + chr(2) + entries[entry_key]["link"][0], {})) == 0:
            questions.append(_question(cache["srv"][instance_key]["host"], TYPE_A))
        end
        if not (instance_key in cache["txt"]):
            questions.append(_question(labels, TYPE_TXT))
        end
    end
    packet = _message(0, 0, dedup(questions), [], [])
    for link in _links():
        call _send_link(link, packet)
    end
    browser["next_query"] = time.monotonic() + browser["interval"]
    browser["interval"] = min(browser["interval"] * 2.0, 60.0)
    return 0
end

function _raw_browse(browser):
    call _raw_open()
    call _raw_query(browser)
    call _raw_refresh()
    return 0
end
