# Veřejné API; operace hostitele poskytuje modul vybraný cílem.

load _update_platform as implementation

MANIFEST_URL = implementation.MANIFEST_URL
KEY_ID = implementation.KEY_ID
PUBLIC_KEY = implementation.PUBLIC_KEY
MAX_MANIFEST = implementation.MAX_MANIFEST
MAX_ARCHIVE = implementation.MAX_ARCHIVE
MAX_TAR = implementation.MAX_TAR
DOWNLOAD = implementation.DOWNLOAD

function fail(message):
    return implementation.fail(message)
end

function digits(text, maximum):
    return implementation.digits(text, maximum)
end

function version_parts(value):
    return implementation.version_parts(value)
end

function compare_versions(first, second):
    return implementation.compare_versions(first, second)
end

function fields(value, expected):
    return implementation.fields(value, expected)
end

function hash_string(value):
    return implementation.hash_string(value)
end

function timestamp(value):
    return implementation.timestamp(value)
end

function host_platform():
    return implementation.host_platform()
end

function manifest_value(text, current, architecture, allow_downgrade):
    return implementation.manifest_value(text, current, architecture, allow_downgrade)
end

function allowed_url(url):
    return implementation.allowed_url(url)
end

function download(url, path, maximum):
    return implementation.download(url, path, maximum)
end

function download_chunk(chunk):
    return implementation.download_chunk(chunk)
end

function download_progress(url, path, expected):
    return implementation.download_progress(url, path, expected)
end

function verify_signature(work):
    return implementation.verify_signature(work)
end

function verified_manifest(work, current, architecture, allow_downgrade):
    return implementation.verified_manifest(work, current, architecture, allow_downgrade)
end

function verify_archive(path, artifact):
    return implementation.verify_archive(path, artifact)
end

function tar_string(buffer, offset, width):
    return implementation.tar_string(buffer, offset, width)
end

function tar_octal(buffer, offset, width):
    return implementation.tar_octal(buffer, offset, width)
end

function archive_path(name, root):
    return implementation.archive_path(name, root)
end

function tar_entries(buffer, root):
    return implementation.tar_entries(buffer, root)
end

function installer_entry(buffer, entries, root):
    return implementation.installer_entry(buffer, entries, root)
end

function extract_archive(work, artifact):
    return implementation.extract_archive(work, artifact)
end

function options():
    return implementation.options()
end

function execute(current, settings, work, prefix):
    return implementation.execute(current, settings, work, prefix)
end

function main(current):
    return implementation.main(current)
end
