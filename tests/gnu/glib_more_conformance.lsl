# Modul glib, doplňky 0.10.6: locale a místní čas (g_date_time), kalendářní
# pomůcky, signály procesům, exec, tiché spuštění, časovače s prioritou,
# prostředí a cesty. Výstup nezávisí na jazyku prostředí.
load glib

if arg_count() > 1 and arg(1) == "child":
    call glib.exec(["sh", "-c", "echo exec ok"])
    print "exec failed"
    exit(3)
end

print type(glib.setlocale()) == "String"
today = glib.local_date()
print len(today), today[0] >= 2026, today[1] >= 1 and today[1] <= 12, today[2] >= 1 and today[2] <= 31, today[6] >= 1 and today[6] <= 7, today[7] >= 1 and today[7] <= 366
print glib.date_time_format("%Y") == String(today[0]), len(glib.date_time_format("%H:%M")) == 5
print glib.format_date(2026, 10, 23, "%Y-%m-%d|%u|%j"), glib.format_date(2026, 2, 30, "%d") == ""
print glib.format_unix(0, "%Y") == "1970" or glib.format_unix(0, "%Y") == "1969", glib.format_unix(86400 * 365, "%Y-%m-%d").startswith("197")
print glib.days_in_month(2024, 2), glib.days_in_month(2026, 2), glib.days_in_month(2026, 12), glib.weekday(2026, 10, 23), glib.weekday(2026, 10, 25)
first = glib.first_weekday()
print first >= 1 and first <= 7
print glib.kill(glib.getpid(), 0), glib.kill(2147483000, 0)
print glib.getenv("HOME") == glib.home_dir(), glib.getenv("LSL_NO_SUCH_VARIABLE") == ""
print glib.filename_from_uri("file:///tmp/a%20b"), glib.filename_from_uri("http://x/") == "", glib.filename_to_uri("/tmp/a b")
print glib.shell_quote("a b'c"), glib.format_size(1000).endswith("kB"), glib.user_cache_dir() != "", glib.user_data_dir() != ""
print capture(executable_path(), ["child"]).strip(), capture_status()
fired = []
function on_high():
    fired.append("high")
    return False
end
function on_second():
    fired.append("seconds")
    return False
end
call glib.timeout_add_full(glib.PRIORITY_HIGH, 5, on_high)
call glib.timeout_add_seconds_full(glib.PRIORITY_DEFAULT, 1, on_second)
# výstup potomka jde do /dev/null: „noise“ se v testu neobjeví
quiet = glib.spawn_quiet(["sh", "-c", "echo noise; echo noise >&2"])
print quiet > 0
call glib.timeout_add_seconds(2, glib.main_quit)
call glib.main()
print fired
