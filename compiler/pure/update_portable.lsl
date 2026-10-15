# Self-update na Windows a macOS zatím není (ověření podpisu a archivu
# vyžaduje nástroje Linuxu). Rozhraní je stejné jako update_linux_x86_64.lsl;
# operace hlásí srozumitelnou chybu.
DOWNLOAD = {"path": "", "received": 0, "expected": 0, "shown": -1}
KEY_ID = "6930f9769efdaa1f62183875d540b340bab10f40060082f29eedd5dcead8231a"
MANIFEST_URL = "https://lsl.lux-ai.cz/updates/channels/stable.json"
MAX_ARCHIVE = 33554432
MAX_MANIFEST = 65536
MAX_TAR = 67108864
PUBLIC_KEY = "-----BEGIN PUBLIC KEY-----\nMCowBQYDK2VwAyEA0wMrw+VLMcfb4IlJ/CF3rIOBY10enQ/SJxiFKcLtUpo=\n-----END PUBLIC KEY-----\n"

function fail(message):
    Error(UpdateError: "self-update is not available on Windows and macOS yet; download the new release from https://lsl.lux-ai.cz/ and run lsl-install")
end

function digits(text, maximum):
    Error(UpdateError: "self-update is not available on Windows and macOS yet; download the new release from https://lsl.lux-ai.cz/ and run lsl-install")
end

function version_parts(value):
    Error(UpdateError: "self-update is not available on Windows and macOS yet; download the new release from https://lsl.lux-ai.cz/ and run lsl-install")
end

function compare_versions(first, second):
    Error(UpdateError: "self-update is not available on Windows and macOS yet; download the new release from https://lsl.lux-ai.cz/ and run lsl-install")
end

function fields(value, expected):
    Error(UpdateError: "self-update is not available on Windows and macOS yet; download the new release from https://lsl.lux-ai.cz/ and run lsl-install")
end

function hash_string(value):
    Error(UpdateError: "self-update is not available on Windows and macOS yet; download the new release from https://lsl.lux-ai.cz/ and run lsl-install")
end

function timestamp(value):
    Error(UpdateError: "self-update is not available on Windows and macOS yet; download the new release from https://lsl.lux-ai.cz/ and run lsl-install")
end

function host_platform():
    Error(UpdateError: "self-update is not available on Windows and macOS yet; download the new release from https://lsl.lux-ai.cz/ and run lsl-install")
end

function manifest_value(text, current, architecture, allow_downgrade):
    Error(UpdateError: "self-update is not available on Windows and macOS yet; download the new release from https://lsl.lux-ai.cz/ and run lsl-install")
end

function allowed_url(url):
    Error(UpdateError: "self-update is not available on Windows and macOS yet; download the new release from https://lsl.lux-ai.cz/ and run lsl-install")
end

function download(url, path, maximum):
    Error(UpdateError: "self-update is not available on Windows and macOS yet; download the new release from https://lsl.lux-ai.cz/ and run lsl-install")
end

function download_chunk(chunk):
    Error(UpdateError: "self-update is not available on Windows and macOS yet; download the new release from https://lsl.lux-ai.cz/ and run lsl-install")
end

function download_progress(url, path, expected):
    Error(UpdateError: "self-update is not available on Windows and macOS yet; download the new release from https://lsl.lux-ai.cz/ and run lsl-install")
end

function verify_signature(work):
    Error(UpdateError: "self-update is not available on Windows and macOS yet; download the new release from https://lsl.lux-ai.cz/ and run lsl-install")
end

function verified_manifest(work, current, architecture, allow_downgrade):
    Error(UpdateError: "self-update is not available on Windows and macOS yet; download the new release from https://lsl.lux-ai.cz/ and run lsl-install")
end

function verify_archive(path, artifact):
    Error(UpdateError: "self-update is not available on Windows and macOS yet; download the new release from https://lsl.lux-ai.cz/ and run lsl-install")
end

function tar_string(buffer, offset, width):
    Error(UpdateError: "self-update is not available on Windows and macOS yet; download the new release from https://lsl.lux-ai.cz/ and run lsl-install")
end

function tar_octal(buffer, offset, width):
    Error(UpdateError: "self-update is not available on Windows and macOS yet; download the new release from https://lsl.lux-ai.cz/ and run lsl-install")
end

function archive_path(name, root):
    Error(UpdateError: "self-update is not available on Windows and macOS yet; download the new release from https://lsl.lux-ai.cz/ and run lsl-install")
end

function tar_entries(buffer, root):
    Error(UpdateError: "self-update is not available on Windows and macOS yet; download the new release from https://lsl.lux-ai.cz/ and run lsl-install")
end

function installer_entry(buffer, entries, root):
    Error(UpdateError: "self-update is not available on Windows and macOS yet; download the new release from https://lsl.lux-ai.cz/ and run lsl-install")
end

function extract_archive(work, artifact):
    Error(UpdateError: "self-update is not available on Windows and macOS yet; download the new release from https://lsl.lux-ai.cz/ and run lsl-install")
end

function options():
    Error(UpdateError: "self-update is not available on Windows and macOS yet; download the new release from https://lsl.lux-ai.cz/ and run lsl-install")
end

function execute(current, settings, work, prefix):
    Error(UpdateError: "self-update is not available on Windows and macOS yet; download the new release from https://lsl.lux-ai.cz/ and run lsl-install")
end

function main(current):
    Error(UpdateError: "self-update is not available on Windows and macOS yet; download the new release from https://lsl.lux-ai.cz/ and run lsl-install")
end
