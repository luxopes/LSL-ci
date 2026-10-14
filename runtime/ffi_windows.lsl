# lsl: runtime
# Nativní knihovny na Windows: obraz ELF (čistý kód s konvencí System V,
# stejný jako na Linuxu) se volá v krátkém dceřiném procesu. Windows nemá
# fork ani seccomp: rodič spustí sám sebe (CreateProcessW) s prostředím jen
# LSL_NATIVE_SANDBOX=1, pošle mu obraz a argumenty rourou a dítě vrátí 8 B
# výsledku. Dítě běží v job objectu (žádné další procesy, nejvýš 256 MiB,
# ukončení s rodičem, pád bez dialogu) a skončí nejpozději po 2 s. Pád,
# zacyklení ani poškození paměti tak proces LSL nezasáhne; systémová volání
# ale na rozdíl od strict seccomp omezena nejsou.
load _platform as platform
load _runtime_os as os

IMAGE_LIMIT = 268435456
SANDBOX_FAILURE = 126
HEADER_BYTES = 64
DEADLINE_MILLISECONDS = 2000
# Záznam volání (VirtualAlloc): +0 HANDLE procesu, +8 job, +16 hlídání limitu.
RECORD_BYTES = 4096

GENERIC_READ = 2147483648
OPEN_EXISTING = 3
MEM_COMMIT_RESERVE = 12288
MEM_RELEASE = 32768
PAGE_READWRITE = 4
PAGE_EXECUTE_READ = 32
HANDLE_FLAG_INHERIT = 1
STARTF_USESTDHANDLES = 256
CREATE_SUSPENDED = 4
CREATE_UNICODE_ENVIRONMENT = 1024
EXTENDED_STARTUPINFO_PRESENT = 524288
PROC_THREAD_ATTRIBUTE_HANDLE_LIST = 131074
JOB_OBJECT_EXTENDED_LIMIT_INFORMATION = 9
# ACTIVE_PROCESS | PROCESS_MEMORY | DIE_ON_UNHANDLED_EXCEPTION | KILL_ON_JOB_CLOSE
JOB_LIMITS = 9480
INFINITE = 4294967295

# Zkopíruje soubor path (String) do paměti pro čtení a zápis. Vrátí adresu
# a do size_out velikost, nebo 0. Poslední složka nesmí být odkaz.
function native_image_load(path, size_out):
    descriptor = os.open(path + 16, platform.O_RDONLY | platform.O_NOFOLLOW, 0)
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
        if count <= 0:
            call os.close(descriptor)
            call os.unmap(image, size)
            return 0
        end
        done += count
    end
    call os.close(descriptor)
    __lsl_qbe_store64(size_out, size)
    return image
end

# Rodič kód nespouští, obraz jen zamkne pro čtení (dítě dostane kopii).
function native_image_seal(image, size):
    old = __lsl_qbe_alloc(8)
    if os.dword(__lsl_qbe_call4(__lsl_symbol("VirtualProtect"), image, size, 2, old)) == 0:
        return -1
    end
    return 0
end

function native_image_unmap(image, size):
    return os.unmap(image, size)
end

# Roura s jedním děděným koncem: ends +0 čtení, +8 zápis; inherit 0 = čtecí
# konec dědí dítě, 1 = zapisovací. 1, nebo 0.
function child_pipe(ends, inherit):
    if os.dword(__lsl_qbe_call4(__lsl_symbol("CreatePipe"), ends, ends + 8, 0, 65536)) == 0:
        return 0
    end
    return os.dword(__lsl_qbe_call3(__lsl_symbol("SetHandleInformation"), __lsl_qbe_load64(ends + __lsl_qbe_shl(inherit, 3)), HANDLE_FLAG_INHERIT, HANDLE_FLAG_INHERIT)) != 0
end

function close_handle(handle):
    if handle != 0:
        call __lsl_qbe_call1(__lsl_symbol("CloseHandle"), handle)
    end
    return 0
end

