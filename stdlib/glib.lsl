# lsl: internal-abi
# lsl: link libgio-2.0.so.0 libgobject-2.0.so.0 libglib-2.0.so.0
# GLib přímo z LSL (cíl linux-x86_64-gnu): hlavní smyčka, časovače, signály
# UNIXu, spouštění programů a společný most zpětných volání pro moduly gio
# a gtk. Program je dynamicky linkovaný proti knihovnám systému a volá je bez
# mezivrstvy; hodnoty objektů GLib jsou surové ukazatele (Int).
#
# Zpětná volání: knihovna volá vstup lsl_arch_callback* v runtime (vrstva
# arch), ten přesune záznam obsluhy na první místo a zavolá dispatch; obsluha
# LSL je běžná funkce a dostane argumenty zabalené. Záznam [obsluha, počet,
# vázaná hodnota] drží seznam handlers, protože knihovna má jen surový
# ukazatel, který GC nevidí.
#
# Pravidla uvnitř modulu: argumenty z běžného kódu a globální proměnné
# modulu jsou zabalené (Any), před předáním do C je rozbalí ptr(); parametr
# se nepřepisuje (přepsaný by se zabalil znovu), výsledky volání C se drží
# v nových lokálních proměnných.

PRIORITY_HIGH = -100
PRIORITY_DEFAULT = 0
PRIORITY_LOW = 300

handlers = []
main_loop = 0

# Ukazatel na bajty Stringu (runtime drží za textem nulu).
function cstr(text):
    return __lsl_address(text) + 16
end

function ptr(value):
    return __lsl_unbox_int(value)
end

# String z textu jazyka C ukončeného nulou (kopie; paměť C zůstává volajícímu).
function from_c(address):
    raw = ptr(address)
    if raw == 0:
        return ""
    end
    length = __lsl_qbe_call1(__lsl_symbol("strlen"), raw)
    bytes = __lsl_byte_zeros(length)
    call __lsl_qbe_call3(__lsl_symbol("memcpy"), __lsl_qbe_load64(__lsl_address(bytes) + 24), raw, length)
    return __lsl_text_from_bytes(bytes, 0, length)
end

# String z textu C, který volajícímu patří (g_free po zkopírování).
function take_c(address):
    text = from_c(address)
    call __lsl_qbe_call1(__lsl_symbol("g_free"), ptr(address))
    return text
end

# Pole ukazatelů na texty ukončené NULL (char **) z Listu Stringů; ByteArray
# s poli musí žít po dobu volání C (volající ho drží v proměnné).
function cstr_array(items):
    count = len(items)
    bytes = __lsl_byte_zeros((count + 1) * 8)
    data = __lsl_qbe_load64(__lsl_address(bytes) + 24)
    index = 0
    while index < count:
        __lsl_qbe_store64(data + index * 8, cstr(items[index]))
        index += 1
    end
    __lsl_qbe_store64(data + count * 8, 0)
    return bytes
end

function array_data(bytes):
    return __lsl_qbe_load64(__lsl_address(bytes) + 24)
end

# --- zpětná volání ---

function box(word):
    return __lsl_qbe_call1(__lsl_symbol("rt_runtime_box_int"), word)
end

# Zavolá obsluhu LSL ze záznamu se zabalenými slovy z C (vázaná hodnota
# záznamu jako první argument, je-li přítomna). Chyba obsluhy program
# neukončí (hlavní smyčka musí běžet dál): vypíše se na stderr jako
# „LSL callback error: …“ a obsluha vrátí 0. Výsledek pro C: Bool/Int
# rozbalený, None a ostatní objekty 0 (gboolean „nepokračovat“/„neobslouženo“).
function dispatch(record, a1, a2, a3, a4, a5, a6):
    base = __lsl_address(record)
    items = __lsl_qbe_load64(base + 24)
    code = __lsl_qbe_call1(__lsl_symbol("rt_runtime_unbox_dynamic_function"), __lsl_qbe_load64(items))
    count = __lsl_qbe_call1(__lsl_symbol("rt_runtime_unbox_dynamic_int"), __lsl_qbe_load64(items + 8))
    result = 0
    try:
        result = invoke(code, count, __lsl_qbe_load64(base + 8) > 2, items, a1, a2, a3, a4, a5, a6)
    else:
        call report("LSL callback error: " + String(last_error()) + chr(10))
        return 0
    end
    word = __lsl_qbe_call1(__lsl_symbol("rt_runtime_unbox_dynamic_int"), result)
    if __lsl_qbe_call1(__lsl_symbol("rt_runtime_is_heap_object"), word) != 0:
        return 0
    end
    return word
