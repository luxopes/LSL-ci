# Optional integration with an actual PUBLIC signed release archive.
# Usage: update-release-integration ARCHIVE
load fd
load update
load update_install

function require(condition, message):
    if not condition:
        Error(TestFailure: message)
    end
end

function main():
    work = update_install.private_work("/tmp")
    print "Isolated release integration:", work
    call writefile(work + "/manifest.json", readfile("tests/compiler/fixtures/update-stable.json"))
    call writebytes(work + "/manifest.sig", readbytes("tests/compiler/fixtures/update-stable.sig"))
    manifest = update.verified_manifest(work, "0.7.7", "x86_64", False)
    call writebytes(work + "/release.tar.gz", fd.read_all_limit(arg(1), update.MAX_ARCHIVE))
    installer = update.extract_archive(work, manifest["artifact"])
    prefix = work + "/prefix"
    call update_install.directory(prefix)
    call update_install.bounded(installer, [prefix], 16777216, 120)
    call update_install.health(prefix, "0.7.7", work)
    call writefile(prefix + "/bin/unrelated", "preserve me")
    call writefile(prefix + "/lib/lsl/stdlib/custom_library.lsl", "print 7")
    store = prefix + "/lib/lsl-updates"
    call update_install.directory(store)
    call update_install.directory(store + "/generations")
    handle = update_install.lock(store)
    generation = update_install.private_work(store + "/generations")
    call update_install.install_stage(installer, generation, "0.7.7", work)
    old = update_install.prepare(prefix, prefix + "/bin/lsl", "0.7.7", work)
    call require(old != generation, "migration did not retain old generation")
    call update_install.activate(store, generation, "0.7.7", work)
    call update_install.health(prefix, "0.7.7", work)
    call update_install.rollback(store, work)
    call require(update_install.target(store, "current") == old, "release rollback failed")
    call update_install.health(prefix, "0.7.7", work)
    call require(readfile(prefix + "/bin/unrelated") == "preserve me", "unrelated executable overwritten")
    call require(readfile(prefix + "/lib/lsl/stdlib/custom_library.lsl") == "print 7", "user library overwritten")
    call fd.close(handle)
    print "Signed release extraction, installer, migration, activation, rollback and compiler smoke passed."
    call update_install.cleanup_scratch(work)
end

call main()
