load json
load lconf

source = "# Lux package dependencies" + chr(10)
source += "apt: gimp, libjpeg62-turbo:amd64" + chr(10)
source += "lux: lux-ai" + chr(10)
source += "lsl: external_pckg" + chr(10)
manifest = lconf.parse(source, "demo/config.lconf")
print json.encode(manifest)
encoded = lconf.encode(manifest)
print encoded == "apt: gimp\napt: libjpeg62-turbo:amd64\nlux: lux-ai\nlsl: external_pckg\n"
print json.encode(lconf.decode(encoded)) == json.encode(manifest)

for invalid in [
    "unknown: item",
    "apt item",
    "apt:",
    "apt: bad name",
    "lux: duplicate\nlux: duplicate"
]:
    try:
        call lconf.parse(invalid, "bad.lconf")
    else:
        print last_error()
    end
end