end

function invoke(code, count, has_bound, items, a1, a2, a3, a4, a5, a6):
    if has_bound:
        bound = __lsl_qbe_load64(items + 16)
        if count == 0:
            return __lsl_qbe_call1(code, bound)
        elif count == 1:
            return __lsl_qbe_call2(code, bound, box(a1))
        elif count == 2:
            return __lsl_qbe_call3(code, bound, box(a1), box(a2))
        elif count == 3:
            return __lsl_qbe_call4(code, bound, box(a1), box(a2), box(a3))
        elif count == 4:
            return __lsl_qbe_call5(code, bound, box(a1), box(a2), box(a3), box(a4))
        elif count == 5:
            return __lsl_qbe_call6(code, bound, box(a1), box(a2), box(a3), box(a4), box(a5))
        end
        return __lsl_qbe_call7(code, bound, box(a1), box(a2), box(a3), box(a4), box(a5), box(a6))
    end
    if count == 0:
        return __lsl_qbe_call0(code)
    elif count == 1:
        return __lsl_qbe_call1(code, box(a1))
    elif count == 2:
        return __lsl_qbe_call2(code, box(a1), box(a2))
    elif count == 3:
        return __lsl_qbe_call3(code, box(a1), box(a2), box(a3))
    elif count == 4:
        return __lsl_qbe_call4(code, box(a1), box(a2), box(a3), box(a4))
    elif count == 5:
        return __lsl_qbe_call5(code, box(a1), box(a2), box(a3), box(a4), box(a5))
    end
    return __lsl_qbe_call6(code, box(a1), box(a2), box(a3), box(a4), box(a5), box(a6))
end

# Text na stderr přímo (bez vyrovnávací paměti).
function report(text):
    return __lsl_qbe_call3(__lsl_symbol("write"), 2, cstr(text), __lsl_text_byte_length(text))
end

# Nový záznam obsluhy; vrací surovou adresu pro user_data knihovny.
function record_new(handler, count):
    __lsl_qbe_store64(__lsl_symbol("lsl_arch_callback_slot"), __lsl_qbe_call1(__lsl_symbol("rt_runtime_unbox_dynamic_function"), dispatch))
    record = [handler, count]
    call handlers.append(record)
    return __lsl_address(record)
end

# Záznam s vázanou hodnotou: obsluha dostane bound jako první argument.
function record_bound(handler, count, bound):
    __lsl_qbe_store64(__lsl_symbol("lsl_arch_callback_slot"), __lsl_qbe_call1(__lsl_symbol("rt_runtime_unbox_dynamic_function"), dispatch))
    record = [handler, count, bound]
    call handlers.append(record)
    return __lsl_address(record)
end

# Vstupy pro knihovnu podle pozice user_data (viz runtime/arch).
function callback_first():
    return __lsl_symbol("lsl_arch_callback")
end

function callback_third():
    return __lsl_symbol("lsl_arch_callback_u3")
end

function callback_fourth():
    return __lsl_symbol("lsl_arch_callback_u4")
end

function callback_seventh():
    return __lsl_symbol("lsl_arch_callback_u7")
end

# user_data osmá, první argument (spojení) se vynechá: GDBusInterfaceMethodCallFunc.
function callback_eighth():
    return __lsl_symbol("lsl_arch_callback_u8")
end

# --- hlavní smyčka ---

# Globální proměnná modulu drží ukazatel zabalený (Any): před voláním C
# vždy ptr().
function main():
    global main_loop
    if main_loop == 0:
        main_loop = __lsl_qbe_call2(__lsl_symbol("g_main_loop_new"), 0, 0)
    end
    # Výstup služby na pozadí (roura, journal) musí jít ven hned, ne až při ukončení.
    call unbuffered()
    return __lsl_qbe_call1(__lsl_symbol("g_main_loop_run"), ptr(main_loop))
end

function main_quit():
    if main_loop != 0:
        call __lsl_qbe_call1(__lsl_symbol("g_main_loop_quit"), ptr(main_loop))
    end
    return 0
end

# Jeden průchod čekajícími událostmi bez blokování.
function pump():
    context = __lsl_qbe_call0(__lsl_symbol("g_main_context_default"))
    while __lsl_qbe_call2(__lsl_symbol("g_main_context_iteration"), context, 0) != 0:
        continue
    end
    return 0
