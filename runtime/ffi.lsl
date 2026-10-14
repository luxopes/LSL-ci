# lsl: runtime
# Nativní knihovny (stdlib native): omezené samostatné obrazy bez relokací
# a externích symbolů, volané izolovaně. NativeLibrary: +0 tag 11, +8 adresa
# kopie obrazu (0 = zavřená), +16 velikost. NativeFunction: +0 tag 12,
# +8 adresa kódu, +16 NativeLibrary (drží knihovnu živou pro GC).
# Formát obrazu kontroluje elf.lsl, načtení a izolaci volání vrstva OS
# ffi_linux.lsl. Mapování chrání zámek stavu +88 proti souběžnému close.
load core
load sync
load elf
load _runtime_ffi as host

TAG_LIST = 2
TAG_NATIVE_LIBRARY = 11
TAG_NATIVE_FUNCTION = 12
NATIVE_ARGUMENTS = 6
EINVAL = 22

# Kontrola handle jako přímé volání (ne vložená do každé rutiny).
function library_valid(library):
    return __lsl_qbe_call1(__lsl_symbol("rt_runtime_native_library_valid"), library)
end

# Ověří neprůhledné handly přes registr živých objektů dřív, než se čtou:
# vestavěné funkce lze volat přímo a špatná hodnota nesmí vést ke čtení
# libovolné paměti.
function rt_runtime_native_library_valid(library):
    if not core.rt_runtime_is_heap_object(library):
        return 0
    elif __lsl_qbe_load64(library) != TAG_NATIVE_LIBRARY or __lsl_qbe_load64(library + 8) == 0:
        return 0
    end
    return __lsl_qbe_load64(library + 16) >= 64
end

function rt_runtime_native_string_valid(text):
    if not core.rt_runtime_is_heap_object(text):
        return 0
    elif __lsl_qbe_load64(text) != core.TAG_STRING:
        return 0
    end
    return __lsl_qbe_load64(text + 8) <= 255
end

# Adresa funkce leží uvnitř stále otevřeného obrazu její knihovny.
function rt_runtime_native_function_valid(target):
    if not core.rt_runtime_is_heap_object(target):
        return 0
    elif __lsl_qbe_load64(target) != TAG_NATIVE_FUNCTION:
        return 0
    end
    library = __lsl_qbe_load64(target + 16)
    if not library_valid(library):
        return 0
    end
    address = __lsl_qbe_load64(target + 8)
    image = __lsl_qbe_load64(library + 8)
    if __lsl_qbe_ult(address, image):
        return 0
    end
    return __lsl_qbe_ult(address, image + __lsl_qbe_load64(library + 16))
end

# Seznam právě šesti zabalených Int.
function rt_runtime_native_arguments_valid(arguments):
    if not core.rt_runtime_is_heap_object(arguments):
        return 0
    elif __lsl_qbe_load64(arguments) != TAG_LIST or __lsl_qbe_load64(arguments + 8) != NATIVE_ARGUMENTS:
        return 0
    end
    items = __lsl_qbe_load64(arguments + 24)
    index = 0
    while index < NATIVE_ARGUMENTS:
        item = __lsl_qbe_load64(items + __lsl_qbe_shl(index, 3))
        if not core.rt_runtime_is_heap_object(item):
            return 0
        elif __lsl_qbe_load64(item) != core.TAG_INT:
            return 0
        end
        index += 1
    end
    return 1
end

# Zkopíruje obraz do paměti, ověří formát a zamkne ho jen pro čtení
# a spuštění. Vrátí NativeLibrary, nebo 0 (None) bez chyby.
function rt_runtime_native_open(path):
    if not __lsl_qbe_call1(__lsl_symbol("rt_runtime_path_valid"), path):
        return 0
    end
    size_out = __lsl_qbe_alloc(8)
    image = host.native_image_load(path, size_out)
    if image == 0:
        return 0
    end
    size = __lsl_qbe_load64(size_out)
    if not elf.native_image_format_valid(image) or host.native_image_seal(image, size) != 0:
        call host.native_image_unmap(image, size)
        return 0
    end
    library = __lsl_qbe_call1(__lsl_symbol("rt_runtime_alloc"), 24)
    __lsl_qbe_store64(library, TAG_NATIVE_LIBRARY)
    __lsl_qbe_store64(library + 8, image)
    __lsl_qbe_store64(library + 16, size)
    return library
end

# Velikost otevřeného obrazu, 0 pro zavřený nebo neplatný.
function rt_runtime_native_size(library):
    call sync.rt_runtime_native_lock()
    size = 0
    # Vložená kontrola: native_size volá stdlib před každým hledáním symbolu.
    if rt_runtime_native_library_valid(library):
        size = __lsl_qbe_load64(library + 16)
    end
    call sync.rt_runtime_native_unlock()
    return size
