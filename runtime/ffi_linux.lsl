# lsl: runtime
# Nativní knihovny na Linuxu: kopie souboru v anonymním mapování a volání
# v krátkém procesu se strict seccomp. Obecná část je v ffi.lsl; jiný
# systém dodá stejné funkce (native_image_*, native_sandbox_*).
load _platform as platform
load os_linux as os

# Obraz má nejvýš 256 MiB: omezí prostředky a pozdější změna souboru už
# nezmění kód, který prošel kontrolou.
IMAGE_LIMIT = 268435456
SANDBOX_FAILURE = 126

# Zkopíruje soubor path (String) do zapisovatelného anonymního mapování.
# Vrátí jeho adresu a do size_out velikost, nebo 0. Poslední složka cesty
# nesmí být symlink (O_NOFOLLOW), aby se soubor nedal podvrhnout.
function native_image_load(path, size_out):
    descriptor = os.openat(platform.AT_FDCWD, path + 16, platform.O_RDONLY | platform.O_CLOEXEC | platform.O_NOFOLLOW, 0)
    if descriptor < 0:
        return 0
    end
    size = os.lseek(descriptor, 0, platform.SEEK_END)
    if size < 64 or size > IMAGE_LIMIT:
        call os.close(descriptor)
        return 0
    end
    image = os.mmap(0, size, platform.PROT_READ | platform.PROT_WRITE, platform.MAP_PRIVATE | platform.MAP_ANONYMOUS, -1, 0)
    if image < 0:
        call os.close(descriptor)
        return 0
    end
    # Celý soubor od začátku; opakuje se jen EINTR, krátké čtení (soubor
    # mezitím zkrácený) obraz odmítne.
    if os.lseek(descriptor, 0, platform.SEEK_SET) != 0:
        call os.close(descriptor)
        call os.munmap(image, size)
        return 0
    end
    done = 0
    while done < size:
        count = os.read(descriptor, image + done, size - done)
        if count > 0:
            done += count
        elif count != -platform.EINTR:
            call os.close(descriptor)
            call os.munmap(image, size)
            return 0
        end
    end
    call os.close(descriptor)
    __lsl_qbe_store64(size_out, size)
    return image
end

# W^X: zapisovatelný jen během kopie, pak po celou dobu jen čtení a spuštění.
function native_image_seal(image, size):
    return os.mprotect(image, size, platform.PROT_READ | platform.PROT_EXEC)
end

function native_image_unmap(image, size):
    return os.munmap(image, size)
end

# Spustí code(a1..a6) v novém procesu; argumenty jsou položky items
# (zabalené Int). Rodiči vrátí pid a do channel_out čtecí konec roury, při
# chybě -1. Dítě se nevrací: do roury zapíše 8 B výsledku a skončí.
function native_sandbox_start(code, items, channel_out):
    fds = __lsl_qbe_alloc(8)
    if os.pipe2(fds, platform.O_CLOEXEC) < 0:
        return -1
    end
    reader = __lsl_qbe_load32(fds)
    writer = __lsl_qbe_load32(fds + 4)
    pid = os.fork()
    if pid < 0:
        call os.close(writer)
        call os.close(reader)
        return -1
    elif pid == 0:
        call native_sandbox_child(code, items, reader, writer)
    end
    call os.close(writer)
    __lsl_qbe_store64(channel_out, reader)
    return pid
end

# Dítě: ponechá jen deskriptor 3, nastaví budík a vstoupí do strict seccomp.
# Nativní funkce smí počítat a vrátit hodnotu, ale nesmí otevírat soubory,
# mapovat paměť, spouštět procesy, posílat signály ani komunikovat po síti.
function native_sandbox_child(code, items, reader, writer):
    call os.close(reader)
    if writer != 3:
        if os.dup3(writer, 3, platform.O_CLOEXEC) < 0:
            call os.exit_thread(SANDBOX_FAILURE)
        end
        call os.close(writer)
    end
    if os.close_range(4, 4294967295, 0) < 0:
        call os.exit_thread(SANDBOX_FAILURE)
    end
    call os.close(0)
    call os.close(1)
    call os.close(2)
    call os.alarm(2)
    if os.prctl(platform.PR_SET_NO_NEW_PRIVS, 1) != 0:
        call os.exit_thread(SANDBOX_FAILURE)
    end
    if os.prctl(platform.PR_SET_SECCOMP, platform.SECCOMP_MODE_STRICT) != 0:
        call os.exit_thread(SANDBOX_FAILURE)
    end
    result = __lsl_qbe_alloc(8)
    __lsl_qbe_store64(result, __lsl_qbe_call6(code, __lsl_qbe_load64(__lsl_qbe_load64(items) + 8), __lsl_qbe_load64(__lsl_qbe_load64(items + 8) + 8), __lsl_qbe_load64(__lsl_qbe_load64(items + 16) + 8), __lsl_qbe_load64(__lsl_qbe_load64(items + 24) + 8), __lsl_qbe_load64(__lsl_qbe_load64(items + 32) + 8), __lsl_qbe_load64(__lsl_qbe_load64(items + 40) + 8)))
    while True:
        written = os.write(3, result, 8)
        if written != -platform.EINTR:
            if written != 8:
                call os.exit_thread(SANDBOX_FAILURE)
            end
            call os.exit_thread(0)
        end
    end
    return 0
end

# Rodič: přečte 8 B výsledku a počká na dítě (budík zaručí konec do 2 s).
# Úspěch jen při celém výsledku a návratovém kódu 0; výsledek do result_out.
function native_sandbox_finish(pid, reader, result_out):
    count = os.read(reader, result_out, 8)
    while count == -platform.EINTR:
        count = os.read(reader, result_out, 8)
    end
    call os.close(reader)
    status = __lsl_qbe_alloc(8)
    __lsl_qbe_store64(status, 0)
    waited = os.wait4(pid, status, 0)
    while waited == -platform.EINTR:
        waited = os.wait4(pid, status, 0)
    end
    if waited < 0 or count != 8:
        return 0
    end
    code = __lsl_qbe_load32(status)
    # Ukončení signálem (SIGSEGV, SIGALRM, SIGKILL od seccomp) nebo kód != 0.
    if code & 127 != 0 or __lsl_qbe_lshr(code, 8) & 255 != 0:
        return 0
    end
    return 1
end
