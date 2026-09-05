load fd
load json
load update
load update_install

function require(condition, message):
    if not condition:
        Error(TestFailure: message)
    end
end

function reject_manifest(text):
    rejected = False
    try:
        call update.manifest_value(text, "0.7.7", "x86_64", False)
    else:
        rejected = True
    end
    call require(rejected, "unsafe manifest accepted")
end

function reject_signature(work):
    rejected = False
    try:
        call update.verified_manifest(work, "0.7.7", "x86_64", False)
    else:
        rejected = True
    end
    call require(rejected, "untrusted signature accepted")
end

function put_text(buffer, offset, text):
    data = ByteArray(buffer)
    for index in rang(len(text)):
        data[offset + index] = ord(text[index])
    end
end

function octal(value, width):
    result = ""
    number = Int(value)
    for index in rang(width - 1):
        result = String(number % 8) + result
        number = number // 8
    end
    return result + chr(0)
end

function checksum(buffer, offset):
    data = ByteArray(buffer)
    call put_text(data, offset + 148, "        ")
    total = 0
    for index in rang(512):
        total += data[offset + index]
    end
    call put_text(data, offset + 148, octal(total, 7) + " ")
end

function header(name, kind, size):
    data = __lsl_byte_zeros(512)
    call put_text(data, 0, name)
    call put_text(data, 100, octal(493, 8))
    call put_text(data, 108, octal(0, 8))
    call put_text(data, 116, octal(0, 8))
    call put_text(data, 124, octal(size, 12))
    call put_text(data, 136, octal(0, 12))
    data[156] = Int(kind)
    call put_text(data, 257, "ustar" + chr(0) + "00")
    call checksum(data, 0)
    return data
end

function archive():
    data = __lsl_byte_zeros(3072)
    call __lsl_byte_copy(data, header("lsl-0.7.7/", 53, 0), 0, 0, 512)
    call __lsl_byte_copy(data, header("lsl-0.7.7/bin/", 53, 0), 512, 0, 512)
    call __lsl_byte_copy(data, header("lsl-0.7.7/bin/lsl-install", 48, 176), 1024, 0, 512)
    data[1536] = 127
    call put_text(data, 1537, "ELF")
    data[1540] = 2
    data[1541] = 1
    data[1552] = 3
    data[1554] = 62
    return data
end

function reject_tar(data):
    rejected = False
    try:
        entries = update.tar_entries(data, "lsl-0.7.7")
        call update.installer_entry(data, entries, "lsl-0.7.7")
    else:
        rejected = True
    end
    call require(rejected, "unsafe tar archive accepted")
end