end

# Obsluha bez argumentů se volá každých interval ms, dokud vrací True.
function timeout_add(interval, handler):
    return __lsl_qbe_call3(__lsl_symbol("g_timeout_add"), ptr(interval), callback_first(), record_new(handler, 0))
end

function timeout_add_seconds(interval, handler):
    return __lsl_qbe_call3(__lsl_symbol("g_timeout_add_seconds"), ptr(interval), callback_first(), record_new(handler, 0))
end

function idle_add(handler):
    return __lsl_qbe_call2(__lsl_symbol("g_idle_add"), callback_first(), record_new(handler, 0))
end

# Podmínky deskriptoru pro fd_add (GIOCondition).
IO_IN = 1
IO_OUT = 4
IO_ERR = 8
IO_HUP = 16

# Deskriptor (soket net/tls, roura) v hlavní smyčce: handler(fd, podmínky)
# se volá, když nastane některá z podmínek, dokud vrací True; vrací id zdroje.
function fd_add(fd, condition, handler):
    return __lsl_qbe_call6(__lsl_symbol("g_unix_fd_add_full"), PRIORITY_DEFAULT, ptr(fd), ptr(condition), callback_third(), record_new(handler, 2), 0)
end

function source_remove(id):
    return __lsl_qbe_call1(__lsl_symbol("g_source_remove"), ptr(id)) != 0
end

# Signál UNIXu (SIGUSR1 = 10, SIGUSR2 = 12, SIGTERM = 15) v hlavní smyčce.
function unix_signal_add(signum, handler):
    return __lsl_qbe_call5(__lsl_symbol("g_unix_signal_add_full"), PRIORITY_HIGH, ptr(signum), callback_first(), record_new(handler, 0), 0)
end

# Spustí program na pozadí (hledá se v PATH); GLib potomka sklidí sama.
# Vrací PID, při chybě (program nenalezen) 0. G_SPAWN_SEARCH_PATH = 4.
function spawn(argv):
    return spawn_flags(argv, 4)
end

# Spustí program a po jeho skončení zavolá obsluhu(pid, status); status je
# jako z waitpid (ukončení kódem n = n * 256). G_SPAWN_DO_NOT_REAP_CHILD = 2.
function spawn_watched(argv, handler):
    pid = spawn_flags(argv, 6)
    if pid != 0:
        call __lsl_qbe_call5(__lsl_symbol("g_child_watch_add_full"), PRIORITY_DEFAULT, pid, callback_third(), record_new(handler, 2), 0)
    end
    return pid
end

function spawn_flags(argv, flags):
    array = cstr_array(argv)
    pid_cell = __lsl_byte_zeros(8)
    ok = __lsl_qbe_call8(__lsl_symbol("g_spawn_async"), 0, array_data(array), 0, ptr(flags), 0, 0, array_data(pid_cell), 0)
    if ok == 0:
        return 0
    end
    return __lsl_qbe_s32(__lsl_qbe_load32(array_data(pid_cell)))
end

# --- objekty ---

function object_unref(object):
    return __lsl_qbe_call1(__lsl_symbol("g_object_unref"), ptr(object))
end

# Signál GObject; obsluha dostane argumenty signálu a nakonec instanci
# (G_CONNECT_SWAPPED = 2: záznam první, instance poslední).
function signal_connect(instance, signal, handler, argument_count):
    record = record_new(handler, ptr(argument_count) + 1)
    return __lsl_qbe_call6(__lsl_symbol("g_signal_connect_data"), ptr(instance), cstr(signal), callback_first(), record, 0, 2)
end

function signal_handler_disconnect(instance, id):
    return __lsl_qbe_call2(__lsl_symbol("g_signal_handler_disconnect"), ptr(instance), ptr(id))
end

# --- pomůcky ---

function monotonic_time():
    return __lsl_qbe_call0(__lsl_symbol("g_get_monotonic_time"))
end

function markup_escape(text):
    return take_c(__lsl_qbe_call2(__lsl_symbol("g_markup_escape_text"), cstr(text), -1))
end

function find_program_in_path(name):
    return take_c(__lsl_qbe_call1(__lsl_symbol("g_find_program_in_path"), cstr(name)))
end

function user_config_dir():
    return from_c(__lsl_qbe_call0(__lsl_symbol("g_get_user_config_dir")))
end

function user_runtime_dir():
    return from_c(__lsl_qbe_call0(__lsl_symbol("g_get_user_runtime_dir")))
