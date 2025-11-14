[org 0]
[bits 16]

%include "firmware.inc"

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
%define UEFI_UTF16_BUFFER_LEN 256
%define BIOS_E820_ENTRY_SIZE    24

%define ACPI_RSDP_MIN_LEN     20
%define ACPI_RSDP_COPY_LEN    36
%define ACPI_FLAG_FOUND       NOVA_ACPI_FLAG_FOUND
%define ACPI_FLAG_HAS_XSDT    NOVA_ACPI_FLAG_HAS_XSDT
%define ACPI_FLAG_FROM_UEFI   NOVA_ACPI_FLAG_FROM_UEFI
%define ACPI_FLAG_HAS_MADT    NOVA_ACPI_FLAG_HAS_MADT
%define ACPI_FLAG_CPU_LIMIT   NOVA_ACPI_FLAG_CPU_LIMIT

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

%define ACPI_SIG_MADT   0x5444414D    ; 'MADT'
%define ACPI_SIG_APIC   ACPI_SIG_MADT
%define ACPI_TABLE_BUFFER_SIZE 4096
%define CPU_ENTRY_SIZE  16
%define ERROR_VECTOR_COUNT 7

%define STAGE2_ABS(addr) ((addr) + STAGE2_LINEAR_BASE)
%define PROT_STACK_PTR   (PROT_STACK_TOP - STAGE2_LINEAR_BASE)

%define BOOTINFO_SIGNATURE 0x42494E46 ; 'BINF'
%define BOOTINFO_FLAG_SMBIOS   (1 << 0)
%define BOOTINFO_FLAG_CPU_BRAND (1 << 1)

%macro GDT_ENTRY 4
    dw (%1 & 0xFFFF)
    dw (%2 & 0xFFFF)
    db ((%2 >> 16) & 0xFF)
    db %3
    db (((%1 >> 16) & 0x0F) | ((%4 & 0x0F) << 4))
    db ((%2 >> 24) & 0xFF)
%endmacro

stage2_entry:
    cli

    mov ax, STACK_SEG
    mov ss, ax
    mov sp, STACK_TOP_OFF

    mov ax, cs
    mov ds, ax
    mov es, ax

    cld
    call firmware_init_rm
    call memmap_reset_raw
    call memmap_collect_rm
    mov si, stage2_real_mode_msg
    call fw_console_write_rm

    cli
    mov al, 0x11
    out 0x20, al
    out 0xA0, al
    mov al, 0x20
    out 0x21, al
    mov al, 0x28
    out 0xA1, al
    mov al, 0x04
    out 0x21, al
    mov al, 0x02
    out 0xA1, al
    mov al, 0x01
    out 0x21, al
    out 0xA1, al
    mov al, 0xFF
    out 0x21, al
    out 0xA1, al

    in al, 0x70
    or al, 0x80
    out 0x70, al

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

    jmp dword CODE32_SELECTOR:protected_mode_entry

firmware_init_rm:
    mov byte [firmware_kind], FIRMWARE_KIND_BIOS
    mov [firmware_boot_drive], dl
    ret

fw_console_write_rm:
    cmp byte [firmware_kind], FIRMWARE_KIND_BIOS
    je bios_console_write_rm
    cmp byte [firmware_kind], FIRMWARE_KIND_UEFI
    je uefi_console_write_rm_stub
    jmp bios_console_write_rm

uefi_console_write_rm_stub:
    ; UEFI path never runs in real mode; fall back to BIOS routines so higher
    ; levels still get diagnostic output.
    jmp bios_console_write_rm

bios_console_write_rm:
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

memmap_reset_raw:
    mov word [bios_memmap_raw_count], 0
    mov dword [memmap_truncated_flag], 0
    ret

memmap_collect_rm:
    cmp byte [firmware_kind], FIRMWARE_KIND_BIOS
    je bios_collect_e820
    ret

bios_collect_e820:
    push ax
    push bx
    push cx
    push dx
    push si
    push di
    push bp

    xor ebx, ebx

.e820_loop:
    mov ax, cs
    mov es, ax
    mov di, bios_e820_temp
    mov eax, 0xE820
    mov edx, 0x534D4150
    xor ecx, ecx
    mov cx, BIOS_E820_ENTRY_SIZE
    int 0x15
    jc .done
    cmp eax, 0x534D4150
    jne .done

    call bios_store_e820_entry

    cmp ebx, 0
    jne .e820_loop

.done:
    pop bp
    pop di
    pop si
    pop dx
    pop cx
    pop bx
    pop ax
    ret

bios_store_e820_entry:
    push ax
    push bx
    push cx
    push dx
    push si
    push di

    mov ax, [bios_memmap_raw_count]
    cmp ax, NOVA_MEM_MAX_ENTRIES
    jae .overflow

    mov bx, BIOS_E820_ENTRY_SIZE
    mul bx
    mov si, bios_e820_temp
    mov di, bios_memmap_raw_entries
    add di, ax
    mov cx, BIOS_E820_ENTRY_SIZE / 2
    rep movsw

    inc word [bios_memmap_raw_count]
    jmp .done

