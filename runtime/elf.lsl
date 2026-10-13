# lsl: runtime
# Formát ELF nativních knihoven: kontrola hlavičky zkopírovaného obrazu.
# Tabulky sekcí a symbolů čte stdlib (_native_<cíl>.lsl) přes native_u64
# a native_name_equal. Jiný formát (PE, Mach-O) dodá modul se stejnou funkcí.
load _platform as platform

ELF_MAGIC = 1179403647
ELF_TYPE_DYN = 3

# Obraz (alespoň 64 B) je ELF ET_DYN pro stroj cíle.
function native_image_format_valid(image):
    if __lsl_qbe_load32(image) != ELF_MAGIC:
        return 0
    elif __lsl_qbe_load16(image + 16) != ELF_TYPE_DYN:
        return 0
    end
    return __lsl_qbe_load16(image + 18) == platform.ELF_MACHINE
end
