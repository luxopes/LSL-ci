# lsl: runtime
# Nativní knihovny na macOS: obraz ELF (čistý kód s konvencí System V nebo
# AAPCS64, stejný jako na Linuxu) se volá v krátkém dceřiném procesu. macOS
# nemá seccomp a fork po vláknech není bezpečný: rodič spustí sám sebe
# (posix_spawn) s prostředím jen LSL_NATIVE_SANDBOX=1, pošle mu obraz
# a argumenty rourou a dítě vrátí 8 B výsledku. Dítě se před zpracováním
# kódu uzavře do sandboxu (deny default: žádné soubory, síť ani procesy)
# a skončí nejpozději po 2 s. Pád ani zacyklení proces LSL nezasáhne.
load _platform as platform
load _runtime_os as os

IMAGE_LIMIT = 268435456
SANDBOX_FAILURE = 126
HEADER_BYTES = 64
DEADLINE_MILLISECONDS = 2000
# Záznam volání: +0 pid, +8 hlídání limitu.
RECORD_BYTES = 16384
POSIX_SPAWN_CLOEXEC_DEFAULT = 16384
MAC_MAP_PRIVATE = 2
MAC_MAP_ANON = 4096

# Zkopíruje soubor path (String) do paměti pro čtení a zápis. Vrátí adresu
# a do size_out velikost, nebo 0. Poslední složka nesmí být odkaz.
function native_image_load(path, size_out):
    descriptor = os.open(path + 16, platform.O_RDONLY | platform.O_CLOEXEC | platform.O_NOFOLLOW, 0)
    if descriptor < 0:
        return 0
    end
    size = os.lseek(descriptor, 0, platform.SEEK_END)
    if size < 64 or size > IMAGE_LIMIT or os.lseek(descriptor, 0, platform.SEEK_SET) != 0:
        call os.close(descriptor)
        return 0
    end
    image = os.map_anonymous(size, 0)
    if image < 0:
        call os.close(descriptor)
        return 0
    end
    done = 0
    while done < size:
        count = os.read(descriptor, image + done, size - done)
        if count > 0:
            done += count
        elif count != -platform.EINTR:
            call os.close(descriptor)
            call os.unmap(image, size)
            return 0
        end
    end
    call os.close(descriptor)
    __lsl_qbe_store64(size_out, size)
    return image
end

# Rodič kód nespouští, obraz jen zamkne pro čtení (dítě dostane kopii).
function native_image_seal(image, size):
    return os.mprotect(image, size, 1)
end

function native_image_unmap(image, size):
    return os.unmap(image, size)
end

# Spustí code(a1..a6) v dceřiném procesu. Vrátí záznam volání a do
# channel_out čtecí konec roury s výsledkem, nebo -1.
function native_sandbox_start(image, size, code, items, channel_out):
    input = __lsl_qbe_alloc(8)
    output = __lsl_qbe_alloc(8)
    if os.os_pipe(input) < 0:
        return -1
    end
    if os.os_pipe(output) < 0:
        call os.close(__lsl_qbe_s32(__lsl_qbe_load32(input)))
        call os.close(__lsl_qbe_s32(__lsl_qbe_load32(input + 4)))
        return -1
    end
    child_input = __lsl_qbe_s32(__lsl_qbe_load32(input))
    writer = __lsl_qbe_s32(__lsl_qbe_load32(input + 4))
    reader = __lsl_qbe_s32(__lsl_qbe_load32(output))
    child_output = __lsl_qbe_s32(__lsl_qbe_load32(output + 4))
    pid = spawn_child(child_input, child_output)
    call os.close(child_input)
    call os.close(child_output)
    record = 0
    if pid > 0:
        record = os.map_anonymous(RECORD_BYTES, 0)
    end
    watch = 0
    if record > 0:
        watch = os.process_deadline(pid, DEADLINE_MILLISECONDS)
    end
    if watch == 0:
        if pid > 0:
            call os.os_kill(pid)
            call os.os_wait(pid)
        end
        if record > 0:
            call os.unmap(record, RECORD_BYTES)
        end
        call os.close(writer)
        call os.close(reader)
        return -1
    end
    __lsl_qbe_store64(record, pid)
    __lsl_qbe_store64(record + 8, watch)
    # Hlavička: velikost obrazu, posun funkce, šest argumentů; pak obraz.
    header = __lsl_qbe_alloc(64)
    __lsl_qbe_store64(header, size)
    __lsl_qbe_store64(header + 8, code - image)
    index = 0
    while index < 6:
        __lsl_qbe_store64(header + 16 + __lsl_qbe_shl(index, 3), __lsl_qbe_load64(__lsl_qbe_load64(items + __lsl_qbe_shl(index, 3)) + 8))
        index += 1
    end
    if os.os_write_all(writer, header, HEADER_BYTES) == 0:
        call os.os_write_all(writer, image, size)
    end
    call os.close(writer)
    __lsl_qbe_store64(channel_out, reader)
    return record
end