.overflow:
    mov dword [memmap_truncated_flag], 1

.done:
    pop di
    pop si
    pop dx
    pop cx
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
    mov esp, PROT_STACK_PTR

    call init_idt
    call bootinfo_init
    call bootinfo_collect_cpu
    call setup_paging
    call memmap_build_normalized
    call acpi_collect_tables
    call smp_collect_cpu_info
    call bootinfo_collect_smbios
    call bootinfo_finalize

    mov esi, pmode_message
    call fw_console_write_pm

    call enter_long_mode

.pm_hang:
    hlt
    jmp .pm_hang

setup_paging:
    pushad

    ; Clear paging structures
    mov edi, page_tables_start
    mov ecx, (page_tables_end - page_tables_start) / 4
    xor eax, eax
    rep stosd

    ; PML4 entries
    mov edi, pml4_table
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
    mov edi, pdpt_low
    mov eax, STAGE2_PHYS_BASE + pd_low
    or eax, PAGE_FLAGS
    mov [edi + (0 * 8)], eax
    mov dword [edi + (0 * 8) + 4], 0

    mov edi, pdpt_high
    mov eax, STAGE2_PHYS_BASE + pd_high
    or eax, PAGE_FLAGS
    mov [edi + (KERNEL_PDPT_INDEX * 8)], eax
    mov dword [edi + (KERNEL_PDPT_INDEX * 8) + 4], 0
%if KERNEL_PDPT_INDEX != BOOT_PDPT_INDEX
    mov [edi + (BOOT_PDPT_INDEX * 8)], eax
    mov dword [edi + (BOOT_PDPT_INDEX * 8) + 4], 0
%endif

    ; PD entries
    mov edi, pd_low
    mov eax, STAGE2_PHYS_BASE + pt_identity
    or eax, PAGE_FLAGS
    mov [edi + (0 * 8)], eax
    mov dword [edi + (0 * 8) + 4], 0

    mov edi, pd_high
    mov eax, STAGE2_PHYS_BASE + pt_kernel
    or eax, PAGE_FLAGS
    mov [edi + (KERNEL_PD_INDEX * 8)], eax
    mov dword [edi + (KERNEL_PD_INDEX * 8) + 4], 0

    mov eax, STAGE2_PHYS_BASE + pt_boot
    or eax, PAGE_FLAGS
    mov [edi + (BOOT_PD_INDEX * 8)], eax
    mov dword [edi + (BOOT_PD_INDEX * 8) + 4], 0

    ; Identity PT entries
    mov edi, pt_identity
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
    mov edi, pt_kernel + (KERNEL_PT_INDEX * 8)
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
    mov edi, pt_boot + (BOOT_PT_INDEX * 8)
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

    jmp CODE64_SELECTOR:long_mode_entry

fw_console_write_pm:
    pushad
    cmp byte [firmware_kind], FIRMWARE_KIND_BIOS
    je .bios
    cmp byte [firmware_kind], FIRMWARE_KIND_UEFI
    je .uefi
.bios:
    call console_write_vga32
    jmp .done
.uefi:
    call uefi_console_write_pm_stub
    jmp .done
.done:
    popad
    ret

console_write_vga32:
    mov edi, 0x000B8000
    mov bl, 0x07
.pm_loop:
    lodsb
    test al, al
    jz .pm_done
    mov ah, bl
    mov [edi], ax
    add edi, 2
    jmp .pm_loop
.pm_done:
    ret

uefi_console_write_pm_stub:
    ; Genuine UEFI firmware never executes this path, but fall back to VGA so
    ; developers still see diagnostics if the backend is misdetected.
    jmp console_write_vga32

memmap_build_normalized:
    pushad
    call memmap_reset_final
    cmp byte [firmware_kind], FIRMWARE_KIND_BIOS
    je .from_bios
    cmp byte [firmware_kind], FIRMWARE_KIND_UEFI
    je .from_uefi
    jmp .done
.from_bios:
    call memmap_build_from_bios
    jmp .done
.from_uefi:
    call memmap_build_from_uefi
.done:
    popad
    ret

memmap_reset_final:
    mov dword [memmap_header_signature], NOVA_MEM_SIGNATURE
    mov dword [memmap_entry_count], 0
    mov dword [memmap_source_kind], NOVA_MEM_SOURCE_NONE

    mov edi, memmap_entries
    mov ecx, NOVA_MEM_MAX_ENTRIES * NOVA_MEM_ENTRY_DWORDS
    xor eax, eax
    rep stosd
    ret

memmap_build_from_bios:
    pushad
    mov dword [memmap_source_kind], NOVA_MEM_SOURCE_BIOS
    movzx ecx, word [bios_memmap_raw_count]
    mov edi, bios_memmap_raw_entries
