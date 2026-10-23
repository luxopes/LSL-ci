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
# DBusError (zachytí try: ... else: ... end). Časový limit je výchozí
# limit GDBus (25 s); call_timeout(…, ms) ho mění.
function call(bus, name, path, interface, method, params):
    return call_timeout(bus, name, path, interface, method, params, -1)
end

function call_timeout(bus, name, path, interface, method, params, timeout_ms):
    parameters = 0
    if len(params) > 0:
        parameters = variant_parse(params)
    end
    reply = call_variant(bus, name, path, interface, method, parameters, timeout_ms)
    text = variant_text(reply)
    call variant_unref(reply)
    return text
end

# Jádro volání: parameters je GVariant (plná reference, uvolní se) nebo 0;
# vrací GVariant odpovědi (plná reference).
function call_variant(bus, name, path, interface, method, parameters, timeout_ms):
    cell = error_cell()
    reply = __lsl_qbe_call11(__lsl_symbol("g_dbus_connection_call_sync"), ptr(bus), glib.cstr(name), glib.cstr(path), glib.cstr(interface), glib.cstr(method), ptr(parameters), 0, 0, ptr(timeout_ms), 0, glib.array_data(cell))
    if parameters != 0:
        call variant_unref(parameters)
    end
    call take_error(cell)
    return reply
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

# --- hodnoty LSL místo textu GVariant ---
#
# variant_to_value: Bool, Int (b y n q i u x t h), Float (d), String (s o g),
# List (pole a n-tice), Dictionary (a{..}), v se rozbalí, m dá None nebo
# hodnotu. value_to_variant staví GVariant podle podpisu: "i" z Int, "as" ze
# seznamu, "(su)" z [text, číslo], "a{sv}" ze slovníku; hodnota pro "v" je
# [podpis, hodnota] (např. ["u", 4]) nebo prostá hodnota (Bool → b, Int → x,
# Float → d, String → s).

function variant_to_value(variant):
    kind = __lsl_qbe_call1(__lsl_symbol("g_variant_classify"), ptr(variant))
    if kind == 98:
        return __lsl_qbe_call1(__lsl_symbol("g_variant_get_boolean"), ptr(variant)) != 0
    elif kind == 121:
        return __lsl_qbe_u8(__lsl_qbe_call1(__lsl_symbol("g_variant_get_byte"), ptr(variant)))
    elif kind == 110:
        return __lsl_qbe_s16(__lsl_qbe_call1(__lsl_symbol("g_variant_get_int16"), ptr(variant)))
    elif kind == 113:
        return __lsl_qbe_u16(__lsl_qbe_call1(__lsl_symbol("g_variant_get_uint16"), ptr(variant)))
    elif kind == 105:
        return __lsl_qbe_s32(__lsl_qbe_call1(__lsl_symbol("g_variant_get_int32"), ptr(variant)))
    elif kind == 104:
        return __lsl_qbe_s32(__lsl_qbe_call1(__lsl_symbol("g_variant_get_handle"), ptr(variant)))
    elif kind == 117:
        return __lsl_qbe_u32(__lsl_qbe_call1(__lsl_symbol("g_variant_get_uint32"), ptr(variant)))
    elif kind == 120:
        return __lsl_qbe_call1(__lsl_symbol("g_variant_get_int64"), ptr(variant))
    elif kind == 116:
        return __lsl_qbe_call1(__lsl_symbol("g_variant_get_uint64"), ptr(variant))
    elif kind == 100:
        return __lsl_qbe_fcall1(__lsl_symbol("g_variant_get_double"), ptr(variant))
    elif kind == 115 or kind == 111 or kind == 103:
        return glib.from_c(__lsl_qbe_call2(__lsl_symbol("g_variant_get_string"), ptr(variant), 0))
    elif kind == 118:
        inner = __lsl_qbe_call1(__lsl_symbol("g_variant_get_variant"), ptr(variant))
        value = variant_to_value(inner)
        call variant_unref(inner)
        return value
    elif kind == 109:
        inner = __lsl_qbe_call1(__lsl_symbol("g_variant_get_maybe"), ptr(variant))
        if inner == 0:
            return None
        end
        value = variant_to_value(inner)
        call variant_unref(inner)
        return value
    end
    count = __lsl_qbe_call1(__lsl_symbol("g_variant_n_children"), ptr(variant))
    if kind == 97 and glib.from_c(__lsl_qbe_call1(__lsl_symbol("g_variant_get_type_string"), ptr(variant))).startswith("a{"):
        result = {}
        index = 0
        while index < count:
            entry = __lsl_qbe_call2(__lsl_symbol("g_variant_get_child_value"), ptr(variant), index)
            key_variant = __lsl_qbe_call2(__lsl_symbol("g_variant_get_child_value"), entry, 0)
            value_variant = __lsl_qbe_call2(__lsl_symbol("g_variant_get_child_value"), entry, 1)
            result[variant_to_value(key_variant)] = variant_to_value(value_variant)
            call variant_unref(key_variant)
            call variant_unref(value_variant)
            call variant_unref(entry)
            index += 1
        end
        return result
    end
    items = []
    index = 0
    while index < count:
        child = __lsl_qbe_call2(__lsl_symbol("g_variant_get_child_value"), ptr(variant), index)
        items.append(variant_to_value(child))
        call variant_unref(child)
        index += 1
    end
    return items
