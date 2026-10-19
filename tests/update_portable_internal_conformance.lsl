# lsl: internal-abi
# Self-update pro Windows a macOS (update_portable.lsl), testovaný na všech
# systémech s přejmenováním: přesun spuštěného programu, výměna a obnova
# instalace, kontrola archivu ZIP, výběr artefaktu z manifestu, podpis
# manifestu zakompilovaným klíčem a SHA-256.
load update_portable as updater
load update_manifest as manifest
load release_crypto as crypto

function bytes(text):
    value = String(text)
    result = __lsl_byte_zeros(__lsl_text_byte_length(value))
    for i in range(len(result)):
        result[i] = __lsl_text_byte(value, i)
    end
    return result
end

function zip_rejected(hex):
    failed = False
    try:
        call updater.zip_entries(crypto.hex_bytes(hex), "lsl-9.9.9")
    else:
        failed = True
    end
    return failed
end

function manifest_rejected(text, system, architecture):
    failed = False
    try:
        call manifest.manifest_value(text, "0.10.1", system, architecture, False)
    else:
        failed = True
    end
    return failed
end

function signature_rejected(work):
    failed = False
    try:
        call updater.verify_signature(work)
    else:
        failed = True
    end
    return failed
end

function swap_rejected(prefix, store):
    failed = False
    try:
        call updater.swap_in(prefix, store, "0.0.1")
    else:
        failed = True
    end
    return failed
end