.bios_loop:
    test ecx, ecx
    jz .bios_done
    mov eax, [edi + 0]
    mov [memmap_tmp_base_low], eax
    mov eax, [edi + 4]
    mov [memmap_tmp_base_high], eax
    mov eax, [edi + 8]
    mov [memmap_tmp_len_low], eax
    mov eax, [edi + 12]
    mov [memmap_tmp_len_high], eax
    mov eax, [edi + 20]
    mov [memmap_tmp_attr], eax
    mov esi, [edi + 16]
    call map_bios_type
    test esi, esi
    jz .bios_skip
    mov eax, [memmap_tmp_len_low]
    or eax, [memmap_tmp_len_high]
    jz .bios_skip
    mov eax, [memmap_tmp_base_low]
    mov edx, [memmap_tmp_base_high]
    mov ebx, [memmap_tmp_len_low]
    mov ecx, [memmap_tmp_len_high]
    mov edi, [memmap_tmp_attr]
    call memmap_append_entry
.bios_skip:
    add edi, BIOS_E820_ENTRY_SIZE
    dec ecx
    jmp .bios_loop
.bios_done:
    popad
    ret

memmap_build_from_uefi:
    pushad
    mov ebp, dword [uefi_memmap_ptr]
    mov eax, dword [uefi_memmap_size]
    mov edx, ebp
    add edx, eax
    test ebp, ebp
    jz .uefi_done
    test eax, eax
    jz .uefi_done
    mov dword [memmap_source_kind], NOVA_MEM_SOURCE_UEFI
.uefi_loop:
    cmp ebp, edx
    jae .uefi_done
    mov eax, dword [uefi_memdesc_size]
    test eax, eax
    jz .uefi_done
    mov [memmap_tmp_desc_size], eax
    mov esi, [ebp + 0]
    call map_uefi_type
    test esi, esi
    jz .uefi_skip
    mov eax, [ebp + 8]
    mov [memmap_tmp_base_low], eax
    mov eax, [ebp + 12]
    mov [memmap_tmp_base_high], eax
    mov eax, [ebp + 24]
    mov [memmap_tmp_len_low], eax
    mov eax, [ebp + 28]
    mov [memmap_tmp_len_high], eax
    mov eax, [ebp + 32]
    mov [memmap_tmp_attr], eax

    mov eax, [memmap_tmp_len_low]
    mov ecx, [memmap_tmp_len_high]
    shld ecx, eax, 12
    shl eax, 12
    mov [memmap_tmp_len_low], eax
    mov [memmap_tmp_len_high], ecx

    mov eax, [memmap_tmp_len_low]
    or eax, [memmap_tmp_len_high]
    jz .uefi_skip

    mov eax, [memmap_tmp_base_low]
    mov edx, [memmap_tmp_base_high]
    mov ebx, [memmap_tmp_len_low]
    mov ecx, [memmap_tmp_len_high]
    mov edi, [memmap_tmp_attr]
    call memmap_append_entry
.uefi_skip:
    mov eax, [memmap_tmp_desc_size]
    add ebp, eax
    jmp .uefi_loop
.uefi_done:
    popad
    ret

map_bios_type:
    cmp esi, 1
    je .usable
    cmp esi, 2
    je .reserved
    cmp esi, 3
    je .acpi_reclaim
    cmp esi, 4
    je .acpi_nvs
    cmp esi, 5
    je .mmio
    cmp esi, 7
    je .persistent
    jmp .default_reserved
.usable:
    mov esi, NOVA_MEM_TYPE_USABLE
    ret
.reserved:
.default_reserved:
    mov esi, NOVA_MEM_TYPE_RESERVED
    ret
.acpi_reclaim:
    mov esi, NOVA_MEM_TYPE_ACPI_RECLAIM
    ret
.acpi_nvs:
    mov esi, NOVA_MEM_TYPE_ACPI_NVS
    ret
.mmio:
    mov esi, NOVA_MEM_TYPE_MMIO
    ret
.persistent:
    mov esi, NOVA_MEM_TYPE_PERSISTENT
    ret

map_uefi_type:
    cmp esi, 7              ; EfiConventionalMemory
    je .usable
    cmp esi, 1              ; LoaderCode
    je .usable
    cmp esi, 2              ; LoaderData
    je .usable
    cmp esi, 3              ; BootServicesCode
    je .usable
    cmp esi, 4              ; BootServicesData
    je .usable
    cmp esi, 8              ; Unusable
    je .bad
    cmp esi, 9              ; ACPI reclaim
    je .acpi_reclaim
    cmp esi, 10             ; ACPI NVS
    je .acpi_nvs
    cmp esi, 11             ; MMIO
    je .mmio
    cmp esi, 12             ; MMIO port space
    je .mmio
    cmp esi, 14             ; Persistent Mem
    je .persistent
    mov esi, NOVA_MEM_TYPE_RESERVED
    ret
.usable:
    mov esi, NOVA_MEM_TYPE_USABLE
    ret
.bad:
    mov esi, NOVA_MEM_TYPE_BAD
    ret
.acpi_reclaim:
    mov esi, NOVA_MEM_TYPE_ACPI_RECLAIM
    ret
.acpi_nvs:
    mov esi, NOVA_MEM_TYPE_ACPI_NVS
    ret
.mmio:
    mov esi, NOVA_MEM_TYPE_MMIO
    ret
.persistent:
    mov esi, NOVA_MEM_TYPE_PERSISTENT
    ret