end

# Délka jednoho úplného typu na začátku podpisu (od pozice start).
function signature_length(signature, start):
    first = signature[start]
    if first == "a" or first == "m":
        return 1 + signature_length(signature, start + 1)
    elif first == "(" or first == "{":
        closing = ")"
        if first == "{":
            closing = "}"
        end
        position = start + 1
        while signature[position] != closing:
            position += signature_length(signature, position)
        end
        return position - start + 1
    end
    return 1
end

function signature_error(signature, value):
    Error(DBusError: "cannot build GVariant " + signature + " from " + type(value))
end

# GVariant (plovoucí reference) z hodnoty LSL podle podpisu.
function value_to_variant(value, signature):
    first = signature[0]
    if first == "b":
        return __lsl_qbe_call1(__lsl_symbol("g_variant_new_boolean"), ptr(Bool(value)))
    elif first == "y" or first == "n" or first == "q" or first == "i" or first == "u" or first == "x" or first == "t" or first == "h":
        if type(value) != "Int":
            call signature_error(signature, value)
        end
        if first == "y":
            return __lsl_qbe_call1(__lsl_symbol("g_variant_new_byte"), ptr(value))
        elif first == "n":
            return __lsl_qbe_call1(__lsl_symbol("g_variant_new_int16"), ptr(value))
        elif first == "q":
            return __lsl_qbe_call1(__lsl_symbol("g_variant_new_uint16"), ptr(value))
        elif first == "i":
            return __lsl_qbe_call1(__lsl_symbol("g_variant_new_int32"), ptr(value))
        elif first == "u":
            return __lsl_qbe_call1(__lsl_symbol("g_variant_new_uint32"), ptr(value))
        elif first == "x":
            return __lsl_qbe_call1(__lsl_symbol("g_variant_new_int64"), ptr(value))
        elif first == "t":
            return __lsl_qbe_call1(__lsl_symbol("g_variant_new_uint64"), ptr(value))
        end
        return __lsl_qbe_call1(__lsl_symbol("g_variant_new_handle"), ptr(value))
    elif first == "d":
        return __lsl_qbe_call1(__lsl_symbol("g_variant_new_double"), Float(value))
    elif first == "s" or first == "o" or first == "g":
        if type(value) != "String":
            call signature_error(signature, value)
        end
        if first == "o":
            return __lsl_qbe_call1(__lsl_symbol("g_variant_new_object_path"), glib.cstr(value))
        elif first == "g":
            return __lsl_qbe_call1(__lsl_symbol("g_variant_new_signature"), glib.cstr(value))
        end
        return __lsl_qbe_call1(__lsl_symbol("g_variant_new_string"), glib.cstr(value))
    elif first == "v":
        inner_signature = ""
        inner_value = value
        if type(value) == "List" and len(value) == 2 and type(value[0]) == "String" and len(value[0]) > 0 and signature_length(value[0], 0) == len(value[0]):
            inner_signature = value[0]
            inner_value = value[1]
        elif type(value) == "Bool":
            inner_signature = "b"
        elif type(value) == "Int":
            inner_signature = "x"
        elif type(value) == "Float":
            inner_signature = "d"
        elif type(value) == "String":
            inner_signature = "s"
        else:
            call signature_error(signature, value)
        end
        return __lsl_qbe_call1(__lsl_symbol("g_variant_new_variant"), ptr(value_to_variant(inner_value, inner_signature)))
    elif first == "m":
        if value == None:
            return __lsl_qbe_call2(__lsl_symbol("g_variant_new_maybe"), ptr(variant_type(signature[1:len(signature)])), 0)
        end
        return __lsl_qbe_call2(__lsl_symbol("g_variant_new_maybe"), 0, ptr(value_to_variant(value, signature[1:len(signature)])))
    elif first == "a":
        builder = __lsl_qbe_call1(__lsl_symbol("g_variant_builder_new"), ptr(variant_type(signature)))
        element = signature[1:len(signature)]
        if element.startswith("{"):
            if type(value) != "Dictionary":
                call signature_error(signature, value)
            end
            key_signature = element[1:1 + signature_length(element, 1)]
            value_signature = element[1 + len(key_signature):len(element) - 1]
            for key in value.keys():
                entry = __lsl_qbe_call2(__lsl_symbol("g_variant_new_dict_entry"), ptr(value_to_variant(key, key_signature)), ptr(value_to_variant(value[key], value_signature)))
                call __lsl_qbe_call2(__lsl_symbol("g_variant_builder_add_value"), builder, entry)
            end
        else:
            if type(value) != "List" and type(value) != "Tuple":
                call signature_error(signature, value)
            end
            for item in value:
                call __lsl_qbe_call2(__lsl_symbol("g_variant_builder_add_value"), builder, ptr(value_to_variant(item, element)))
            end
        end
        result = __lsl_qbe_call1(__lsl_symbol("g_variant_builder_end"), builder)
        call __lsl_qbe_call1(__lsl_symbol("g_variant_builder_unref"), builder)
        return result
    elif first == "(":
        if type(value) != "List" and type(value) != "Tuple":
            call signature_error(signature, value)
        end
        builder = __lsl_qbe_call1(__lsl_symbol("g_variant_builder_new"), ptr(variant_type(signature)))
        position = 1
        index = 0
        while signature[position] != ")":
            length = signature_length(signature, position)
            if index >= len(value):
                call signature_error(signature, value)
            end
            call __lsl_qbe_call2(__lsl_symbol("g_variant_builder_add_value"), builder, ptr(value_to_variant(value[index], signature[position:position + length])))
            position += length
            index += 1
        end
        if index != len(value):
            call signature_error(signature, value)
        end
        result = __lsl_qbe_call1(__lsl_symbol("g_variant_builder_end"), builder)
        call __lsl_qbe_call1(__lsl_symbol("g_variant_builder_unref"), builder)
        return result
    end
    call signature_error(signature, value)
    return 0
