/* Rozložení obrazu bare metal riscv64 (RAM od 0x80000000, qemu virt).
   Sekce začínají na stránce kvůli oprávněním stránkování (kód R+X, data
   jen pro čtení R, ostatní RW). Pod hlavním zásobníkem (8 MiB) a pod
   zásobníky pastí hartů je nenamapovaná strážní stránka. Od lsl_image_end
   spravuje paměť runtime (os_baremetal.lsl).
   Překladač tento skript nepoužívá: stejné rozložení vytváří vestavěný
   linker LuxIR (luxir -l -b, src/ld/ld.c), jehož test ho s GNU ld
   porovnává. Při změně rozložení upravit obojí. */
OUTPUT_ARCH(riscv)
ENTRY(_start)
SECTIONS
{
  . = 0x80000000;
  .text : { KEEP(*(.text.start)) *(.text .text.*) }
  . = ALIGN(4096);
  lsl_text_end = .;
  .rodata : { *(.rodata .rodata.* .srodata .srodata.*) }
  . = ALIGN(4096);
  lsl_rodata_end = .;
  .data : { *(.data .data.* .sdata .sdata.*) }
  .bss (NOLOAD) : ALIGN(16) {
    __bss_start = .;
    *(.bss .bss.* .sbss .sbss.* COMMON)
    . = ALIGN(16);
    __bss_end = .;
  }
  /* Zásobníky pastí: 8 hartů po 20 KiB (4 KiB stráž + 16 KiB). */
  .trapstacks (NOLOAD) : ALIGN(4096) {
    lsl_trap_stacks = .;
    . += 8 * 20480;
  }
  .stack (NOLOAD) : ALIGN(4096) {
    lsl_stack_guard = .;
    . += 4096;
    . += 0x800000;
    lsl_stack_top = .;
  }
  lsl_image_end = .;
  /DISCARD/ : { *(.note.GNU-stack) *(.comment) *(.riscv.attributes) *(.eh_frame) }
}