end

# Slovo obrazu na posunu offset; záporný nebo přesahující posun dá 0, takže
# poškozená tabulka sekcí skončí NativeError ve stdlib, ne SIGSEGV/SIGBUS.
function rt_runtime_native_u64(library, offset):
    call sync.rt_runtime_native_lock()
    value = 0
    if library_valid(library) and offset >= 0:
        size = __lsl_qbe_load64(library + 16)
        if size >= 8 and offset <= size - 8:
            value = __lsl_qbe_load64(__lsl_qbe_load64(library + 8) + offset)
        end
    end
    call sync.rt_runtime_native_unlock()
    return value
end

# Jméno v obrazu na posunu offset je name zakončené NUL; jméno i NUL se
# musí do obrazu vejít dřív, než se porovná jediný bajt.
function rt_runtime_native_name_equal(library, offset, name):
    call sync.rt_runtime_native_lock()
    equal = native_name_matches(library, offset, name)
    call sync.rt_runtime_native_unlock()
    return equal
end

function native_name_matches(library, offset, name):
    if not library_valid(library) or not rt_runtime_native_string_valid(name):
        return 0
    elif offset < 0:
        return 0
    end
    size = __lsl_qbe_load64(library + 16)
    length = __lsl_qbe_load64(name + 8)
    if offset >= size or length >= size - offset:
        return 0
    end
    stored = __lsl_qbe_load64(library + 8) + offset
    wanted = name + 16
    index = 0
    while index < length:
        if __lsl_qbe_load8(stored + index) != __lsl_qbe_load8(wanted + index):
            return 0
        end
        index += 1
    end
    return __lsl_qbe_load8(stored + length) == 0
end

# NativeFunction pro kód na posunu offset obrazu, nebo 0 (None).
function rt_runtime_native_function(library, offset):
    call sync.rt_runtime_native_lock()
    if not library_valid(library) or offset < 0 or offset >= __lsl_qbe_load64(library + 16):
        call sync.rt_runtime_native_unlock()
        return 0
    end
    address = __lsl_qbe_load64(library + 8) + offset
    call sync.rt_runtime_native_unlock()
    target = __lsl_qbe_call1(__lsl_symbol("rt_runtime_alloc"), 24)
    __lsl_qbe_store64(target, TAG_NATIVE_FUNCTION)
    __lsl_qbe_store64(target + 8, address)
    __lsl_qbe_store64(target + 16, library)
    return target
end

# Zavolá nativní kód s šesti Int argumenty izolovaně (host.native_sandbox_*).
# Rodič dostane jen jeden Int, takže poškození paměti, SIGSEGV ani nekonečná
# smyčka nepoškodí proces LSL. Zámek drží kontrolu mapování až do vzniku
# procesu: dítě má pak vlastní kopii kódu a close může pokračovat.
function rt_runtime_native_call(target, arguments):
    call __lsl_qbe_call0(__lsl_symbol("rt_runtime_stdio_direct"))
    call sync.rt_runtime_native_lock()
    if not rt_runtime_native_function_valid(target):
        call sync.rt_runtime_native_unlock()
        call __lsl_qbe_call1(__lsl_symbol("qbe_error_set"), "NativeError: native library is closed")
        return 0
    elif not rt_runtime_native_arguments_valid(arguments):
        call sync.rt_runtime_native_unlock()
        call __lsl_qbe_call1(__lsl_symbol("qbe_error_set"), "NativeError: native call requires exactly six Int arguments")
        return 0
    end
    channel = __lsl_qbe_alloc(8)
    result = __lsl_qbe_alloc(8)
    library = __lsl_qbe_load64(target + 16)
    pid = host.native_sandbox_start(__lsl_qbe_load64(library + 8), __lsl_qbe_load64(library + 16), __lsl_qbe_load64(target + 8), __lsl_qbe_load64(arguments + 24), channel)
    call sync.rt_runtime_native_unlock()
    if pid < 0 or not host.native_sandbox_finish(pid, __lsl_qbe_load64(channel), result):
        call __lsl_qbe_call1(__lsl_symbol("qbe_error_set"), "NativeError: isolated native call failed or timed out")
        return 0
    end
    return __lsl_qbe_load64(result)
end

# Odmapuje obraz; 0, záporné errno munmap, nebo -EINVAL pro neplatný handle.
function rt_runtime_native_close(library):
    call sync.rt_runtime_native_lock()
    result = -EINVAL
    if library_valid(library):
        result = host.native_image_unmap(__lsl_qbe_load64(library + 8), __lsl_qbe_load64(library + 16))
        if result == 0:
            __lsl_qbe_store64(library + 8, 0)
            __lsl_qbe_store64(library + 16, 0)
        end
    end
    call sync.rt_runtime_native_unlock()
    return result
end