# Tento program se vstupem a výstupem z rour a prostředím jen se značkou
# dítěte (posix_spawn, potomek zdědí jen deskriptory 0-2). pid, nebo -1.
function spawn_child(input, output):
    path = __lsl_qbe_alloc(4104)
    length = os.os_executable_path(path, 4096)
    if length <= 0 or length >= 4096:
        return -1
    end
    __lsl_qbe_store8(path + length, 0)
    argv = __lsl_qbe_alloc(16)
    __lsl_qbe_store64(argv, path)
    __lsl_qbe_store64(argv + 8, 0)
    environment = __lsl_qbe_alloc(16)
    __lsl_qbe_store64(environment, __lsl_address("LSL_NATIVE_SANDBOX=1") + 16)
    __lsl_qbe_store64(environment + 8, 0)
    actions = __lsl_qbe_alloc(8)
    attributes = __lsl_qbe_alloc(8)
    pid = __lsl_qbe_alloc(8)
    __lsl_qbe_store64(pid, 0)
    if os.int32(__lsl_qbe_call1(__lsl_symbol("posix_spawn_file_actions_init"), actions)) != 0:
        return -1
    end
    if os.int32(__lsl_qbe_call1(__lsl_symbol("posix_spawnattr_init"), attributes)) != 0:
        call __lsl_qbe_call1(__lsl_symbol("posix_spawn_file_actions_destroy"), actions)
        return -1
    end
    call __lsl_qbe_call2(__lsl_symbol("posix_spawnattr_setflags"), attributes, POSIX_SPAWN_CLOEXEC_DEFAULT)
    call __lsl_qbe_call3(__lsl_symbol("posix_spawn_file_actions_adddup2"), actions, input, 0)
    call __lsl_qbe_call3(__lsl_symbol("posix_spawn_file_actions_adddup2"), actions, output, 1)
    call __lsl_qbe_call3(__lsl_symbol("posix_spawn_file_actions_adddup2"), actions, output, 2)
    result = os.int32(__lsl_qbe_call6(__lsl_symbol("posix_spawn"), pid, path, actions, attributes, argv, environment))
    call __lsl_qbe_call1(__lsl_symbol("posix_spawn_file_actions_destroy"), actions)
    call __lsl_qbe_call1(__lsl_symbol("posix_spawnattr_destroy"), attributes)
    if result != 0:
        return -1
    end
    return os.int32(__lsl_qbe_load64(pid))
end

# Rodič: přečte 8 B výsledku a počká na dítě. Úspěch jen při celém
# výsledku, kódu 0 a nevypršeném limitu; výsledek do result_out.
function native_sandbox_finish(record, reader, result_out):
    done = 0
    while done < 8:
        count = os.read(reader, result_out + done, 8 - done)
        if count > 0:
            done += count
        elif count != -platform.EINTR:
            break
        end
    end
    call os.close(reader)
    pid = __lsl_qbe_load64(record)
    expired = os.process_deadline_cancel(__lsl_qbe_load64(record + 8))
    code = os.os_wait(pid)
    call os.unmap(record, RECORD_BYTES)
    return done == 8 and not expired and code == 0
end

# Dítě izolovaného volání: prostředí obsahuje LSL_NATIVE_SANDBOX=1 (jinak
# běží program normálně, 0). Uzavře se do sandboxu, přečte hlavičku
# a obraz, zavolá funkci a zapíše výsledek; nevrací se.
function native_child_main():
    if not marker_present():
        return 0
    end
    failure = __lsl_qbe_alloc(8)
    __lsl_qbe_store64(failure, 0)
    profile = __lsl_address("(version 1)(deny default)") + 16
    if os.int32(__lsl_qbe_call3(__lsl_symbol("sandbox_init"), profile, 0, failure)) != 0:
        call os.exit_process(SANDBOX_FAILURE)
    end
    header = __lsl_qbe_alloc(64)
    if not read_exact(header, HEADER_BYTES):
        call os.exit_process(SANDBOX_FAILURE)
    end
    size = __lsl_qbe_load64(header)
    offset = __lsl_qbe_load64(header + 8)
    if size < 64 or size > IMAGE_LIMIT or offset < 0 or offset >= size:
        call os.exit_process(SANDBOX_FAILURE)
    end
    image = os.mmap(0, size, 3, MAC_MAP_PRIVATE | MAC_MAP_ANON, -1, 0)
    if image < 0 or not read_exact(image, size):
        call os.exit_process(SANDBOX_FAILURE)
    end
    if os.mprotect(image, size, 5) != 0:
        call os.exit_process(SANDBOX_FAILURE)
    end
    call __lsl_qbe_call2(__lsl_symbol("sys_icache_invalidate"), image, size)
    result = __lsl_qbe_alloc(8)
    __lsl_qbe_store64(result, __lsl_qbe_call2(__lsl_symbol("lsl_arch_call_native"), image + offset, header + 16))
    if os.os_write_all(1, result, 8) != 0:
        call os.exit_process(SANDBOX_FAILURE)
    end
    call os.exit_process(0)
    return 0
end

# Proměnná LSL_NATIVE_SANDBOX=1 je vyhrazená pro runtime. Rodič dítěti
# předá prostředí jen s ní; systém (wine) může přidat další proměnné.
function marker_present():
    entry_pointer = os.os_environment()
    while __lsl_qbe_load64(entry_pointer) != 0:
        if marker_equal(__lsl_qbe_load64(entry_pointer)):
            return 1
        end
        entry_pointer += 8
    end
    return 0
end

function marker_equal(entry):
    marker = __lsl_address("LSL_NATIVE_SANDBOX=1") + 16
    index = 0
    while __lsl_qbe_load8(marker + index) != 0:
        if __lsl_qbe_load8(entry + index) != __lsl_qbe_load8(marker + index):
            return 0
        end
        index += 1
    end
    return __lsl_qbe_load8(entry + index) == 0
end

function read_exact(buffer, size):
    done = 0
    while done < size:
        count = os.read(0, buffer + done, size - done)
        if count > 0:
            done += count
        elif count != -platform.EINTR:
            return 0
        end
    end
    return 1
end
