	.globl _main
_main:
	push %rbp
	mov $1, %edi
	lea msg(%rip), %rsi
	mov $13, %edx
	call _write
	xor %edi, %edi
	call _exit
	.section __TEXT,__cstring
msg:	.asciz "hello macOS\n"