end

function home_dir():
    return from_c(__lsl_qbe_call0(__lsl_symbol("g_get_home_dir")))
end

function host_name():
    return from_c(__lsl_qbe_call0(__lsl_symbol("g_get_host_name")))
end

function set_prgname(name):
    return __lsl_qbe_call1(__lsl_symbol("g_set_prgname"), cstr(name))
end

function set_application_name(name):
    return __lsl_qbe_call1(__lsl_symbol("g_set_application_name"), cstr(name))
end

function getpid():
    return __lsl_qbe_call0(__lsl_symbol("getpid"))
end

# Výstup print bez vyrovnávací paměti (záznamy služby jdou hned do žurnálu).
function unbuffered():
    return __lsl_qbe_call0(__lsl_symbol("rt_runtime_stdio_direct"))
end

# --- prostředí, čas a procesy ---

LC_ALL = 6
# glibc nl_langinfo: položky LC_TIME (_NL_ITEM(LC_TIME = 2, index))
NL_TIME_WEEK_1STDAY = 131174
NL_TIME_FIRST_WEEKDAY = 131176

# setlocale(LC_ALL, ""): jazyk, formáty data a překlady podle prostředí
# (LANG, LC_*). gtk.init() to dělá sama; služba bez GTK (hodiny, strftime)
# zavolá setlocale() před prvním formátováním. Vrací název nastaveného
# locale, "" když prostředí žádné platné nemá.
function setlocale():
    return from_c(__lsl_qbe_call2(__lsl_symbol("setlocale"), LC_ALL, cstr("")))
end

# Místní čas teď ve formátu g_date_time_format (%H:%M, %A %-d. %B …; názvy
# dnů a měsíců podle locale po setlocale()).
function date_time_format(format):
    now = __lsl_qbe_call0(__lsl_symbol("g_date_time_new_now_local"))
    text = take_c(__lsl_qbe_call2(__lsl_symbol("g_date_time_format"), now, cstr(format)))
    call __lsl_qbe_call1(__lsl_symbol("g_date_time_unref"), now)
    return text
end

# Daný den (místní čas) ve formátu g_date_time_format, např. název měsíce
# nebo dne v týdnu pro kalendář: format_date(2026, 10, 23, "%A").
function format_date(year, month, day, format):
    date = __lsl_qbe_call6(__lsl_symbol("g_date_time_new_local"), ptr(year), ptr(month), ptr(day), 0, 0, Float(0))
    if date == 0:
        return ""
    end
    text = take_c(__lsl_qbe_call2(__lsl_symbol("g_date_time_format"), date, cstr(format)))
    call __lsl_qbe_call1(__lsl_symbol("g_date_time_unref"), date)
    return text
end

# Čas UNIXu (sekundy) v místním čase ve formátu g_date_time_format.
function format_unix(seconds, format):
    date = __lsl_qbe_call1(__lsl_symbol("g_date_time_new_from_unix_local"), ptr(seconds))
    if date == 0:
        return ""
    end
    text = take_c(__lsl_qbe_call2(__lsl_symbol("g_date_time_format"), date, cstr(format)))
    call __lsl_qbe_call1(__lsl_symbol("g_date_time_unref"), date)
    return text
end

# Místní datum a čas teď: [rok, měsíc, den, hodina, minuta, sekunda,
# den v týdnu 1–7 (pondělí = 1), den v roce].
function local_date():
    now = __lsl_qbe_call0(__lsl_symbol("g_date_time_new_now_local"))
    parts = [__lsl_qbe_call1(__lsl_symbol("g_date_time_get_year"), now), __lsl_qbe_call1(__lsl_symbol("g_date_time_get_month"), now), __lsl_qbe_call1(__lsl_symbol("g_date_time_get_day_of_month"), now), __lsl_qbe_call1(__lsl_symbol("g_date_time_get_hour"), now), __lsl_qbe_call1(__lsl_symbol("g_date_time_get_minute"), now), __lsl_qbe_call1(__lsl_symbol("g_date_time_get_second"), now), __lsl_qbe_call1(__lsl_symbol("g_date_time_get_day_of_week"), now), __lsl_qbe_call1(__lsl_symbol("g_date_time_get_day_of_year"), now)]
    call __lsl_qbe_call1(__lsl_symbol("g_date_time_unref"), now)
    return parts
end