memmap_append_entry:
    pushad
    mov eax, [memmap_entry_count]
    cmp eax, NOVA_MEM_MAX_ENTRIES
    jb .store
    mov dword [memmap_truncated_flag], 1
    jmp .done
.store:
    mov edx, NOVA_MEM_ENTRY_SIZE
    mul edx
    mov edi, memmap_entries
    add edi, eax
    mov eax, [esp + 0]   ; base low
    mov edx, [esp + 8]   ; base high
    mov ebx, [esp + 12]  ; length low
    mov ecx, [esp + 4]   ; length high
    mov esi, [esp + 24]  ; type
    mov ebp, [esp + 28]  ; attr

    mov [edi + 0], eax
    mov [edi + 4], edx
    mov [edi + 8], ebx
    mov [edi + 12], ecx
    mov [edi + 16], esi
    mov [edi + 20], ebp

    mov eax, [memmap_entry_count]
    inc eax
    mov [memmap_entry_count], eax
.done:
    popad
    ret

bootinfo_init:
    pushad
    mov edi, bootinfo_struct
    mov ecx, (bootinfo_end - bootinfo_struct) / 4
    xor eax, eax
    rep stosd
    mov dword [bootinfo_signature], BOOTINFO_SIGNATURE
    mov eax, bootinfo_end - bootinfo_struct
    mov [bootinfo_length], eax
    mov dword [bootinfo_version], 1
    popad
    ret

bootinfo_collect_cpu:
    pushad
    xor ecx, ecx
    mov eax, 0
    cpuid
    mov [bootinfo_cpu_max_basic], eax
    mov [bootinfo_cpu_vendor], ebx
    mov [bootinfo_cpu_vendor + 4], edx
    mov [bootinfo_cpu_vendor + 8], ecx
    mov byte [bootinfo_cpu_vendor + 12], 0

    mov eax, 1
    xor ecx, ecx
    cpuid
    mov [bootinfo_cpu_signature], eax
    mov [bootinfo_cpu_features_edx], edx
    mov [bootinfo_cpu_features_ecx], ecx

    mov eax, 0x80000000
    xor ecx, ecx
    cpuid
    mov [bootinfo_cpu_max_ext], eax
    cmp eax, 0x80000004
    jb .no_brand
    mov esi, bootinfo_cpu_brand
    mov eax, 0x80000002
.brand_loop:
    xor ecx, ecx
    cpuid
    mov [esi], eax
    mov [esi + 4], ebx
    mov [esi + 8], ecx
    mov [esi + 12], edx
    add esi, 16
    inc eax
    cmp eax, 0x80000005
    jb .brand_loop
    or dword [bootinfo_flags], BOOTINFO_FLAG_CPU_BRAND
.no_brand:
    popad
    ret

bootinfo_collect_smbios:
    pushad
    mov esi, 0x000F0000
    mov edi, 0x00100000
.scan_loop:
    cmp esi, edi
    jae .done
    mov eax, [esi]
    cmp eax, 0x5F4D535F            ; '_SM_'
    je .check_v2
    add esi, 16
    jmp .scan_loop
.check_v2:
    movzx ecx, byte [esi + 5]
    cmp ecx, 0
    je .next
    push ecx
    mov edi, esi
    xor ebx, ebx
.sum_loop:
    add bl, [edi]
    inc edi
    dec ecx
    jnz .sum_loop
    test bl, bl
    pop ecx
    jne .next
    mov eax, [esi + 0x10]
    cmp eax, 0x5F494D44            ; 'DMI_'
    jne .next
    mov edi, esi
    add edi, 0x10
    mov ecx, 0x0F
    xor bl, bl
.dmi_sum:
    add bl, [edi]
    inc edi
    dec ecx
    jnz .dmi_sum
    test bl, bl
    jne .next
    mov eax, [esi + 0x18]
    mov [bootinfo_smbios_phys], eax
    movzx eax, word [esi + 0x16]
    mov [bootinfo_smbios_len], eax
    or dword [bootinfo_flags], BOOTINFO_FLAG_SMBIOS
    jmp .done
.next:
    add esi, 16
    jmp .scan_loop
.done:
    popad
    ret

bootinfo_finalize:
    pushad
    mov eax, [cpu_info_count]
    mov [bootinfo_cpu_core_count], eax
    popad
    ret

acpi_collect_tables:
    pushad
    test dword [acpi_info_flags], ACPI_FLAG_FOUND
    jnz .ensure_cache
    cmp byte [firmware_kind], FIRMWARE_KIND_BIOS
    jne .ensure_cache
    call acpi_search_bios_pm
    jc .ensure_cache
    mov [acpi_rsdp_phys], eax
    mov dword [acpi_rsdp_phys + 4], 0
    and dword [acpi_info_flags], ~ACPI_FLAG_FROM_UEFI
.ensure_cache:
    cmp word [acpi_rsdp_cache_len], 0
    jne .process
    call acpi_copy_rsdp_from_phys32
.process:
    cmp word [acpi_rsdp_cache_len], 0
    je .out
    call acpi_process_rsdp_cache
.out:
    popad
    ret

