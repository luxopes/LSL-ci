/* Rozložení obrazu bare metal riscv64 (deska qemu virt: RAM od 0x80000000).
   Za obrazem 8 MiB zásobníku a 16 KiB zásobníku pasti; od lsl_image_end
   spravuje paměť runtime (os_baremetal.lsl). */
OUTPUT_ARCH(riscv)
ENTRY(_start)
SECTIONS
{
  . = 0x80000000;
  .text : { KEEP(*(.text.start)) *(.text .text.*) }
  .rodata : ALIGN(16) { *(.rodata .rodata.* .srodata .srodata.*) }
  .data : ALIGN(16) { *(.data .data.* .sdata .sdata.*) }
  .bss (NOLOAD) : ALIGN(16) {
    __bss_start = .;
    *(.bss .bss.* .sbss .sbss.* COMMON)
    . = ALIGN(16);
    __bss_end = .;
  }
  .stack (NOLOAD) : ALIGN(4096) {
    . += 0x4000;
    lsl_trap_stack_top = .;
    . += 0x800000;
    lsl_stack_top = .;
  }
  lsl_image_end = .;
  /DISCARD/ : { *(.note.GNU-stack) *(.comment) *(.riscv.attributes) *(.eh_frame) }
}