function main():
    work = update_install.private_work("/tmp")
    helper = arg(1)
    text = readfile("tests/compiler/fixtures/update-stable.json")
    signature = readbytes("tests/compiler/fixtures/update-stable.sig")
    call writefile(work + "/manifest.json", text)
    call writebytes(work + "/manifest.sig", signature)
    verified = update.verified_manifest(work, "0.7.7", "x86_64", False)
    call require(verified["version"] == "0.7.7" and verified["comparison"] == 0, "valid signed fixture rejected")
    call require(update.compare_versions("0.10.0", "0.9.99") == 1, "version comparison is lexical")
    call require(update.compare_versions("1.0.0", "0.99.99") == 1, "major comparison")
    call require(update.compare_versions("0.7.6", "0.7.7") == -1, "patch comparison")
    for version in ["0.7.6", "0.7", "0.7.7.0", "0.7.-1", "00.7.7", "9999999999.0.0", "0.7.7-beta", "../0.7.7"]:
        call reject_manifest(text.replace("0.7.7", version))
    end
    permitted = update.manifest_value(text.replace("0.7.7", "0.7.6"), "0.7.7", "x86_64", True)
    call require(permitted["comparison"] == -1, "explicit downgrade flag failed")
    for replacement in ["\"schema\": true", "\"schema\": 1.0", "\"schema\": 2", "\"schema\": 1, \"schema\": 1", "\"schema\": 1, \"extra\": 1"]:
        call reject_manifest(text.replace("\"schema\": 1", replacement))
    end
    call reject_manifest(text.replace("stable", "nightly"))
    call reject_manifest(text.replace(update.KEY_ID, "0" * 64))
    call reject_manifest(text.replace("2026-09-05", "2026-02-30"))
    call reject_manifest(text.replace("1397462", "33554433"))
    call reject_manifest(text.replace("1397462", "-1"))
    call reject_manifest(text.replace("1397462", "1.5"))
    call reject_manifest(text.replace("x86_64", "aarch64"))
    call reject_manifest(text.replace("linux", "windows"))
    call reject_manifest(text.replace("tar.gz", "zip"))
    call reject_manifest(text.replace("bin/lsl-install", "bin/evil"))
    call reject_manifest(text.replace("211f6ab4", "211F6AB4"))
    call reject_manifest(text.replace("https://lsl.lux-ai.cz/", "https://evil.invalid/"))
    call reject_manifest(text + "garbage")
    for url in ["http://lsl.lux-ai.cz/updates/x", "https://lsl.lux-ai.cz.evil/updates/x", "https://lsl.lux-ai.cz@evil/updates/x", "https://lsl.lux-ai.cz:443/updates/x", "https://lsl.lux-ai.cz/updates/../x", "https://lsl.lux-ai.cz/updates/%2e/x", "https://lsl.lux-ai.cz/updates/x?y", "https://lsl.lux-ai.cz/updates/x#y", "https://lsl.lux-ai.cz/updates/[1-2]"]:
        rejected = False
        try:
            call update.allowed_url(url)
        else:
            rejected = True
        end
        call require(rejected, "unsafe update URL accepted")
    end
    call update.allowed_url(update.MANIFEST_URL)
    call writefile(work + "/manifest.json", text + chr(10))
    call reject_signature(work)
    call writefile(work + "/manifest.json", text)
    signature[0] = signature[0] ~ 1
    call writebytes(work + "/manifest.sig", signature)
    call reject_signature(work)
    for size in [0, 63, 65, 1024]:
        call writebytes(work + "/manifest.sig", __lsl_byte_zeros(size))
        call reject_signature(work)
    end
    # A valid signature from an unrelated, ephemeral key is not a trust root.
    call update_install.bounded(update_install.tool("openssl"), ["genpkey", "-algorithm", "ED25519", "-out", work + "/test-key.pem"], 65536, 30)
    call update_install.bounded(update_install.tool("openssl"), ["pkeyutl", "-sign", "-rawin", "-inkey", work + "/test-key.pem", "-in", work + "/manifest.json", "-out", work + "/manifest.sig"], 65536, 30)
    call reject_signature(work)
    call unlink(work + "/test-key.pem")
    print "update manifest and signature checks ok"

    valid = archive()
    entries = update.tar_entries(valid, "lsl-0.7.7")
    call update.installer_entry(valid, entries, "lsl-0.7.7")
    for kind in [49, 50, 51, 52, 54, 55, 76, 75, 83, 120, 103]:
        bad = archive()
        bad[1180] = Int(kind)
        call checksum(bad, 1024)
        call reject_tar(bad)
    end
    for path in ["/absolute", "lsl-0.7.7/../escape", "other/bin/lsl-install", "lsl-0.7.7//x", "lsl-0.7.7/./x", "lsl-0.7.7/bin", "lsl-0.7.7/missing/x", "lsl-0.7.7/bin/evil"]:
        bad = archive()
        call __lsl_byte_copy(bad, header(path, 48, 176), 1024, 0, 512)
        call reject_tar(bad)
    end
    bad = archive()
    bad[1100] = 255
    call reject_tar(bad)
    bad = archive()
    call put_text(bad, 1124, octal(2541, 8))
    call checksum(bad, 1024)
    call reject_tar(bad)
    bad = archive()
    call put_text(bad, 1148, octal(16777217, 12))
    call checksum(bad, 1024)
    call reject_tar(bad)
    bad = archive()
    bad[1536] = 0
    call reject_tar(bad)
    bad = archive()
    bad[2049] = 1
    call reject_tar(bad)
    bad = __lsl_byte_zeros(2048)
    call __lsl_byte_copy(bad, valid, 0, 0, 2048)
    call reject_tar(bad)
    call writebytes(work + "/archive", valid)
    hash = update_install.bounded(update_install.tool("sha256sum"), [work + "/archive"], 1048576, 30)[0:64]
    artifact = {"size": len(valid), "sha256": hash}
    call update.verify_archive(work + "/archive", artifact)
    valid[2000] = 1
    call writebytes(work + "/archive", valid)
    rejected = False
    try:
        call update.verify_archive(work + "/archive", artifact)
    else:
        rejected = True
    end
    call require(rejected, "corrupt archive hash accepted")
    artifact["size"] = 1
    rejected = False
    try:
        call update.verify_archive(work + "/archive", artifact)
    else:
        rejected = True
    end
    call require(rejected, "incorrect archive size accepted")
    print "update archive checks ok"

    rejected = False
    try:
        call update_install.bounded(helper, ["overflow", work + "/oversized"], 64, 10)
    else:
        rejected = True
    end
    call require(rejected and update_install.metadata(work + "/oversized")["size"] <= 64, "kernel file size limit failed")
    call update_install.directory(work + "/store")
    store = work + "/store"
    handle = update_install.lock(store)
    rejected = False
    try:
        call update_install.lock(store)
    else:
        rejected = True
    end
    call fd.close(handle)
    call require(rejected, "concurrent updater lock succeeded")
    call unlink(store + "/lock")
    call writefile(work + "/victim", "untouched")
    call update_install.link(work + "/victim", store + "/lock")
    rejected = False
    try:
        call update_install.lock(store)
    else:
        rejected = True
    end
    call require(rejected and readfile(work + "/victim") == "untouched", "lock symlink followed")
    call unlink(store + "/lock")
    call update_install.link(work, store + "/symlink")
    rejected = False
    try:
        call update_install.directory(store + "/symlink")
    else:
        rejected = True
    end
    call require(rejected, "symlink staging directory accepted")
    rejected = False
    try:
        call update_install.installation("/usr/local/bin/lsl", "/home/test", False)
    else:
        rejected = String(last_error()).find("explicit administrator invocation") >= 0
    end
    call require(rejected, "system update did not require explicit administrator invocation")
    rejected = False
    try:
        call update_install.installation(executable_path(), None, False)
    else:
        rejected = True
    end
    call require(rejected, "self-update accepted a development binary")
    print "update limits and filesystem checks ok"

    call update_install.directory(store + "/generations")
    old = update_install.private_work(store + "/generations")
    next = update_install.private_work(store + "/generations")
    for generation in [old, next]:
        call update_install.directory(generation + "/bin")
        call writebytes(generation + "/bin/lsl", readbytes(helper))
        call writefile(generation + "/version", "0.7.7" + chr(10))
    end
    call update_install.switch_link(old, store + "/current", work + "/initial-link")
    call update_install.activate(store, next, "0.7.7", work)
    call require(update_install.target(store, "current") == next and update_install.target(store, "previous") == old, "atomic activation failed")
    call require(not exists(store + "/pending"), "successful transaction left journal")
    call writefile(old + "/bin/lsl.bad", "bad")
    rejected = False
    try:
        call update_install.activate(store, old, "0.7.7", work)
    else:
        rejected = String(last_error()).find("rolled back") >= 0
    end
    call require(rejected and update_install.target(store, "current") == next, "post-switch failure did not roll back")
    call unlink(old + "/bin/lsl.bad")
    call writefile(old + "/bin/lsl.no-compile", "broken compiler")
    rejected = False
    try:
        call update_install.activate(store, old, "0.7.7", work)
    else:
        rejected = String(last_error()).find("rolled back") >= 0
    end
    call require(rejected and update_install.target(store, "current") == next, "stale smoke executable hid failed compilation")
    call unlink(old + "/bin/lsl.no-compile")
    call update_install.switch_link(old, store + "/previous", work + "/prior-link")
    call writefile(store + "/pending", "interrupted")
    call update_install.recover(store, work)
    call require(update_install.target(store, "current") == old, "rollback target lost")
    call require(not exists(store + "/pending"), "recovery left pending journal")
    call update_install.switch_link(next, store + "/previous", work + "/manual-link")
    call update_install.rollback(store, work)
    call require(update_install.target(store, "current") == next and update_install.target(store, "previous") == old, "manual rollback failed")
    call update_install.switch_link("/tmp", store + "/previous", work + "/escape-link")
    rejected = False
    try:
        call update_install.target(store, "previous")
    else:
        rejected = True
    end
    call require(rejected, "rollback link escaped store")
    print "update atomic activation and rollback checks ok"
    call update_install.cleanup_scratch(work)
end

call main()