end

# GVariantType z podpisu (statická reference z interní tabulky typů).
variant_types = {}

function variant_type(signature):
    if signature in variant_types:
        return variant_types[signature]
    end
    kind = __lsl_qbe_call1(__lsl_symbol("g_variant_type_new"), glib.cstr(signature))
    variant_types[signature] = kind
    return kind
end

# Volání metody s hodnotami LSL: values je seznam argumentů a signature
# podpis n-tice ("(su)"; "" bez argumentů); vrací seznam hodnot odpovědi.
function call_values(bus, name, path, interface, method, values, signature, timeout_ms):
    parameters = 0
    if len(signature) > 0:
        parameters = __lsl_qbe_call1(__lsl_symbol("g_variant_ref_sink"), ptr(value_to_variant(values, signature)))
    end
    reply = call_variant(bus, name, path, interface, method, parameters, timeout_ms)
    result = variant_to_value(reply)
    call variant_unref(reply)
    return result
end

# Vlastnost jako hodnota LSL a nastavení vlastnosti (value podle podpisu,
# např. set_property(bus, …, "Brightness", 40, "i")).
function get_property_value(bus, name, path, interface, property):
    return call_values(bus, name, path, "org.freedesktop.DBus.Properties", "Get", [interface, property], "(ss)", -1)[0]
