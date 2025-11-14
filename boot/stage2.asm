[org 0]
[bits 16]

%define STACK_SEG        0x9000
%define STACK_TOP_OFF    0xFFFE
%define PROT_STACK_TOP   0x0009F000

%define STAGE2_LOAD_SEG  0x1000
%assign STAGE2_PHYS_BASE (STAGE2_LOAD_SEG << 4)
%define STAGE2_LINEAR_BASE STAGE2_PHYS_BASE

%define GDT_BASE         0x0500
%define CODE32_SELECTOR  0x08
%define DATA_SELECTOR    0x10
%define CODE64_SELECTOR  0x18

%define LOW_IDENTITY_SIZE 0x00200000
%define KERNEL_PHYS_BASE  0x00200000
%define KERNEL_VIRT_BASE  0xFFFFFFFF80000000
%define KERNEL_MAP_SIZE   0x00200000
%define BOOT_PHYS_BASE    STAGE2_PHYS_BASE
%define BOOT_VIRT_BASE    0xFFFFFFFF80200000
%define BOOT_MAP_SIZE     0x00020000
%define LONG_MODE_STACK   (BOOT_VIRT_BASE + BOOT_MAP_SIZE - 0x10)

%define PAGE_SIZE         0x1000
%define PAGE_FLAG_PRESENT 0x001
%define PAGE_FLAG_RW      0x002
%define PAGE_FLAGS        (PAGE_FLAG_PRESENT | PAGE_FLAG_RW)

%assign KERNEL_PML4_INDEX ((KERNEL_VIRT_BASE >> 39) & 0x1FF)
%assign KERNEL_PDPT_INDEX ((KERNEL_VIRT_BASE >> 30) & 0x1FF)
%assign KERNEL_PD_INDEX   ((KERNEL_VIRT_BASE >> 21) & 0x1FF)
%assign KERNEL_PT_INDEX   ((KERNEL_VIRT_BASE >> 12) & 0x1FF)

%assign BOOT_PML4_INDEX   ((BOOT_VIRT_BASE >> 39) & 0x1FF)
%assign BOOT_PDPT_INDEX   ((BOOT_VIRT_BASE >> 30) & 0x1FF)
%assign BOOT_PD_INDEX     ((BOOT_VIRT_BASE >> 21) & 0x1FF)
%assign BOOT_PT_INDEX     ((BOOT_VIRT_BASE >> 12) & 0x1FF)

%assign IDENTITY_PAGE_COUNT (LOW_IDENTITY_SIZE / PAGE_SIZE)
%assign KERNEL_PAGE_COUNT   (KERNEL_MAP_SIZE / PAGE_SIZE)
%assign BOOT_PAGE_COUNT     (BOOT_MAP_SIZE / PAGE_SIZE)

%define MSR_EFER        0xC0000080
%define EFER_LME        (1 << 8)
%define CR4_PAE         (1 << 5)
%define CR0_PG          0x80000000

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

    jmp CODE32_SELECTOR:protected_mode_entry

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

    call setup_paging

    mov esi, STAGE2_LINEAR_BASE + pmode_message
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
    call enter_long_mode

.pm_hang:
    hlt
    jmp .pm_hang

setup_paging:
    pushad

    ; Clear paging structures
    mov edi, STAGE2_LINEAR_BASE + page_tables_start
    mov ecx, (page_tables_end - page_tables_start) / 4
    xor eax, eax
    rep stosd

    ; PML4 entries
    mov edi, STAGE2_LINEAR_BASE + pml4_table
    mov eax, STAGE2_PHYS_BASE + pdpt_low
    or eax, PAGE_FLAGS
    mov [edi + (0 * 8)], eax
    mov dword [edi + (0 * 8) + 4], 0

    mov eax, STAGE2_PHYS_BASE + pdpt_high
    or eax, PAGE_FLAGS
    mov [edi + (KERNEL_PML4_INDEX * 8)], eax
    mov dword [edi + (KERNEL_PML4_INDEX * 8) + 4], 0
%if KERNEL_PML4_INDEX != BOOT_PML4_INDEX
    mov [edi + (BOOT_PML4_INDEX * 8)], eax
    mov dword [edi + (BOOT_PML4_INDEX * 8) + 4], 0
%endif

    ; PDPT entries
    mov edi, STAGE2_LINEAR_BASE + pdpt_low
    mov eax, STAGE2_PHYS_BASE + pd_low
    or eax, PAGE_FLAGS
    mov [edi + (0 * 8)], eax
    mov dword [edi + (0 * 8) + 4], 0

    mov edi, STAGE2_LINEAR_BASE + pdpt_high
    mov eax, STAGE2_PHYS_BASE + pd_high
    or eax, PAGE_FLAGS
    mov [edi + (KERNEL_PDPT_INDEX * 8)], eax
    mov dword [edi + (KERNEL_PDPT_INDEX * 8) + 4], 0
%if KERNEL_PDPT_INDEX != BOOT_PDPT_INDEX
    mov [edi + (BOOT_PDPT_INDEX * 8)], eax
    mov dword [edi + (BOOT_PDPT_INDEX * 8) + 4], 0
