[org 0]
[bits 16]

%define STACK_TOP 0x9FFF

stage2_entry:
    cli
    xor ax, ax
    mov ds, ax
    mov es, ax
    mov ss, ax
    mov sp, STACK_TOP
    sti

    cld
    mov si, stage2_message
    call print_string

hang:
    hlt
    jmp hang

print_string:
    push ax
    push bx
    push si

.print_next:
    lodsb
    cmp al, 0
    je .done
    mov ah, 0x0E
    mov bh, 0x00
    mov bl, 0x07
    int 0x10
    jmp .print_next

.done:
    pop si
    pop bx
    pop ax
    ret

stage2_message: db "NovaOS stage 2 ready", 0x0D, 0x0A, 0
