; Simple /bin/init for NovaOS using custom syscalls
; SYS_write=0, SYS_exit=1

BITS 64
DEFAULT REL

section .text
global _start

_start:
    ; write(1, msg, msglen)
    mov rax, 0                ; SYS_write
    mov rdi, 1                ; fd=1 (stdout)
    lea rsi, [rel msg]
    mov rdx, msglen
    syscall

    ; exit(0)
    mov rax, 1                ; SYS_exit
    xor rdi, rdi
    syscall

section .rodata
msg:    db "NovaOS userland: hello from /bin/init", 10
msglen: equ $ - msg