%endif

    ; PD entries
    mov edi, STAGE2_LINEAR_BASE + pd_low
    mov eax, STAGE2_PHYS_BASE + pt_identity
    or eax, PAGE_FLAGS
    mov [edi + (0 * 8)], eax
    mov dword [edi + (0 * 8) + 4], 0

    mov edi, STAGE2_LINEAR_BASE + pd_high
    mov eax, STAGE2_PHYS_BASE + pt_kernel
    or eax, PAGE_FLAGS
    mov [edi + (KERNEL_PD_INDEX * 8)], eax
    mov dword [edi + (KERNEL_PD_INDEX * 8) + 4], 0

    mov eax, STAGE2_PHYS_BASE + pt_boot
    or eax, PAGE_FLAGS
    mov [edi + (BOOT_PD_INDEX * 8)], eax
    mov dword [edi + (BOOT_PD_INDEX * 8) + 4], 0

    ; Identity PT entries
    mov edi, STAGE2_LINEAR_BASE + pt_identity
    mov ecx, IDENTITY_PAGE_COUNT
    xor ebx, ebx
.identity_loop:
    mov eax, ebx
    or eax, PAGE_FLAGS
    mov [edi], eax
    mov dword [edi + 4], 0
    add edi, 8
    add ebx, PAGE_SIZE
    loop .identity_loop

    ; Kernel PT entries
    mov edi, STAGE2_LINEAR_BASE + pt_kernel + (KERNEL_PT_INDEX * 8)
    mov ecx, KERNEL_PAGE_COUNT
    mov ebx, KERNEL_PHYS_BASE
.kernel_loop:
    mov eax, ebx
    or eax, PAGE_FLAGS
    mov [edi], eax
    mov dword [edi + 4], 0
    add edi, 8
    add ebx, PAGE_SIZE
    loop .kernel_loop

    ; Bootloader PT entries
    mov edi, STAGE2_LINEAR_BASE + pt_boot + (BOOT_PT_INDEX * 8)
    mov ecx, BOOT_PAGE_COUNT
    mov ebx, BOOT_PHYS_BASE
.boot_loop:
    mov eax, ebx
    or eax, PAGE_FLAGS
    mov [edi], eax
    mov dword [edi + 4], 0
    add edi, 8
    add ebx, PAGE_SIZE
    loop .boot_loop

    ; Persist CR3 candidate
    mov eax, STAGE2_PHYS_BASE + pml4_table
    mov [paging_context], eax
    mov dword [paging_context + 4], 0

    popad
    ret

enter_long_mode:
    mov eax, [paging_context]
    mov cr3, eax

    mov eax, cr4
    or eax, CR4_PAE
    mov cr4, eax

    mov ecx, MSR_EFER
    rdmsr
    or eax, EFER_LME
    wrmsr

    mov eax, cr0
    or eax, CR0_PG
    mov cr0, eax

    jmp CODE64_SELECTOR:STAGE2_LINEAR_BASE + long_mode_entry

[bits 16]

stage2_real_mode_msg: db "Stage 2: preparing protected mode...", 0x0D, 0x0A, 0
pmode_message:        db "Paging tables ready; entering long mode...", 0

gdt_descriptor:
    dw gdt_end - gdt_start - 1
    dd GDT_BASE

gdt_start:
    dq 0x0000000000000000          ; Null descriptor
    dq 0x00CF9A000000FFFF          ; 32-bit code segment
    dq 0x00CF92000000FFFF          ; Data segment
    dq 0x00AF9A000000FFFF          ; 64-bit code segment
gdt_end:

align 4096
page_tables_start:
pml4_table:  times 512 dq 0
pdpt_low:    times 512 dq 0
pd_low:      times 512 dq 0
pt_identity: times 512 dq 0
pdpt_high:   times 512 dq 0
pd_high:     times 512 dq 0
pt_kernel:   times 512 dq 0
pt_boot:     times 512 dq 0
page_tables_end:

paging_context:
    dq 0

[bits 64]
long_mode_entry:
    mov ax, DATA_SELECTOR
    mov ds, ax
    mov es, ax
    mov fs, ax
    mov gs, ax
    mov ss, ax

    mov rsp, LONG_MODE_STACK

    mov ax, cs
    cmp ax, CODE64_SELECTOR
    jne long_mode_fail

    mov ax, ss
    cmp ax, DATA_SELECTOR
    jne long_mode_fail

    mov rax, rsp
    cmp rax, LONG_MODE_STACK
    jne long_mode_fail

    lea rsi, [rel long_mode_success]
    jmp long_mode_print

long_mode_fail:
    lea rsi, [rel long_mode_error]

long_mode_print:
    mov rdi, 0x00000000000B8000
    mov bl, 0x0A

.lm_print_loop:
    lodsb
    test al, al
    jz .lm_print_done
    mov ah, bl
    mov [rdi], ax
    add rdi, 2
    jmp .lm_print_loop

.lm_print_done:
    cli
.lm_halt:
    hlt
    jmp .lm_halt

long_mode_success: db "NovaOS long mode active (CS=0x18, SS=0x10, stack ok).", 0
long_mode_error:   db "Long mode validation failed!", 0