# Počet dnů v měsíci a den v týdnu (1 = pondělí … 7 = neděle) daného data.
function days_in_month(year, month):
    return __lsl_qbe_u8(__lsl_qbe_call2(__lsl_symbol("g_date_get_days_in_month"), ptr(month), ptr(year)))
end

function weekday(year, month, day):
    date = __lsl_qbe_call3(__lsl_symbol("g_date_new_dmy"), ptr(day), ptr(month), ptr(year))
    result = __lsl_qbe_call1(__lsl_symbol("g_date_get_weekday"), date)
    call __lsl_qbe_call1(__lsl_symbol("g_date_free"), date)
    return result
end

# První den týdne podle locale (1 = pondělí … 7 = neděle; glibc
# _NL_TIME_FIRST_WEEKDAY je pořadí vztažené k datu _NL_TIME_WEEK_1STDAY,
# které nl_langinfo vrací přímo jako hodnotu ukazatele). Volat po setlocale().
function first_weekday():
    first = __lsl_qbe_call1(__lsl_symbol("nl_langinfo"), NL_TIME_FIRST_WEEKDAY)
    base = __lsl_qbe_call1(__lsl_symbol("nl_langinfo"), NL_TIME_WEEK_1STDAY)
    if first == 0:
        return 1
    end
    offset = __lsl_qbe_load8(first) - 1
    # 19971130 = neděle, 19971201 = pondělí
    if base == 19971130:
        return (offset + 6) % 7 + 1
    end
    return offset % 7 + 1
end

# Signál procesu (SIGTERM = 15, SIGUSR1 = 10, SIGUSR2 = 12): 0 = odesláno,
# -1 = chyba (proces neběží nebo bez oprávnění).
function kill(pid, signum):
    return __lsl_qbe_s32(__lsl_qbe_call2(__lsl_symbol("kill"), ptr(pid), ptr(signum)))
end

# Nahradí běžící proces programem (execvp, hledání v PATH; argv[0] je jméno
# programu). Vrací jen při chybě (-1), jinak se nevrátí.
function exec(argv):
    array = cstr_array(argv)
    call __lsl_qbe_call2(__lsl_symbol("execvp"), __lsl_qbe_load64(array_data(array)), array_data(array))
    return -1
end

# Spustí program na pozadí s výstupem do /dev/null (notify-send apod.).
# G_SPAWN_STDOUT_TO_DEV_NULL = 8, G_SPAWN_STDERR_TO_DEV_NULL = 16.
function spawn_quiet(argv):
    return spawn_flags(argv, 4 + 8 + 16)
end

# Časovače s prioritou (PRIORITY_HIGH pro služby, které musí reagovat hned).
function timeout_add_full(priority, interval, handler):
    return __lsl_qbe_call5(__lsl_symbol("g_timeout_add_full"), ptr(priority), ptr(interval), callback_first(), record_new(handler, 0), 0)
end

function timeout_add_seconds_full(priority, interval, handler):
    return __lsl_qbe_call5(__lsl_symbol("g_timeout_add_seconds_full"), ptr(priority), ptr(interval), callback_first(), record_new(handler, 0), 0)
end

function unix_signal_add_full(priority, signum, handler):
    return __lsl_qbe_call5(__lsl_symbol("g_unix_signal_add_full"), ptr(priority), ptr(signum), callback_first(), record_new(handler, 0), 0)
end

function user_cache_dir():
    return from_c(__lsl_qbe_call0(__lsl_symbol("g_get_user_cache_dir")))
end

function user_data_dir():
    return from_c(__lsl_qbe_call0(__lsl_symbol("g_get_user_data_dir")))
end

function getenv(name):
    return from_c(__lsl_qbe_call1(__lsl_symbol("g_getenv"), cstr(name)))
end

# Cesta z URI file:// ("" když URI není souborové).
function filename_from_uri(uri):
    return take_c(__lsl_qbe_call3(__lsl_symbol("g_filename_from_uri"), cstr(uri), 0, 0))
end

function filename_to_uri(path):
    return take_c(__lsl_qbe_call3(__lsl_symbol("g_filename_to_uri"), cstr(path), 0, 0))
end

# Text bezpečně uvozený pro shell a velikost pro uživatele („1,2 MB“).
function shell_quote(text):
    return take_c(__lsl_qbe_call1(__lsl_symbol("g_shell_quote"), cstr(text)))
end

function format_size(size):
    return take_c(__lsl_qbe_call1(__lsl_symbol("g_format_size"), ptr(size)))
end
