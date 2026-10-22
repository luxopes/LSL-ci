# lsl: internal-abi
# lsl: link libgio-2.0.so.0 libgobject-2.0.so.0 libglib-2.0.so.0
# D-Bus přes Gio přímo z LSL (cíl linux-x86_64-gnu). Parametry a odpovědi
# jsou texty GVariant („('org.freedesktop.DBus',)“, viz g_variant_parse a
# g_variant_print), takže program nepotřebuje typy GLib. Zpětná volání a
# hlavní smyčka: modul glib.
load glib

BUS_SYSTEM = 1
BUS_SESSION = 2

function error_cell():
    return __lsl_byte_zeros(8)
end

# GError z buňky: uvolní ho a vyhodí DBusError s jeho zprávou (try: ...).
function take_error(cell):
    error = __lsl_qbe_load64(glib.array_data(cell))
    if error == 0:
        return False
    end
    message = glib.from_c(__lsl_qbe_load64(error + 8))
    call __lsl_qbe_call1(__lsl_symbol("g_error_free"), error)
    Error(DBusError: message)
end

# Spojení se sběrnicí (BUS_SESSION nebo BUS_SYSTEM); DBusError při chybě.
function bus_get(bus_type):
    cell = error_cell()
    bus = __lsl_qbe_call3(__lsl_symbol("g_bus_get_sync"), ptr(bus_type), 0, glib.array_data(cell))
    call take_error(cell)
    return bus
end

function session_bus():
    return bus_get(BUS_SESSION)
end

function system_bus():
    return bus_get(BUS_SYSTEM)
end

function ptr(value):
    return __lsl_unbox_int(value)
end

# GVariant z textu; DBusError při chybě syntaxe.
function variant_parse(text):
    cell = error_cell()
    variant = __lsl_qbe_call5(__lsl_symbol("g_variant_parse"), 0, glib.cstr(text), 0, 0, glib.array_data(cell))
    call take_error(cell)
    return variant
end

# Text GVariant (s anotacemi typů, aby šel zpět přečíst variant_parse).
function variant_text(variant):
    return glib.take_c(__lsl_qbe_call2(__lsl_symbol("g_variant_print"), ptr(variant), 1))
end

function variant_unref(variant):
    return __lsl_qbe_call1(__lsl_symbol("g_variant_unref"), ptr(variant))
end

# Synchronní volání metody; params je text n-tice GVariant nebo "" bez
# parametrů. Vrací text odpovědi (n-tice); chyba sběrnice nebo metody je
# DBusError (zachytí try: ... else: ... end).
function call(bus, name, path, interface, method, params):
    parameters = 0
    if len(params) > 0:
        parameters = variant_parse(params)
    end
    cell = error_cell()
    reply = __lsl_qbe_call11(__lsl_symbol("g_dbus_connection_call_sync"), ptr(bus), glib.cstr(name), glib.cstr(path), glib.cstr(interface), glib.cstr(method), parameters, 0, 0, -1, 0, glib.array_data(cell))
    if parameters != 0:
        call variant_unref(parameters)
    end
    call take_error(cell)
    text = variant_text(reply)
    call variant_unref(reply)
    return text
end

# Vlastnost rozhraní přes org.freedesktop.DBus.Properties.Get; vrací text
# hodnoty (bez obalu varianty).
function get_property(bus, name, path, interface, property):
    reply = call(bus, name, path, "org.freedesktop.DBus.Properties", "Get", "('" + interface + "', '" + property + "')")
    # odpověď je (<hodnota>,): odstranit obal n-tice a varianty
    return reply[2:len(reply) - 3]
end

# Odběr signálu; obsluha(sender, path, interface, signal, params_text).
# Prázdný String u sender/interface/member/path = bez filtru.
function subscribe(bus, sender, interface, member, path, handler):
    record = glib.record_bound(signal_trampoline, 6, handler)
    sender_p = 0
    if len(sender) > 0:
        sender_p = glib.cstr(sender)
    end
    interface_p = 0
    if len(interface) > 0:
        interface_p = glib.cstr(interface)
    end
    member_p = 0
    if len(member) > 0:
        member_p = glib.cstr(member)
    end
    path_p = 0
    if len(path) > 0:
        path_p = glib.cstr(path)
    end
    return __lsl_qbe_call10(__lsl_symbol("g_dbus_connection_signal_subscribe"), ptr(bus), sender_p, interface_p, member_p, path_p, 0, 0, glib.callback_seventh(), record, 0)
end

function unsubscribe(bus, id):
    return __lsl_qbe_call2(__lsl_symbol("g_dbus_connection_signal_unsubscribe"), ptr(bus), ptr(id))
end

# GDBusSignalCallback(connection, sender, path, interface, signal, params)
function signal_trampoline(handler, connection, sender, path, interface, signal, params):
    return handler(glib.from_c(sender), glib.from_c(path), glib.from_c(interface), glib.from_c(signal), variant_text(params))
end

# Sledování jména na sběrnici: appeared(name, owner), vanished(name).
function watch_name(bus, name, appeared, vanished):
    call watch_vanished(bus, name, glib.record_bound(vanished_trampoline, 6, [vanished, name]))
    return __lsl_qbe_call7(__lsl_symbol("g_bus_watch_name_on_connection"), ptr(bus), glib.cstr(name), 0, glib.callback_fourth(), 0, glib.record_bound(appeared_trampoline, 3, appeared), 0)
end

# Zmizení jména sleduje odběr NameOwnerChanged (jeden watcher Gio má dvě
# zpětná volání s různou pozicí user_data; odběr signálu je jednodušší).
function watch_vanished(bus, name, record):
    call __lsl_qbe_call10(__lsl_symbol("g_dbus_connection_signal_subscribe"), ptr(bus), glib.cstr("org.freedesktop.DBus"), glib.cstr("org.freedesktop.DBus"), glib.cstr("NameOwnerChanged"), glib.cstr("/org/freedesktop/DBus"), glib.cstr(name), 0, glib.callback_seventh(), ptr(record), 0)
    return 0
end

function appeared_trampoline(handler, connection, name, owner):
    return handler(glib.from_c(name), glib.from_c(owner))
end

# Vázaná hodnota je [obsluha, jméno]; NameOwnerChanged nese ('jméno',
# 'starý vlastník', 'nový vlastník') a zajímá nás prázdný nový vlastník.
function vanished_trampoline(bound, connection, sender, path, interface, signal, params):
    if variant_text(params).endswith("'')"):
        return bound[0](bound[1])
    end
    return 0
end

# Vlastní jméno na sběrnici (g_bus_own_name_on_connection, bez obsluh).
function own_name(bus, name):
    return __lsl_qbe_call6(__lsl_symbol("g_bus_own_name_on_connection"), ptr(bus), glib.cstr(name), 0, 0, 0, 0)
end

# Vyšle signál z vlastní cesty; params text n-tice nebo "".
function emit_signal(bus, path, interface, signal, params):
    parameters = 0
    if len(params) > 0:
        parameters = variant_parse(params)
    end
    cell = error_cell()
    call __lsl_qbe_call7(__lsl_symbol("g_dbus_connection_emit_signal"), ptr(bus), 0, glib.cstr(path), glib.cstr(interface), glib.cstr(signal), parameters, glib.array_data(cell))
    call take_error(cell)
    return True
end