# Spustí code(a1..a6) v dceřiném procesu. Vrátí záznam volání a do
# channel_out čtecí konec roury s výsledkem, nebo -1.
function native_sandbox_start(image, size, code, items, channel_out):
    input = __lsl_qbe_alloc(16)
    output = __lsl_qbe_alloc(16)
    __lsl_qbe_zero(input, 16)
    __lsl_qbe_zero(output, 16)
    if not child_pipe(input, 0) or not child_pipe(output, 1):
        call close_pipe_ends(input, output)
        return -1
    end
    record = start_child(__lsl_qbe_load64(input), __lsl_qbe_load64(output + 8))
    # Konce dítěte rodič nepotřebuje.
    call close_handle(__lsl_qbe_load64(input))
    call close_handle(__lsl_qbe_load64(output + 8))
    if record == 0:
        call close_handle(__lsl_qbe_load64(input + 8))
        call close_handle(__lsl_qbe_load64(output))
        return -1
    end
    # Hlavička: velikost obrazu, posun funkce, šest argumentů; pak obraz.
    header = __lsl_qbe_alloc(64)
    __lsl_qbe_store64(header, size)
    __lsl_qbe_store64(header + 8, code - image)
    index = 0
    while index < 6:
        __lsl_qbe_store64(header + 16 + __lsl_qbe_shl(index, 3), __lsl_qbe_load64(__lsl_qbe_load64(items + __lsl_qbe_shl(index, 3)) + 8))
        index += 1
    end
    writer = __lsl_qbe_load64(input + 8)
    sent = os.os_write_all(writer, header, HEADER_BYTES) == 0 and os.os_write_all(writer, image, size) == 0
    call close_handle(writer)
    __lsl_qbe_store64(channel_out, __lsl_qbe_load64(output))
    return record
end

function close_pipe_ends(input, output):
    call close_handle(__lsl_qbe_load64(input))
    call close_handle(__lsl_qbe_load64(input + 8))
    call close_handle(__lsl_qbe_load64(output))
    call close_handle(__lsl_qbe_load64(output + 8))
    return 0
end

# Dítě: tento program, pozastavený, se vstupem a výstupem z rour, v job
# objectu; pak se spustí a hlídá ho limit 2 s. Záznam volání, nebo 0.
function start_child(reader, writer):
    record = os.map_anonymous(RECORD_BYTES, 0)
    if record < 0:
        return 0
    end
    path = __lsl_qbe_alloc(65536)
    if os.dword(__lsl_qbe_call3(__lsl_symbol("GetModuleFileNameW"), 0, path, 32768)) == 0:
        call os.unmap(record, RECORD_BYTES)
        return 0
    end
    # Příkazová řádka "x" (bez argumentů) a prostředí jen se značkou dítěte.
    line = __lsl_qbe_alloc(8)
    __lsl_qbe_store64(line, 120)
    environment = __lsl_qbe_alloc(64)
    __lsl_qbe_zero(environment, 64)
    marker = __lsl_address("LSL_NATIVE_SANDBOX=1") + 16
    index = 0
    while __lsl_qbe_load8(marker + index) != 0:
        __lsl_qbe_store16(environment + __lsl_qbe_shl(index, 1), __lsl_qbe_load8(marker + index))
        index += 1
    end
    handles = __lsl_qbe_alloc(16)
    __lsl_qbe_store64(handles, reader)
    __lsl_qbe_store64(handles + 8, writer)
    attributes = __lsl_qbe_alloc(256)
    size = __lsl_qbe_alloc(8)
    __lsl_qbe_store64(size, 256)
    if os.dword(__lsl_qbe_call4(__lsl_symbol("InitializeProcThreadAttributeList"), attributes, 1, 0, size)) == 0:
        call os.unmap(record, RECORD_BYTES)
        return 0
    end
    call __lsl_qbe_call7(__lsl_symbol("UpdateProcThreadAttribute"), attributes, 0, PROC_THREAD_ATTRIBUTE_HANDLE_LIST, handles, 16, 0, 0)
    startup = __lsl_qbe_alloc(112)
    __lsl_qbe_zero(startup, 112)
    __lsl_qbe_store32(startup, 112)
    __lsl_qbe_store32(startup + 60, STARTF_USESTDHANDLES)
    __lsl_qbe_store64(startup + 80, reader)
    __lsl_qbe_store64(startup + 88, writer)
    __lsl_qbe_store64(startup + 96, writer)
    __lsl_qbe_store64(startup + 104, attributes)
    information = __lsl_qbe_alloc(24)
    __lsl_qbe_zero(information, 24)
    started = os.dword(__lsl_qbe_call10(__lsl_symbol("CreateProcessW"), path, line, 0, 0, 1, CREATE_SUSPENDED | CREATE_UNICODE_ENVIRONMENT | EXTENDED_STARTUPINFO_PRESENT, environment, 0, startup, information))
    call __lsl_qbe_call1(__lsl_symbol("DeleteProcThreadAttributeList"), attributes)
    if started == 0:
        call os.unmap(record, RECORD_BYTES)
        return 0
    end
    process = __lsl_qbe_load64(information)
    thread = __lsl_qbe_load64(information + 8)
    job = __lsl_qbe_call2(__lsl_symbol("CreateJobObjectW"), 0, 0)
    limits = __lsl_qbe_alloc(144)
    __lsl_qbe_zero(limits, 128)
    __lsl_qbe_zero(limits + 128, 16)
    __lsl_qbe_store32(limits + 16, JOB_LIMITS)
    __lsl_qbe_store32(limits + 40, 1)
    __lsl_qbe_store64(limits + 112, IMAGE_LIMIT)
    contained = job != 0 and os.dword(__lsl_qbe_call4(__lsl_symbol("SetInformationJobObject"), job, JOB_OBJECT_EXTENDED_LIMIT_INFORMATION, limits, 144)) != 0 and os.dword(__lsl_qbe_call2(__lsl_symbol("AssignProcessToJobObject"), job, process)) != 0
    watch = 0
    if contained:
        watch = os.process_deadline(process, DEADLINE_MILLISECONDS)
    end
    if watch == 0:
        call __lsl_qbe_call2(__lsl_symbol("TerminateProcess"), process, SANDBOX_FAILURE)
        call close_handle(thread)
        call close_handle(process)
        call close_handle(job)
        call os.unmap(record, RECORD_BYTES)
        return 0
    end
    call __lsl_qbe_call1(__lsl_symbol("ResumeThread"), thread)
    call close_handle(thread)
    __lsl_qbe_store64(record, process)
    __lsl_qbe_store64(record + 8, job)
    __lsl_qbe_store64(record + 16, watch)
    return record