GOOD_ZIP = "504b030414000000000000004f5d0000000000000000000000000a0000006c736c2d392e392e392f504b030414000000000000004f5de65d294a0c0000000c0000001d0000006c736c2d392e392e392f62696e2f6c736c2d696e7374616c6c2e6578654d5a20696e7374616c6c6572504b030414000000000000004f5df386358706000000060000001b0000006c736c2d392e392e392f6c69622f6c736c2f524541444d452e6d64726561646d65504b0102140314000000000000004f5d0000000000000000000000000a0000000000000000000000ed41000000006c736c2d392e392e392f504b0102140314000000000000004f5de65d294a0c0000000c0000001d0000000000000000000000ed81280000006c736c2d392e392e392f62696e2f6c736c2d696e7374616c6c2e657865504b0102140314000000000000004f5df386358706000000060000001b0000000000000000000000a4016f0000006c736c2d392e392e392f6c69622f6c736c2f524541444d452e6d64504b05060000000003000300cc000000ae0000000000"
EVIL_ZIP = "504b030414000000000000004f5d0000000000000000000000000a0000006c736c2d392e392e392f504b030414000000000000004f5d8316dc8c0100000001000000150000006c736c2d392e392e392f2e2e2f6576696c2e74787478504b0102140314000000000000004f5d0000000000000000000000000a0000000000000000000000ed41000000006c736c2d392e392e392f504b0102140314000000000000004f5d8316dc8c0100000001000000150000000000000000000000a401280000006c736c2d392e392e392f2e2e2f6576696c2e747874504b050600000000020002007b0000005c0000000000"
LINK_ZIP = "504b030414000000000000004f5d0000000000000000000000000a0000006c736c2d392e392e392f504b030414000000000000004f5d0ab91f290b0000000b000000120000006c736c2d392e392e392f62696e2f6c696e6b2f6574632f706173737764504b0102140314000000000000004f5d0000000000000000000000000a0000000000000000000000ed41000000006c736c2d392e392e392f504b0102140314000000000000004f5d0ab91f290b0000000b000000120000000000000000000000ffa1280000006c736c2d392e392e392f62696e2f6c696e6b504b0506000000000200020078000000630000000000"
OTHER_ZIP = "504b030414000000000000004f5d8316dc8c01000000010000001d0000006c736c2d392e392e382f62696e2f6c736c2d696e7374616c6c2e65786578504b0102140314000000000000004f5d8316dc8c01000000010000001d0000000000000000000000ed01000000006c736c2d392e392e382f62696e2f6c736c2d696e7374616c6c2e657865504b050600000000010001004b0000003c0000000000"
ENCRYPTED_ZIP = "504b030414000000000000004f5d0000000000000000000000000a0000006c736c2d392e392e392f504b030414000000000000004f5de65d294a0c0000000c0000001d0000006c736c2d392e392e392f62696e2f6c736c2d696e7374616c6c2e6578654d5a20696e7374616c6c6572504b030414000000000000004f5df386358706000000060000001b0000006c736c2d392e392e392f6c69622f6c736c2f524541444d452e6d64726561646d65504b0102140314000100000000004f5d0000000000000000000000000a0000000000000000000000ed41000000006c736c2d392e392e392f504b0102140314000000000000004f5de65d294a0c0000000c0000001d0000000000000000000000ed81280000006c736c2d392e392e392f62696e2f6c736c2d696e7374616c6c2e657865504b0102140314000000000000004f5df386358706000000060000001b0000000000000000000000a4016f0000006c736c2d392e392e392f6c69622f6c736c2f524541444d452e6d64504b05060000000003000300cc000000ae0000000000"
# channels/stable.json vydání 0.10.1 a jeho podpis (produkční klíč).
SIGNED_MANIFEST = "7b0a202022736368656d61223a20312c0a20202270726f64756374223a20226c736c222c0a2020226368616e6e656c223a2022737461626c65222c0a20202276657273696f6e223a2022302e31302e31222c0a20202272656c65617365645f6174223a2022323032362d31302d31355431333a35353a32395a222c0a20202272656c656173655f6b65795f6964223a202236393330663937363965666461613166363231383338373564353430623334306261623130663430303630303832663239656564643564636561643832333161222c0a202022617274696661637473223a205b0a202020207b0a202020202020226f73223a20226c696e7578222c0a20202020202022617263686974656374757265223a20227838365f3634222c0a20202020202022666f726d6174223a20227461722e677a222c0a2020202020202275726c223a202268747470733a2f2f6c736c2e6c75782d61692e637a2f757064617465732f72656c65617365732f302e31302e312f6c736c2d302e31302e312d6c696e75782d7838365f36342e7461722e677a222c0a2020202020202273697a65223a20333534383332322c0a20202020202022736861323536223a202231366535373930343561396162363633336538613531326162356666303135613736303739393466613633616332363862646362326336393664633561303436222c0a20202020202022617263686976655f726f6f74223a20226c736c2d302e31302e31222c0a20202020202022696e7374616c6c6572223a202262696e2f6c736c2d696e7374616c6c220a202020207d2c0a202020207b0a202020202020226f73223a20226c696e7578222c0a20202020202022617263686974656374757265223a202261617263683634222c0a20202020202022666f726d6174223a20227461722e677a222c0a2020202020202275726c223a202268747470733a2f2f6c736c2e6c75782d61692e637a2f757064617465732f72656c65617365732f302e31302e312f6c736c2d302e31302e312d6c696e75782d616172636836342e7461722e677a222c0a2020202020202273697a65223a20333137353730322c0a20202020202022736861323536223a202261333861333938636134326135376564326166633336623334623138393334333063313032383466346336623166363536396231653561653038633262646164222c0a20202020202022617263686976655f726f6f74223a20226c736c2d302e31302e31222c0a20202020202022696e7374616c6c6572223a202262696e2f6c736c2d696e7374616c6c220a202020207d0a20205d0a7d0a"
SIGNATURE = "520a4110966eb445996e60e5e07f04da7c892bcda7d7bfbee860719726a5f6306ce4659407549f0e37f8fe1888e4f7e0cebddeaf10bc34dedc3cd92513397c0b"