acpi_search_bios_pm:
    movzx eax, word [0x0000040E]
    shl eax, 4
    mov edx, eax
    add edx, 0x00000400
    call acpi_scan_region_pm
    jnc .done
    mov eax, 0x000E0000
    mov edx, 0x00100000
    call acpi_scan_region_pm
.done:
    ret

acpi_scan_region_pm:
    push ebx
    push esi
    push edi
    mov esi, eax
.scan_loop:
    cmp esi, edx
    jae .fail
    mov edi, rsdp_signature
    mov ecx, 8
    mov ebx, esi
.cmp_loop:
    mov al, [ebx]
    mov ah, [edi]
    cmp al, ah
    jne .advance
    inc ebx
    inc edi
    dec ecx
    jnz .cmp_loop
    mov edi, acpi_rsdp_cache
    mov ecx, ACPI_RSDP_COPY_LEN
    mov ebx, esi
.copy_loop:
    mov al, [ebx]
    mov [edi], al
    inc ebx
    inc edi
    dec ecx
    jnz .copy_loop
    call acpi_validate_rsdp_cache_pm
    jc .advance
    mov eax, esi
    clc
    jmp .exit
.advance:
    add esi, 16
    jmp .scan_loop
.fail:
    stc
.exit:
    pop edi
    pop esi
    pop ebx
    ret

acpi_copy_rsdp_from_phys32:
    pushad
    mov eax, [acpi_rsdp_phys + 4]
    test eax, eax
    jne .fail
    mov eax, [acpi_rsdp_phys]
    test eax, eax
    je .fail
    cmp eax, LOW_IDENTITY_SIZE
    jae .fail
    mov esi, eax
    mov edi, acpi_rsdp_cache
    mov ecx, ACPI_RSDP_COPY_LEN
.cp_loop:
    mov al, [esi]
    mov [edi], al
    inc esi
    inc edi
    dec ecx
    jnz .cp_loop
    call acpi_validate_rsdp_cache_pm
.fail:
    popad
    ret

acpi_validate_rsdp_cache_pm:
    pushad
    movzx ecx, byte [acpi_rsdp_cache + 15]
    mov [acpi_rsdp_revision], cl
    mov eax, ACPI_RSDP_MIN_LEN
    cmp cl, 2
    jb .len_ready
    mov eax, [acpi_rsdp_cache + 20]
    cmp eax, ACPI_RSDP_COPY_LEN
    jbe .len_ready
    mov eax, ACPI_RSDP_COPY_LEN
.len_ready:
    cmp eax, ACPI_RSDP_MIN_LEN
    jae .len_ok
    mov eax, ACPI_RSDP_MIN_LEN
.len_ok:
    mov [acpi_rsdp_cache_len], ax
    movzx ecx, ax
    mov esi, acpi_rsdp_cache
    xor edx, edx
.chk_loop:
    movzx eax, byte [esi]
    add dl, al
    inc esi
    loop .chk_loop
    test dl, dl
    jne .chk_fail
    or dword [acpi_info_flags], ACPI_FLAG_FOUND
    clc
    jmp .chk_done
.chk_fail:
    mov word [acpi_rsdp_cache_len], 0
    stc
.chk_done:
    popad
    ret

acpi_process_rsdp_cache:
    pushad
    cmp word [acpi_rsdp_cache_len], 0
    je .done
    movzx eax, byte [acpi_rsdp_cache + 15]
    mov [acpi_rsdp_revision], al
    mov eax, [acpi_rsdp_cache + 16]
    mov [acpi_rsdt_phys], eax
    mov eax, [acpi_rsdp_cache + 24]
    mov [acpi_xsdt_phys], eax
    mov eax, [acpi_rsdp_cache + 28]
    mov [acpi_xsdt_phys + 4], eax
    mov eax, [acpi_xsdt_phys]
    or eax, [acpi_xsdt_phys + 4]
    movzx ecx, byte [acpi_rsdp_cache + 15]
    cmp ecx, 2
    jb .no_xsdt
    test eax, eax
    je .no_xsdt
    or dword [acpi_info_flags], ACPI_FLAG_HAS_XSDT
    jmp .done
.no_xsdt:
    and dword [acpi_info_flags], ~ACPI_FLAG_HAS_XSDT
.done:
    popad
    ret

acpi_map_table32:
    push edx
    xor edx, edx
    call acpi_map_table_phys
    pop edx
    ret

acpi_map_table64:
    call acpi_map_table_phys
    ret

acpi_map_table_phys:
    pushad
    mov ebx, eax
    mov ecx, edx
    test ecx, ecx
    jne .fail
    cmp ebx, LOW_IDENTITY_SIZE
    jae .fail
    mov esi, ebx
    mov edi, acpi_table_buffer
    mov ecx, 36
    rep movsb
    mov edi, acpi_table_buffer
    mov edx, [edi + 4]
    cmp edx, 36
    jb .fail
    cmp edx, ACPI_TABLE_BUFFER_SIZE
    ja .fail
    mov eax, ebx
    add eax, edx
    cmp eax, LOW_IDENTITY_SIZE
    ja .fail
    mov esi, ebx
    add esi, 36
    mov edi, acpi_table_buffer + 36
    mov ecx, edx
    sub ecx, 36
    rep movsb
    clc
    jmp .done
