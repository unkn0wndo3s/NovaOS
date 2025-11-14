# NovaOS — Bootloader (Developer README)

This branch contains the Nova OS custom bootloader responsible for loading the kernel and preparing the system environment.

This document explains:
- Required tools
- How to install them
- How to build
- How to run
- Contribution rules

No feature documentation is included here.

## Requirements

Nova OS bootloader development officially supports Linux (Ubuntu recommended).

Mandatory toolchain:
- nasm
- make
- qemu-system-x86
- python3
- Standard Linux build utilities

All build commands are handled by the provided `.sh` scripts.

## Installation

Install all dependencies with:

```
./setup.sh
```

This installs:
- nasm
- qemu-system-x86
- build utilities used by the Makefile

## Build

Compile the bootloader:

```
./build.sh
```

This runs `make`, generating:
- `build/stage1.bin` — BIOS boot sector (Stage 1)
- `build/stage2.bin` — loader payload (Stage 2, padded to sector boundaries)
- `build/novaos.img` — concatenated disk image ready for QEMU

## Run

Start the bootloader in QEMU:

```
./run.sh
```

The image boots in `qemu-system-x86_64`. Pass extra QEMU flags to `run.sh` if required.

## Boot Flow Overview

- **Stage 1 (`boot/stage1.asm`)**
  - BIOS loads the first sector at `0x7C00`.
  - Code immediately sets up a stack, then relocates itself to `0x0600:0000` to keep the original BIOS buffer free.
  - Uses INT 13h extensions (AH=0x42) to load `STAGE2_SECTORS` sectors starting at LBA 1 into `0x1000:0000`.
  - After a successful read, jumps to Stage 2; otherwise prints an error via BIOS TTY and halts.

- **Stage 2 (`boot/stage2.asm`)**
  - Real-mode prologue prints a status banner, copies a three-entry GDT template into low memory (`0x0000:0x0500`), and loads GDTR.
  - Switches to 32-bit protected mode by setting CR0.PE and performing a far jump to the flat 0x08 code selector.
  - Initializes all segment registers plus a 32-bit stack (`ESP = 0x9F000`) and builds the paging hierarchy required for the long-mode transition:
    - PML4/PDPT/PD/PT tables (eight 4 KiB pages) are zeroed and filled at runtime.
    - Identity map of the lowest 2 MiB keeps BIOS-visible memory reachable during transition.
    - Kernel window: maps `0xFFFFFFFF80000000-0xFFFFFFFF80200000` to physical `0x00200000` (2 MiB).
    - Bootloader window: maps `0xFFFFFFFF80200000` onward to the real-mode loader image at `0x00010000` (128 KiB).
  - Enables PAE, sets IA32_EFER.LME, turns on paging (CR0.PG), then far-jumps to a 64-bit code segment. A unified firmware API (`fw_console_write_*`) now handles all console output while the BIOS backend falls back to VGA text memory and the UEFI backend routes through `EFI_SIMPLE_TEXT_OUTPUT_PROTOCOL` when configured. A second-stage check confirms `CS=0x18`, `SS=0x10`, and the high-half stack pointer before announcing long-mode status.
  - Collects the system memory map: BIOS builds a raw E820 table in real mode, while UEFI shims can inject their firmware memory map via the shared `NovaFirmwareContext`. In protected mode the loader normalizes every descriptor into a compact internal array (`memmap_header` + `memmap_entries`) so later stages see consistent types, lengths, and a truncation flag regardless of firmware.
  - Discovers ACPI: BIOS mode scans the EBDA and high BIOS area for the RSDP; UEFI mode may supply the pointer through `NovaFirmwareContext`. The loader validates the descriptor, captures the revision, and records the RSDT/XSDT physical addresses so the kernel can jump straight to ACPI tables.
  - Enumerates CPUs: once the ACPI tables are cached, Stage 2 parses the MADT entries (from either RSDT or XSDT) and records LAPIC IDs, BSP hints, and bitmaps for up to `NOVA_CPU_MAX_ENTRIES` logical processors. Overflow sets the `NOVA_ACPI_FLAG_CPU_LIMIT` flag so the kernel can warn about truncated topologies.
- Enumerates disks: in BIOS mode real-mode INT 13h calls (`AH=48h`) probe up to 16 drives starting at `0x80`, recording EDD flags, geometry, and total sectors inside the BootInfo table. UEFI builds can pass a pre-populated disk list via the firmware context so the same table is available before the kernel starts.
  - Builds a `BootInfo` hardware summary that accompanies the memory/CPU tables. CPUID is used to capture the vendor string, maximum leaf, feature flags, and (if available) the full brand string; the final CPU count is copied from the SMP enumeration. A SMBIOS entry-point scan (`0xF0000-0xFFFFF`) records table length and physical address when an `_SM_` anchor is present.
  - This is the natural place to add A20 enable logic, paging, and kernel loading.