end

function get_all_properties(bus, name, path, interface):
    return call_values(bus, name, path, "org.freedesktop.DBus.Properties", "GetAll", [interface], "(s)", -1)[0]
end

function set_property(bus, name, path, interface, property, value, signature):
    call call_values(bus, name, path, "org.freedesktop.DBus.Properties", "Set", [interface, property, [signature, value]], "(ssv)", -1)
    return True
end

# Odběr signálu s hodnotami: f(sender, path, interface, signal, values),
# values je seznam argumentů signálu (PropertiesChanged: [rozhraní,
# {změněné}, [neplatné]]).
function subscribe_values(bus, sender, interface, member, path, handler):
    return subscribe_record(bus, sender, interface, member, path, glib.record_bound(values_trampoline, 6, handler))
end

function values_trampoline(handler, connection, sender, path, interface, signal, params):
    return handler(glib.from_c(sender), glib.from_c(path), glib.from_c(interface), glib.from_c(signal), variant_to_value(params))
end

function subscribe_record(bus, sender, interface, member, path, record):
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
    return __lsl_qbe_call10(__lsl_symbol("g_dbus_connection_signal_subscribe"), ptr(bus), sender_p, interface_p, member_p, path_p, 0, 0, glib.callback_seventh(), ptr(record), 0)
end

# Vyslání signálu s hodnotami podle podpisu n-tice.
function emit_values(bus, path, interface, signal, values, signature):
    parameters = 0
    if len(signature) > 0:
        parameters = value_to_variant(values, signature)
    end
    cell = error_cell()
    call __lsl_qbe_call7(__lsl_symbol("g_dbus_connection_emit_signal"), ptr(bus), 0, glib.cstr(path), glib.cstr(interface), glib.cstr(signal), ptr(parameters), glib.array_data(cell))
    call take_error(cell)
    return True
end

# --- vlastní objekt na sběrnici (agent BlueZ, služba hubu) ---

# vtable a introspekce musí žít po dobu registrace (knihovna drží jen
# ukazatele, které GC nevidí).
registrations = []

# Zaregistruje objekt s rozhraním z introspekčního XML (první rozhraní
# uzlu). Při volání metody dostane f(sender, path, interface, method,
# values, invocation) a odpoví return_value(invocation, values, podpis)
# nebo return_error(invocation, jméno_chyby, zpráva) – hned, nebo později
# z jiné obsluhy (invocation zůstává platné, dokud se neodpoví). Vrací id
# registrace pro unregister_object.
function register_object(bus, path, xml, handler):
    cell = error_cell()
    info = __lsl_qbe_call2(__lsl_symbol("g_dbus_node_info_new_for_xml"), glib.cstr(xml), glib.array_data(cell))
    call take_error(cell)
    interfaces = __lsl_qbe_load64(info + 16)
    if interfaces == 0 or __lsl_qbe_load64(interfaces) == 0:
        Error(DBusError: "introspection XML has no interface")
    end
    # GDBusInterfaceVTable: method_call, get_property, set_property, padding[8]
    vtable = __lsl_byte_zeros(88)
    __lsl_qbe_store64(glib.array_data(vtable), ptr(glib.callback_eighth()))
    record = glib.record_bound(method_trampoline, 6, handler)
    registrations.append([vtable, info, record])
    id = __lsl_qbe_call7(__lsl_symbol("g_dbus_connection_register_object"), ptr(bus), glib.cstr(path), __lsl_qbe_load64(interfaces), glib.array_data(vtable), ptr(record), 0, glib.array_data(cell))
    call take_error(cell)
    return id