.fail:
    stc
.done:
    popad
    ret

acpi_unmap_table:
    ret

smp_register_cpu:
    pushad
    mov esi, eax                ; APIC ID
    mov dl, al
    mov ecx, [cpu_info_count]
    cmp ecx, NOVA_CPU_MAX_ENTRIES
    jb .store
    or dword [acpi_info_flags], ACPI_FLAG_CPU_LIMIT
    jmp .done
.store:
    mov edi, cpu_entries
    mov eax, ecx
    mov ebx, CPU_ENTRY_SIZE
    mul ebx
    add edi, eax
    cmp byte [edi], 0
    jne .skip_store
    mov byte [edi], dl
    mov byte [edi + 1], NOVA_CPU_KIND_LAPIC
    mov word [edi + 2], 0
    mov [edi + 4], ecx
    mov [edi + 8], esi
    mov dword [edi + 12], 0
.skip_store:
    mov eax, ecx
    inc eax
    mov [cpu_info_count], eax
    mov eax, esi
    cmp eax, 32
    jb .lowbmp
    sub eax, 32
    bts dword [cpu_apic_id_bmp_high], eax
    jmp .bitmap_done
.lowbmp:
    bts dword [cpu_apic_id_bmp_low], eax
.bitmap_done:
    cmp dword [cpu_bsp_lapic_id], 0
    jne .done
    mov [cpu_bsp_lapic_id], esi
.done:
    popad
    ret
smp_collect_cpu_info:
    pushad
    call smp_reset_info
    test dword [acpi_info_flags], ACPI_FLAG_FOUND
    je .done
    test dword [acpi_info_flags], ACPI_FLAG_HAS_XSDT
    jne .use_xsdt
    call smp_scan_rsdt
    jmp .done
.use_xsdt:
    call smp_scan_xsdt
.done:
    popad
    ret

smp_reset_info:
    mov dword [cpu_info_signature], 0x4E435550
    mov dword [cpu_info_count], 0
    mov dword [cpu_apic_id_bmp_low], 0
    mov dword [cpu_apic_id_bmp_high], 0
    mov dword [cpu_bsp_lapic_id], 0
    mov eax, ACPI_FLAG_HAS_MADT
    or eax, ACPI_FLAG_CPU_LIMIT
    not eax
    and dword [acpi_info_flags], eax
    mov edi, cpu_entries
    mov ecx, (NOVA_CPU_MAX_ENTRIES * CPU_ENTRY_SIZE) / 4
    xor eax, eax
    rep stosd
    ret

smp_scan_rsdt:
    pushad
    mov eax, [acpi_rsdt_phys]
    test eax, eax
    je .out
    call acpi_map_table32
    jc .out
    mov esi, acpi_table_buffer
    mov ebx, [esi + 4]
    cmp ebx, 36
    jb .unmap
    sub ebx, 36
    shr ebx, 2
    mov edi, acpi_table_buffer + 36
.rsdt_loop:
    test ebx, ebx
    jz .unmap
    mov eax, [edi]
    push ebx
    push edi
    call smp_try_parse_table32
    pop edi
    pop ebx
    add edi, 4
    dec ebx
    jmp .rsdt_loop
.unmap:
    call acpi_unmap_table
.out:
    popad
    ret

smp_scan_xsdt:
    pushad
    mov eax, [acpi_xsdt_phys]
    mov edx, [acpi_xsdt_phys + 4]
    test eax, eax
    jne .have_ptr
    test edx, edx
    je .out
.have_ptr:
    call acpi_map_table64
    jc .out
    mov esi, acpi_table_buffer
    mov ebx, [esi + 4]
    cmp ebx, 44
    jb .unmap
    sub ebx, 44
    shr ebx, 3
    mov edi, acpi_table_buffer + 44
.xsdt_loop:
    test ebx, ebx
    jz .unmap
    mov eax, [edi]
    mov edx, [edi + 4]
    push ebx
    push edi
    call smp_try_parse_table64
    pop edi
    pop ebx
    add edi, 8
    dec ebx
    jmp .xsdt_loop
.unmap:
    call acpi_unmap_table
.out:
    popad
    ret

smp_try_parse_table32:
    pushad
    mov edx, 0
    call acpi_map_table_phys
    jc .done
    call smp_parse_madt
    call acpi_unmap_table
.done:
    popad
    ret

smp_try_parse_table64:
    pushad
    call acpi_map_table_phys
    jc .done
    call smp_parse_madt
    call acpi_unmap_table
.done:
    popad
    ret

smp_parse_madt:
    pushad
    mov esi, acpi_table_buffer
    mov eax, [esi]
    cmp eax, ACPI_SIG_MADT
    jne .out
    mov ebx, [cpu_info_count]
    mov ecx, [esi + 36]
    mov [cpu_lapic_phys], ecx
    mov edx, [esi + 40]
    mov edi, esi
    add edi, 44
    mov eax, [esi + 4]
    sub eax, 44
    or dword [acpi_info_flags], ACPI_FLAG_HAS_MADT
