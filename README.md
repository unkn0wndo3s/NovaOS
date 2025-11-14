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
  - Initializes all segment registers plus a 32-bit stack (`ESP = 0x9F000`) and builds the paging hierarchy required for a later jump to 64-bit long mode:
    - PML4/PDPT/PD/PT tables (eight 4 KiB pages) are zeroed and filled at runtime.
    - Identity map of the lowest 2 MiB keeps BIOS-visible memory reachable during transition.
    - Kernel window: maps `0xFFFFFFFF80000000-0xFFFFFFFF80200000` to physical `0x00200000` (2 MiB).
    - Bootloader window: maps `0xFFFFFFFF80200000` onward to the real-mode loader image at `0x00010000` (128 KiB).
  - Writes a confirmation string directly to VGA text memory after the paging structures are ready.
  - This is the natural place to add A20 enable logic, paging, and kernel loading.

The Stage 1 build depends on `build/stage2.inc`, which is generated automatically by `scripts/gen_stage2_inc.sh`. The script pads `stage2.bin` out to whole sectors and records how many sectors Stage 1 should request from the BIOS.

## Customisation Notes

- Extend Stage 2 freely; the helper script recalculates the sector count every build, so no manual constants are needed unless you change the load address.
- If Stage 2 grows beyond the first few sectors, ensure it still fits within the BIOS-readable area or add paging logic before switching to protected/long mode.
- The GDT is currently staged at physical address `0x00000500`; update `GDT_BASE` in `boot/stage2.asm` if you need a different location, and keep it below 1 MiB unless A20 is enabled.
- Paging structures live inside Stage 2 (see the `page_tables_start` block). If you relocate Stage 2, update `STAGE2_LOAD_SEG` to keep the physical addresses computed for CR3 valid. Expand the identity/kernel/boot mappings via the constants at the top of `boot/stage2.asm`.
- Keep Stage 1 within 512 bytes including the `0xAA55` signature; `nasm` plus the padding directive in `boot/stage1.asm` enforces this.

## Contribution Rules

- Never hardcode file paths
- Do not modify scripts without testing them
- Makefiles must remain POSIX-compliant
- The bootloader must always compile without warnings
- All changes must remain compatible with a clean Ubuntu install

## Notes

This branch only contains the bootloader logic. Kernel and OS layers are not part of this tree.