The Stage 1 build depends on `build/stage2.inc`, which is generated automatically by `scripts/gen_stage2_inc.sh`. The script pads `stage2.bin` out to whole sectors and records how many sectors Stage 1 should request from the BIOS.

## Customisation Notes

- Extend Stage 2 freely; the helper script recalculates the sector count every build, so no manual constants are needed unless you change the load address.
- If Stage 2 grows beyond the first few sectors, ensure it still fits within the BIOS-readable area or add paging logic before switching to protected/long mode.
- The GDT is currently staged at physical address `0x00000500`; update `GDT_BASE` in `boot/stage2.asm` if you need a different location, and keep it below 1 MiB unless A20 is enabled.
- Paging structures live inside Stage 2 (see the `page_tables_start` block). If you relocate Stage 2, update `STAGE2_LOAD_SEG` to keep the physical addresses computed for CR3 valid. Expand the identity/kernel/boot mappings via the constants at the top of `boot/stage2.asm`.
- Long-mode entry uses the selectors defined in the Stage 2 GDT (`0x18` for 64-bit code, `0x10` for data). Adjust those descriptors if you change the GDT layout or need additional privilege levels.
- All firmware-related interfaces live under `boot/include/firmware.inc`. Callers should use the `fw_console_write_rm/pm/lm` helpers (exposed by `boot/stage2.asm`) instead of invoking BIOS interrupts or UEFI protocols directly. A future UEFI loader can populate a `NovaFirmwareContext` structure (signature `NFWU`) and call `firmware_install_uefi()` to switch the backend without modifying higher-level code.
- Keep Stage 1 within 512 bytes including the `0xAA55` signature; `nasm` plus the padding directive in `boot/stage1.asm` enforces this.

## Firmware Abstraction Layer

- `boot/include/firmware.inc` holds the shared constants: firmware kinds, the `NFWU` context signature, and the offsets every UEFI shim must fill before jumping into Stage 2.
- Stage 2 publishes three console helpers:
  - `fw_console_write_rm` (real mode) — BIOS backend implements INT 10h, UEFI backend currently falls back to VGA for diagnostics.
  - `fw_console_write_pm` (32-bit) — used during paging/GDT setup; BIOS backend writes to VGA memory, UEFI backend defers to VGA until the handoff switches contexts.
  - `fw_console_write_lm` (64-bit) — BIOS backend keeps writing to the text buffer, while the UEFI backend calls `EFI_SIMPLE_TEXT_OUTPUT_PROTOCOL.OutputString` if the context block provided a pointer.
- UEFI shims can prepare a `NovaFirmwareContext` structure anywhere in memory, set the first doubleword to `NFWU`, populate the system table, simple text output, block I/O, image handle, memory-map, RSDP, and disk-list pointers, then call `firmware_install_uefi(rdi=ctx)` before transferring control to the shared long-mode logic. Disk I/O, ACPI, CPU topology, and other services follow the same pattern without touching the high-level loaders.

## Memory Map

- Stage 2 always resets and rebuilds a normalized map before entering 64-bit mode.
  - **BIOS path:** a real-mode INT 15h/E820 sweep is cached in `bios_memmap_raw_entries`, then converted into the canonical format once protected mode is active.
  - **UEFI path:** supply the original firmware memory map through the `NovaFirmwareContext` fields (`MEMMAP_PTR`, `MEMMAP_SIZE`, `MEMDESC_SIZE`, `MEMDESC_VERSION`) and call `firmware_install_uefi()`; the shared loader consumes those descriptors without caring whether the system started in BIOS or UEFI.
- Normalized output lives under `memmap_header` (`signature=NOVA_MEM_SIGNATURE`, `entry_count`, `truncated`, `source_kind`) followed by `memmap_entries`, a fixed array of `NOVA_MEM_MAX_ENTRIES` records. Each record stores `{ base (64-bit), length (64-bit), type (enum), attributes (32-bit) }`.
- Types are abstracted into a small, firmware-neutral set (`NOVA_MEM_TYPE_USABLE`, `RESERVED`, `ACPI_RECLAIM`, `ACPI_NVS`, `MMIO`, `BAD`, `PERSISTENT`). Any unmapped firmware codes fall back to `RESERVED`.
- If the raw BIOS sweep or the normalized table overflows `NOVA_MEM_MAX_ENTRIES`, `memmap_truncated_flag` is set to `1` so later stages can degrade gracefully.
- The same firmware context exposes `MEMMAP_PTR`, `MEMMAP_SIZE`, `MEMDESC_SIZE`, and `MEMDESC_VERSION` so a UEFI shim can pass along the memory descriptors losslessly; Stage 2 takes care of normalizing them at runtime.

## ACPI Tables

