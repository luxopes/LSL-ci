# lsl: runtime
# Runtime jazyka LSL napsaný v LSL. Překládá ho compiler/pure/lslc_runtime.lsl
# do LuxIR a LuxIR pro každý cíl. Každá funkce je symbol se svým jménem;
# rt_runtime_* volá kód vygenerovaný překladačem (qbe_emit).
#
# Přechod z x86 emitorů: rutiny definované tady nahrazují stejnojmenné x86
# můstky (tools/runtime/build.py). Datové struktury (stav, halda, objekty)
# zůstávají stejné, takže obě části pracují nad stejnými daty.
load os_linux
load core
load sync
load heap
load gc
load strings
load dict
load elf
load ffi_linux
load ffi
load numbers
load processes
load text
load io