stamp = String(Int(monotonic() * 1000000.0))
root = "lsl-update-internal-" + stamp
unsafe:
    check(__lsl_mkdir_private(root) == 0, "create test directory")

    # Spuštěný program jde přesunout a vrátit (Windows: MoveFileExW).
    me = executable_path()
    print "move running program", __lsl_rename(me, me + ".moved") == 0, __lsl_rename(me + ".moved", me) == 0

    # Výměna: aktivní verze do outgoing, nová z incoming do prefixu.
    prefix = root + "/prefix"
    store = prefix + "/lib/lsl-updates"
    for base in [prefix, store + "/incoming"]:
        call updater.make_directories(base + "/bin")
        call updater.make_directories(base + "/lib/lsl")
    end
    for name in updater.binary_names():
        call writefile(prefix + "/bin/" + name, "old")
        call writefile(store + "/incoming/bin/" + name, "new")
    end
    call writefile(prefix + "/lib/lsl/marker", "old")
    call writefile(store + "/incoming/lib/lsl/marker", "new")
    lsl = updater.executable_name("lsl")
    call updater.swap_in(prefix, store, "0.0.1")
    print "swapped", readfile(prefix + "/bin/" + lsl), readfile(prefix + "/lib/lsl/marker"), readfile(store + "/outgoing/bin/" + lsl), readfile(store + "/outgoing/version").strip(), exists(store + "/journal")
    # Obnova po přerušení vrátí starou verzi a novou uloží zpět do incoming.
    print "recovered", updater.recover(prefix, store)
    print "after recovery", readfile(prefix + "/bin/" + lsl), readfile(prefix + "/lib/lsl/marker"), readfile(store + "/incoming/bin/" + lsl), readfile(store + "/incoming/lib/lsl/marker"), exists(store + "/journal"), exists(store + "/outgoing")
    # Přerušení uprostřed výměny: jen část položek je přesunutá.
    call writefile(store + "/journal", "swap" + chr(10))
    call updater.make_directories(store + "/outgoing/bin")
    call updater.make_directories(store + "/outgoing/lib")
    call updater.move(prefix + "/bin/" + lsl, store + "/outgoing/bin/" + lsl)
    call updater.move(prefix + "/lib/lsl", store + "/outgoing/lib/lsl")
    print "partial recovered", updater.recover(prefix, store)
    complete = True
    for name in updater.binary_names():
        if readfile(prefix + "/bin/" + name) != "old" or readfile(store + "/incoming/bin/" + name) != "new":
            complete = False
        end
    end
    print "partial state", complete, readfile(prefix + "/lib/lsl/marker"), exists(store + "/outgoing")
    print "no journal", updater.recover(prefix, store)
    # Neúplná výměna se nepřepíše: outgoing už existuje.
    call updater.make_directories(store + "/outgoing")
    print "outgoing refused", swap_rejected(prefix, store)
    call rmdir(store + "/outgoing")
    call unlink(store + "/journal")

    # ZIP: jen soubory a adresáře pod kořenem, bez "..", odkazů a šifrování.
    print "zip", updater.zip_entries(crypto.hex_bytes(GOOD_ZIP), "lsl-9.9.9")
    print "zip traversal", zip_rejected(EVIL_ZIP)
    print "zip link", zip_rejected(LINK_ZIP)
    print "zip root", zip_rejected(OTHER_ZIP)
    print "zip encrypted", zip_rejected(ENCRYPTED_ZIP)
    print "zip garbage", zip_rejected("6e6f742061207a6970206172636869766520617420616c6c")

    # Manifest se všemi platformami: každý systém dostane svůj archiv.
    hash = "0" * 64
    artifacts = []
    # Velikosti jsou jedinečné, aby šlo změnit jen jeden artefakt; Windows
    # nad 32 MiB (balík s LLVM) je platný.
    for item in [["linux", "x86_64", "tar.gz", "bin/lsl-install", "3000001"], ["linux", "aarch64", "tar.gz", "bin/lsl-install", "3000002"], ["linux", "riscv64", "tar.gz", "bin/lsl-install", "3000003"], ["windows", "x86_64", "zip", "bin/lsl-install.exe", "34000001"], ["windows", "arm64", "zip", "bin/lsl-install.exe", "34000002"], ["macos", "arm64", "tar.gz", "bin/lsl-install", "3000004"], ["macos", "x86_64", "tar.gz", "bin/lsl-install", "3000005"]]:
        url = "https://lsl.lux-ai.cz/updates/releases/0.10.2/lsl-0.10.2-" + item[0] + "-" + item[1] + "." + item[2]
        artifacts.append("{\"os\": \"" + item[0] + "\", \"architecture\": \"" + item[1] + "\", \"format\": \"" + item[2] + "\", \"url\": \"" + url + "\", \"size\": " + item[4] + ", \"sha256\": \"" + hash + "\", \"archive_root\": \"lsl-0.10.2\", \"installer\": \"" + item[3] + "\"}")
    end
    text = "{\"schema\": 1, \"product\": \"lsl\", \"channel\": \"stable\", \"version\": \"0.10.2\", \"released_at\": \"2026-10-16T00:00:00Z\", \"release_key_id\": \"" + manifest.KEY_ID + "\", \"artifacts\": [" + ", ".join(artifacts) + "]}"
    for item in [["windows", "x86_64"], ["windows", "arm64"], ["macos", "arm64"], ["macos", "x86_64"]]:
        print "select", manifest.manifest_value(text, "0.10.1", item[0], item[1], False)["artifact"]["url"]
    end
    print "linux", manifest.manifest_value(text, "0.10.1", "linux", "riscv64", False)["artifact"]["size"]
    print "linux archive limit", manifest_rejected(text.replace("3000001", "33554433"), "linux", "x86_64")
    print "windows at limit", manifest.manifest_value(text.replace("34000002", "67108864"), "0.10.1", "windows", "arm64", False)["artifact"]["size"]
    print "windows archive limit", manifest_rejected(text.replace("34000002", "67108865"), "windows", "arm64")
    print "windows tar.gz", manifest_rejected(text.replace("x86_64.zip\", \"size", "x86_64.tar.gz\", \"size"), "windows", "x86_64")
    print "macos exe installer", manifest_rejected(text.replace("arm64.tar.gz\", \"size\": 3000004, \"sha256\": \"" + hash + "\", \"archive_root\": \"lsl-0.10.2\", \"installer\": \"bin/lsl-install\"", "arm64.tar.gz\", \"size\": 3000004, \"sha256\": \"" + hash + "\", \"archive_root\": \"lsl-0.10.2\", \"installer\": \"bin/lsl-install.exe\""), "macos", "arm64")
    print "unknown platform", manifest_rejected(text, "freebsd", "x86_64")

    # Podpis manifestu zakompilovaným klíčem vydání.
    work = root + "/work"
    check(__lsl_mkdir_private(work) == 0, "create work directory")
    call writebytes(work + "/manifest.json", crypto.hex_bytes(SIGNED_MANIFEST))
    call writebytes(work + "/manifest.sig", crypto.hex_bytes(SIGNATURE))
    print "signed manifest", len(updater.verify_signature(work))
    changed = crypto.hex_bytes(SIGNED_MANIFEST)
    changed[20] = changed[20] ~ 1
    call writebytes(work + "/manifest.json", changed)
    print "changed manifest", signature_rejected(work)
    call writebytes(work + "/manifest.json", crypto.hex_bytes(SIGNED_MANIFEST))
    call writebytes(work + "/manifest.sig", __lsl_byte_zeros(64))
    print "zero signature", signature_rejected(work)
    call writebytes(work + "/manifest.sig", __lsl_byte_zeros(63))
    print "short signature", signature_rejected(work)

    # RFC 8032, oddíl 7.1, testy 1 a 2.
    print "rfc8032", crypto.ed25519_verify(crypto.hex_bytes("e5564300c360ac729086e2cc806e828a84877f1eb8e5d974d873e065224901555fb8821590a33bacc61e39701cf9b46bd25bf5f0595bbe24655141438e7a100b"), __lsl_byte_zeros(0), crypto.hex_bytes("d75a980182b10ab7d54bfed3c964073a0ee172f3daa62325af021a68f707511a")), crypto.ed25519_verify(crypto.hex_bytes("92a009a9f0d4cab8720e820b5f642540a2b27b5416503f8fb3762223ebdb69da085ac1e43e15996e458f3613d0f11d8c387b2eaeb4302aeeb00d291612bb0c00"), crypto.hex_bytes("72"), crypto.hex_bytes("3d4017c3e843895a92b70aa74d1b7ebc9c982ccf2ec4968cc0cd55f12af4660c"))

    # SHA-256 (FIPS 180-4): prázdný vstup, "abc", 448 bitů, milion "a".
    print crypto.sha256_hex(__lsl_byte_zeros(0))
    print crypto.sha256_hex(bytes("abc"))
    print crypto.sha256_hex(bytes("abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq"))
    million = __lsl_byte_zeros(1000000)
    for i in range(len(million)):
        million[i] = 97
    end
    print crypto.sha256_hex(million)

    call updater.remove_tree(root)
    print "removed", exists(root)
end