- `acpi_info_signature` + `acpi_info_flags` describe the ACPI hand-off. Flags follow the shared constants (`NOVA_ACPI_FLAG_FOUND`, `HAS_XSDT`, `FROM_UEFI`) defined in `boot/include/firmware.inc`.
- BIOS path: `acpi_search_bios_pm` scans the EBDA and the `0xE0000-0xFFFFF` BIOS window on 16-byte boundaries looking for `"RSD PTR "`. After validation, the loader caches the descriptor in `acpi_rsdp_cache`, records the physical pointer in `acpi_rsdp_phys`, and extracts the RSDT/XSDT addresses for the kernel.
- UEFI path: populate `RSDP_PTR` inside `NovaFirmwareContext` before calling `firmware_install_uefi`. Stage 2 copies and validates the descriptor (identity-mapped low memory must still cover the pointer; extend `LOW_IDENTITY_SIZE` if your firmware places the RSDP above 2 MiB).
- Normalized outputs:
  - `acpi_rsdp_revision` — ACPI revision (1 or 2+).
  - `acpi_rsdt_phys` — 32-bit physical address from the RSDP (always present).
  - `acpi_xsdt_phys` — 64-bit physical address if revision ≥2; `ACPI_FLAG_HAS_XSDT` indicates whether it is valid.
  - `acpi_rsdp_cache_len` + `acpi_rsdp_cache` — cached copy of the descriptor (20–36 bytes) so later stages can revalidate without re-scanning firmware memory.

## CPU / SMP Info

- `cpu_info_signature` is set to `'NCPU'` (`0x4E435550`) whenever enumeration succeeds. `cpu_info_count` tracks the number of logical processors recorded (capped by `NOVA_CPU_MAX_ENTRIES`).
- Each entry inside `cpu_entries` currently uses 16 bytes: `{apic_id (8-bit), kind, flags, logical_index, apic_id copy, reserved}`. `kind` is `NOVA_CPU_KIND_LAPIC` for standard LAPIC processors; future types (I/O APIC, clusters) can reuse the same structure.
- `cpu_bsp_lapic_id`, `cpu_apic_id_bmp_low`, and `cpu_apic_id_bmp_high` expose quick BSP/bitmap summaries for up to 64 APIC IDs. If more processors exist than the fixed buffer allows, `NOVA_ACPI_FLAG_CPU_LIMIT` toggles so the kernel can fall back to runtime ACPI parsing.
- MADT parsing walks the entries provided in either the RSDT or the XSDT, depending on the ACPI revision. If no MADT is present or the firmware table lives outside the identity-mapped window, the structures remain zeroed and the kernel should rescan using the ACPI pointers described above.

## BootInfo Hardware Summary

- `bootinfo_struct` (symbol exported from `boot/stage2.asm`) starts with the signature `'BINF'`, a size field, and a version number (currently `1`). The structure is zeroed on every boot so downstream code can treat missing values as zero.
- CPU fields:
  - `bootinfo_cpu_vendor` stores the 12-byte CPUID vendor string.
  - `bootinfo_cpu_signature`, `bootinfo_cpu_features_edx`, and `bootinfo_cpu_features_ecx` mirror the `cpuid(1)` outputs.
  - `bootinfo_cpu_max_basic` / `bootinfo_cpu_max_ext` record the highest supported leaf; if the extended range reaches `0x80000004`, the 48-byte brand string is populated and `BOOTINFO_FLAG_CPU_BRAND` is set.
  - `bootinfo_cpu_core_count` is copied from the SMP enumeration so the kernel doesn’t need to reparse the MADT to get a logical core count.
- SMBIOS fields:
  - The loader scans the BIOS window for the `_SM_` anchor. When a valid checksum is found, `bootinfo_smbios_phys` and `bootinfo_smbios_len` capture the table location and reported length while `BOOTINFO_FLAG_SMBIOS` is raised.
  - These pointers are raw physical addresses (identity-mapped under 2 MiB) so the kernel can immediately parse SMBIOS without rescan.
- Future hardware summaries (PCI, EC, etc.) can extend the structure; the size/version fields let later kernels detect new additions safely.
- Disk fields:
  - `bootinfo_disk_count` caps at `BOOTINFO_MAX_DISKS` (currently 16). Each entry in `bootinfo_disks` is 32 bytes: `{iface (0=BIOS,1=UEFI), drive_id, flags, handle[63:0], total_sectors[63:0], bytes_per_sector, reserved}`.
  - BIOS enumeration issues INT 13h `AH=48h` requests for drives `0x80`..`0x80+MAX_BIOS_DISKS`. When successful, the returned EDD info/bytes-per-sector land in the BootInfo entry with `BOOTINFO_DISK_FLAG_EDD` set.
  - UEFI loaders can supply their own disk list inside the firmware context (the pointer at `DISK_LIST_PTR` should reference `{count,u32 entry_size, entries[]}` where each entry already matches the BootInfo layout). Stage 2 copies those entries directly after the BIOS ones.

## Contribution Rules

- Never hardcode file paths
- Do not modify scripts without testing them
- Makefiles must remain POSIX-compliant
- The bootloader must always compile without warnings
- All changes must remain compatible with a clean Ubuntu install

## Notes

This branch only contains the bootloader logic. Kernel and OS layers are not part of this tree.