.madt_loop:
    cmp eax, 0
    jle .out
    mov bl, [edi]
    mov bh, [edi + 1]
    movzx ecx, bh
    cmp ecx, 2
    jb .advance
    cmp bl, 0
    je smp_handle_lapic
    cmp bl, 1
    je smp_handle_ioapic
    cmp bl, 2
    je smp_handle_iso
    cmp bl, 4
    je smp_handle_nmi
    jmp .advance
.advance:
    movzx ecx, bh
    add edi, ecx
    sub eax, ecx
    jmp .madt_loop
.out:
    popad
    ret

smp_handle_lapic:
    pushad
    mov bl, [edi + 2]
    mov bh, [edi + 3]
    test bh, 1
    jz .done
    movzx eax, bl
    call smp_register_cpu
.done:
    popad
    jmp smp_parse_madt.advance

smp_handle_ioapic:
    pushad
    ; currently ignored
    popad
    jmp smp_parse_madt.advance

smp_handle_iso:
    jmp smp_parse_madt.advance
smp_handle_nmi:
    jmp smp_parse_madt.advance

init_idt:
    pushad
    mov ebx, STAGE2_ABS(default_isr)
    mov edx, CODE32_SELECTOR
    mov ecx, 256
    mov edi, idt_entries
.idt_loop:
    mov word [edi], bx
    mov word [edi + 2], dx
    mov byte [edi + 4], 0
    mov byte [edi + 5], 0x8E
    mov eax, ebx
    shr eax, 16
    mov word [edi + 6], ax
    add edi, 8
    loop .idt_loop

    mov ebx, STAGE2_ABS(default_isr_err)
    mov esi, error_code_vectors
    mov ecx, ERROR_VECTOR_COUNT
.patch_loop:
    movzx eax, byte [esi]
    imul eax, eax, 8
    lea edi, [idt_entries + eax]
    mov word [edi], bx
    mov word [edi + 2], dx
    mov byte [edi + 4], 0
    mov byte [edi + 5], 0x8E
    mov eax, ebx
    shr eax, 16
    mov word [edi + 6], ax
    inc esi
    loop .patch_loop

    mov eax, STAGE2_ABS(idt_entries)
    mov [idt_descriptor_pm + 2], eax
    lidt [idt_descriptor_pm]
    popad
    ret

[bits 16]

stage2_real_mode_msg: db "Stage 2: preparing protected mode...", 0x0D, 0x0A, 0
pmode_message:        db "Paging tables ready; entering long mode...", 0

gdt_descriptor:
    dw gdt_end - gdt_start - 1
    dd GDT_BASE

gdt_start:
    dq 0x0000000000000000          ; Null descriptor
    GDT_ENTRY 0x000FFFFF, STAGE2_LINEAR_BASE, 0x9A, 0x0C   ; 32-bit code
    GDT_ENTRY 0x000FFFFF, STAGE2_LINEAR_BASE, 0x92, 0x0C   ; Data segment
    GDT_ENTRY 0x000FFFFF, STAGE2_LINEAR_BASE, 0x9A, 0x0A   ; 64-bit code
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

memmap_header_signature: dd NOVA_MEM_SIGNATURE
memmap_entry_count:      dd 0
memmap_truncated_flag:   dd 0
memmap_source_kind:      dd NOVA_MEM_SOURCE_NONE
memmap_entries:
    times (NOVA_MEM_MAX_ENTRIES * NOVA_MEM_ENTRY_DWORDS) dd 0

memmap_tmp_base_low:   dd 0
memmap_tmp_base_high:  dd 0
memmap_tmp_len_low:    dd 0
memmap_tmp_len_high:   dd 0
memmap_tmp_attr:       dd 0
memmap_tmp_desc_size:  dd 0

bios_memmap_raw_count:   dw 0
bios_memmap_raw_entries:
    times (NOVA_MEM_MAX_ENTRIES * BIOS_E820_ENTRY_SIZE) db 0
bios_e820_temp:          times BIOS_E820_ENTRY_SIZE db 0

acpi_info_signature: dd 0x4E414350
acpi_info_flags:     dd 0
acpi_rsdp_phys:      dq 0
acpi_rsdt_phys:      dd 0
acpi_xsdt_phys:      dq 0
acpi_rsdp_revision:  db 0
acpi_rsdp_cache_len: dw 0
acpi_reserved_pad:   db 0
acpi_rsdp_cache:     times ACPI_RSDP_COPY_LEN db 0
rsdp_signature:      db "RSD PTR ", 0

acpi_table_buffer:   times ACPI_TABLE_BUFFER_SIZE db 0

cpu_info_signature:  dd 0
cpu_info_count:      dd 0
cpu_apic_id_bmp_low: dd 0
cpu_apic_id_bmp_high:dd 0
cpu_bsp_lapic_id:    dd 0
cpu_lapic_phys:      dd 0
cpu_entries:
    times (NOVA_CPU_MAX_ENTRIES * 4) dd 0