end

function unregister_object(bus, id):
    return __lsl_qbe_call2(__lsl_symbol("g_dbus_connection_unregister_object"), ptr(bus), ptr(id)) != 0
end

# GDBusInterfaceMethodCallFunc bez spojení (most _u8): sender, path,
# interface, method, parameters, invocation.
function method_trampoline(handler, sender, path, interface, method, params, invocation):
    return handler(glib.from_c(sender), glib.from_c(path), glib.from_c(interface), glib.from_c(method), variant_to_value(params), invocation)
end

# Odpověď na volání metody: values podle podpisu n-tice ("(s)"), "" bez
# návratové hodnoty.
function return_value(invocation, values, signature):
    result = 0
    if len(signature) > 0:
        result = value_to_variant(values, signature)
    end
    return __lsl_qbe_call2(__lsl_symbol("g_dbus_method_invocation_return_value"), ptr(invocation), ptr(result))
end

function return_error(invocation, error_name, message):
    return __lsl_qbe_call3(__lsl_symbol("g_dbus_method_invocation_return_dbus_error"), ptr(invocation), glib.cstr(error_name), glib.cstr(message))
end

# --- sledování souborů (GFileMonitor) ---

# GFileMonitorEvent
FILE_CHANGED = 0
FILE_CHANGES_DONE_HINT = 1
FILE_DELETED = 2
FILE_CREATED = 3
FILE_ATTRIBUTE_CHANGED = 4
FILE_PRE_UNMOUNT = 5
FILE_UNMOUNTED = 6
FILE_MOVED = 7
FILE_RENAMED = 8
FILE_MOVED_IN = 9
FILE_MOVED_OUT = 10

# Sleduje soubor nebo adresář: f(path, event, other_path), other_path je
# cíl přesunu u FILE_RENAMED/FILE_MOVED_*, jinak "". Vrací monitor pro
# file_monitor_cancel; DBusError, když cestu nelze sledovat.
function file_monitor(path, handler):
    file = __lsl_qbe_call1(__lsl_symbol("g_file_new_for_path"), glib.cstr(path))
    cell = error_cell()
    # G_FILE_MONITOR_WATCH_MOVES = 8
    monitor = __lsl_qbe_call4(__lsl_symbol("g_file_monitor"), file, 8, 0, glib.array_data(cell))
    call glib.object_unref(file)
    call take_error(cell)
    record = glib.record_bound(monitor_trampoline, 4, handler)
    call __lsl_qbe_call6(__lsl_symbol("g_signal_connect_data"), monitor, glib.cstr("changed"), ptr(glib.callback_first()), ptr(record), 0, 2)
    return monitor
end

function file_monitor_cancel(monitor):
    call __lsl_qbe_call1(__lsl_symbol("g_file_monitor_cancel"), ptr(monitor))
    return glib.object_unref(monitor)
end

# changed(monitor, file, other_file, event) se SWAPPED: (záznam, file, other, event, monitor)
function monitor_trampoline(handler, file, other, event, monitor):
    other_path = ""
    if other != 0:
        other_path = glib.take_c(__lsl_qbe_call1(__lsl_symbol("g_file_get_path"), ptr(other)))
    end
    return handler(glib.take_c(__lsl_qbe_call1(__lsl_symbol("g_file_get_path"), ptr(file))), event, other_path)
end
