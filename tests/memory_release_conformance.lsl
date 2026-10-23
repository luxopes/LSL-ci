# Po úklidu GC se stránky velkých volných bloků vracejí jádru
# (MADV_DONTNEED): anonymní paměť klesne pod čtvrtinu vrcholu.
load fd

function anon_kib():
    for line in fd.read_text_limit("/proc/self/status", 65536).split("\n"):
        if line.startswith("RssAnon:"):
            return Int(line[8:len(line)].strip().split(" ")[0])
        end
    end
    Error(TestFailure: "RssAnon unavailable")
end

# Data vznikají ve funkci, aby po návratu nezůstal odkaz na zásobníku.
function churn():
    big = []
    for i in rang(40):
        big.append("x" * 1048576)
    end
    return anon_kib()
end

peak = churn()
call gc()
after = anon_kib()
if peak < 30000:
    Error(TestFailure: "peak only " + String(peak) + " KiB")
end
if after * 4 > peak:
    Error(TestFailure: "RssAnon after gc " + String(after) + " KiB of peak " + String(peak) + " KiB")
end
print("ok")