bootinfo_struct:
bootinfo_signature:      dd 0
bootinfo_length:         dd 0
bootinfo_version:        dd 0
bootinfo_flags:          dd 0
bootinfo_cpu_vendor:     times 16 db 0
bootinfo_cpu_brand:      times 48 db 0
bootinfo_cpu_signature:  dd 0
bootinfo_cpu_features_edx: dd 0
bootinfo_cpu_features_ecx: dd 0
bootinfo_cpu_max_basic:  dd 0
bootinfo_cpu_max_ext:    dd 0
bootinfo_cpu_core_count: dd 0
bootinfo_smbios_phys:    dd 0
bootinfo_smbios_len:     dd 0
bootinfo_reserved:       times 8 dd 0
bootinfo_end:
bootinfo_ptr:            dd bootinfo_struct
idt_descriptor_pm:
    dw idt_entries_end - idt_entries - 1
    dd idt_entries
idt_entries:
    times 256 dq 0
idt_entries_end:
default_isr:
    iretd
default_isr_err:
    add esp, 4
    iretd
error_code_vectors: db 8, 10, 11, 12, 13, 14, 17
firmware_kind:       db FIRMWARE_KIND_BIOS
firmware_boot_drive: db 0
firmware_flags:      dw 0

uefi_system_table_ptr: dq 0
uefi_text_output_ptr:  dq 0
uefi_block_io_ptr:     dq 0
uefi_image_handle_ptr: dq 0
uefi_memmap_ptr:       dq 0
uefi_memmap_size:      dq 0
uefi_memdesc_size:     dd 0
uefi_memdesc_version:  dd 0
uefi_utf16_buffer:     times UEFI_UTF16_BUFFER_LEN dw 0

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
    call fw_console_write_lm
    cli
.lm_halt:
    hlt
    jmp .lm_halt

long_mode_success: db "NovaOS long mode active (CS=0x18, SS=0x10, stack ok).", 0
long_mode_error:   db "Long mode validation failed!", 0

fw_console_write_lm:
    push rbx
    push rdi
    push rsi
    cmp byte [firmware_kind], FIRMWARE_KIND_BIOS
    je .bios
    cmp byte [firmware_kind], FIRMWARE_KIND_UEFI
    je .uefi
.bios:
    call console_write_vga64
    jmp .done
.uefi:
    call uefi_console_write_lm
    jmp .done
.done:
    pop rsi
    pop rdi
    pop rbx
    ret

console_write_vga64:
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
    ret

uefi_console_write_lm:
    mov rax, [uefi_text_output_ptr]
    test rax, rax
    jz console_write_vga64
    push rsi
    push rdi
    lea rdi, [rel uefi_utf16_buffer]
    call ascii_to_utf16
    mov rdx, rax
    mov rcx, [uefi_text_output_ptr]
    mov rax, [rcx + EFI_SIMPLE_TEXT_OUTPUT_OUTPUTSTRING]
    mov r8, 0
    mov r9, 0
    call rax
    pop rdi
    pop rsi
    ret

ascii_to_utf16:
    push rbx
    mov rbx, rdi
.utf16_loop:
    lodsb
    mov [rdi], al
    mov byte [rdi + 1], 0
    add rdi, 2
    test al, al
    jne .utf16_loop
    mov rax, rbx
    pop rbx
    ret

firmware_install_uefi:
    ; RDI points to a NovaFirmwareContext structure populated by the UEFI stub.
    test rdi, rdi
    jz .done
    mov eax, dword [rdi + NOVA_FW_CTX_SIGNATURE]
    cmp eax, NOVA_FIRMWARE_SIGNATURE
    jne .done

    mov byte [firmware_kind], FIRMWARE_KIND_UEFI
    mov rax, [rdi + NOVA_FW_CTX_SYSTEM_TABLE]
    mov [uefi_system_table_ptr], rax
    mov rax, [rdi + NOVA_FW_CTX_TEXT_OUTPUT]
    mov [uefi_text_output_ptr], rax
    mov rax, [rdi + NOVA_FW_CTX_BLOCK_IO]
    mov [uefi_block_io_ptr], rax
    mov rax, [rdi + NOVA_FW_CTX_IMAGE_HANDLE]
    mov [uefi_image_handle_ptr], rax
    mov rax, [rdi + NOVA_FW_CTX_MEMMAP_PTR]
    mov [uefi_memmap_ptr], rax
    mov rax, [rdi + NOVA_FW_CTX_MEMMAP_SIZE]
    mov [uefi_memmap_size], rax
    mov eax, dword [rdi + NOVA_FW_CTX_MEMDESC_SIZE]
    mov [uefi_memdesc_size], eax
    mov eax, dword [rdi + NOVA_FW_CTX_MEMDESC_VERSION]
    mov [uefi_memdesc_version], eax
    mov rax, [rdi + NOVA_FW_CTX_RSDP_PTR]
    mov [acpi_rsdp_phys], rax
    test rax, rax
    je .done
    mov word [acpi_rsdp_cache_len], 0
    or dword [acpi_info_flags], ACPI_FLAG_FOUND
    or dword [acpi_info_flags], ACPI_FLAG_FROM_UEFI
.done:
    ret
