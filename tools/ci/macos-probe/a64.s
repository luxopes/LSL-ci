	.globl _main
	.p2align 2
_main:
	stp x29, x30, [sp, -16]!
	mov x0, 1
	adrp x1, msg@PAGE
	add x1, x1, msg@PAGEOFF
	mov x2, 13
	bl _write
	mov x0, 0
	bl _exit
	.section __TEXT,__cstring
msg:	.asciz "hello macOS\n"
