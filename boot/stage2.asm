[org 0]
[bits 16]

%define STACK_SEG        0x9000
%define STACK_TOP_OFF    0xFFFE
%define PROT_STACK_TOP   0x0009F000

%define GDT_BASE         0x0500
%define CODE_SELECTOR    0x08
%define DATA_SELECTOR    0x10

stage2_entry:
    cli

    mov ax, STACK_SEG
    mov ss, ax
    mov sp, STACK_TOP_OFF

    mov ax, cs
    mov ds, ax
    mov es, ax

    cld
    mov si, stage2_real_mode_msg
    call print_string

    ; Copy the GDT template into low memory (0x0000:0x0500)
    mov si, gdt_start
    xor ax, ax
    mov es, ax
    mov di, GDT_BASE
    mov cx, gdt_end - gdt_start
    rep movsb

    ; Load the GDTR with our GDT pointer (base = 0x0000:0x0500)
    lgdt [gdt_descriptor]

    ; Enter protected mode
    cli
    mov eax, cr0
    or eax, 0x1
    mov cr0, eax

    jmp CODE_SELECTOR:protected_mode_entry

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

[bits 32]
protected_mode_entry:
    mov ax, DATA_SELECTOR
    mov ds, ax
    mov es, ax
    mov fs, ax
    mov gs, ax
    mov ss, ax
    mov esp, PROT_STACK_TOP

    mov esi, pmode_message
    mov edi, 0x000B8000
    mov bl, 0x07

.pm_print:
    lodsb
    test al, al
    jz .pm_done
    mov ah, bl
    mov [edi], ax
    add edi, 2
    jmp .pm_print

.pm_done:
    cli
.pm_hang:
    hlt
    jmp .pm_hang

[bits 16]

stage2_real_mode_msg: db "Stage 2: preparing protected mode...", 0x0D, 0x0A, 0
pmode_message:        db "NovaOS is now in 32-bit protected mode.", 0

gdt_descriptor:
    dw gdt_end - gdt_start - 1
    dd GDT_BASE

gdt_start:
    dq 0x0000000000000000          ; Null descriptor
    dq 0x00CF9A000000FFFF          ; Code segment: base 0, limit 4 GiB
    dq 0x00CF92000000FFFF          ; Data segment: base 0, limit 4 GiB
gdt_end:
