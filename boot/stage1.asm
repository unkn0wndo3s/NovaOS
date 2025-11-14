[org 0]
[bits 16]

%define BOOT_SEG         0x07C0
%define RELOC_SEG        0x0600
%define STACK_TOP        0x7C00
%define STAGE2_LOAD_SEG  0x1000
%define STAGE2_LOAD_OFF  0x0000

%include "stage2.inc"
%ifndef STAGE2_SECTORS
    %define STAGE2_SECTORS 1
%endif

start:
    cli
    xor ax, ax
    mov ss, ax
    mov sp, STACK_TOP
    mov ax, BOOT_SEG
    mov ds, ax
    mov es, ax
    sti

    cld
    xor si, si
    xor di, di
    mov cx, boot_end - start
    add cx, 1
    shr cx, 1
    mov ax, RELOC_SEG
    mov es, ax
    rep movsw

    mov ax, RELOC_SEG
    mov ds, ax
    mov es, ax

    push ax
    push boot_main
    retf

boot_main:
    cli
    xor ax, ax
    mov ss, ax
    mov sp, STACK_TOP
    sti

    mov ax, RELOC_SEG
    mov ds, ax
    mov es, ax

    mov [boot_drive], dl

    call load_stage2
    jmp STAGE2_LOAD_SEG:STAGE2_LOAD_OFF

load_stage2:
    push ax
    push bx
    push dx
    push si

    mov word [dap_sector_count], STAGE2_SECTORS
    mov word [dap_buffer_offset], STAGE2_LOAD_OFF
    mov word [dap_buffer_segment], STAGE2_LOAD_SEG

    mov dl, [boot_drive]
    mov si, dap
    mov ah, 0x42
    int 0x13
    jc disk_error

    pop si
    pop dx
    pop bx
    pop ax
    ret

disk_error:
    mov si, disk_error_msg
    call print_string

hang:
    cli
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

boot_drive:         db 0

dap:
    db 0x10
    db 0x00
 dap_sector_count:   dw 0
 dap_buffer_offset:  dw 0
 dap_buffer_segment: dw 0
 dap_lba:            dq 1

disk_error_msg: db "Disk read error!", 0x0D, 0x0A, 0

boot_end:
    times 510 - ($ - $$) db 0
    dw 0xAA55