end

# Rodič: přečte 8 B výsledku a počká na dítě. Úspěch jen při celém
# výsledku, kódu 0 a nevypršeném limitu; výsledek do result_out.
function native_sandbox_finish(record, reader, result_out):
    done = 0
    while done < 8:
        count = os.read(reader, result_out + done, 8 - done)
        if count <= 0:
            break
        end
        done += count
    end
    call close_handle(reader)
    process = __lsl_qbe_load64(record)
    expired = os.process_deadline_cancel(__lsl_qbe_load64(record + 16))
    call __lsl_qbe_call2(__lsl_symbol("WaitForSingleObject"), process, INFINITE)
    status = __lsl_qbe_alloc(8)
    __lsl_qbe_store64(status, 1)
    call __lsl_qbe_call2(__lsl_symbol("GetExitCodeProcess"), process, status)
    call close_handle(process)
    call close_handle(__lsl_qbe_load64(record + 8))
    call os.unmap(record, RECORD_BYTES)
    return done == 8 and not expired and os.dword(__lsl_qbe_load64(status)) == 0
end

# Dítě izolovaného volání: prostředí obsahuje LSL_NATIVE_SANDBOX=1 (jinak
# běží program normálně, 0). Přečte hlavičku a obraz, zavolá funkci
# a zapíše výsledek; nevrací se.
function native_child_main():
    if not marker_present():
        return 0
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
    image = __lsl_qbe_call4(__lsl_symbol("VirtualAlloc"), 0, size, MEM_COMMIT_RESERVE, PAGE_READWRITE)
    if image == 0 or not read_exact(image, size):
        call os.exit_process(SANDBOX_FAILURE)
    end
    old = __lsl_qbe_alloc(8)
    if os.dword(__lsl_qbe_call4(__lsl_symbol("VirtualProtect"), image, size, PAGE_EXECUTE_READ, old)) == 0:
        call os.exit_process(SANDBOX_FAILURE)
    end
    call __lsl_qbe_call3(__lsl_symbol("FlushInstructionCache"), __lsl_qbe_call0(__lsl_symbol("GetCurrentProcess")), image, size)
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
        if count <= 0:
            return 0
        end
        done += count
    end
    return 1
end
