# Paměťová stopa malého programu: anonymní paměť pod 512 KiB. Bitmapa
# objektů (4 MiB řídká mapa) nesmí s THP "always" zabrat 2 MiB fyzické
# paměti (runtime ji mapuje s MADV_NOHUGEPAGE).
load fd

function status_kib(key):
    for line in fd.read_text_limit("/proc/self/status", 65536).split("\n"):
        if line.startswith(key):
            return Int(line[len(key):len(line)].strip().split(" ")[0])
        end
    end
    Error(TestFailure: key + " unavailable")
end

anonymous = status_kib("RssAnon:")
if anonymous > 512:
    Error(TestFailure: "RssAnon " + String(anonymous) + " KiB, expected at most 512 KiB")
end
print("ok")
