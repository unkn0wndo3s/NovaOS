English | [Français](README.fr.md)

## Nova OS — Minimal kernel with Limine

Nova OS is a minimal x86_64 kernel based on Limine, with a build chain to generate a hybrid BIOS/UEFI bootable ISO and run it under QEMU. The project uses a simple structure and relies on LLVM/Clang.

### Overview
- **Bootloader**: Limine (BIOS + UEFI)
- **Target arch**: x86_64
- **Toolchain**: LLVM (clang, ld.lld, llvm-ar, llvm-objcopy)
- **Display**: Framebuffer (draws a gradient background, a bordered square, and “NOVA OS” text)

---

### Requirements
- LLVM/Clang (clang, ld.lld, llvm-ar, llvm-objcopy in PATH)
- xorriso (to build the hybrid ISO)
- QEMU (qemu-system-x86_64)
- Limine (included in `Limine/` and referenced by scripts)
- OVMF (optional, only for UEFI testing with QEMU)

On Windows, `build_and_run.bat` expects `clang`, `ld.lld`, `xorriso`, `qemu-system-x86_64` and `Limine\limine.exe` in PATH.

---

### Quick tool installation

- **Windows (PowerShell/Chocolatey)**
```powershell
choco install llvm qemu xorriso -y
# Ensure Limine is present in the project `Limine/` folder
```

- **Linux (Debian/Ubuntu)**
```bash
sudo apt update
sudo apt install -y clang lld llvm xorriso qemu-system-x86 ovmf
```

- **macOS (Homebrew)**
```bash
brew install llvm xorriso qemu
# Optionally add llvm to PATH depending on your setup
```

---

### Build and run

- **Windows (recommended for this project)**
```powershell
./build_and_run.bat
```
This will:
- compile `kernel/main.c` as freestanding with proper flags;
- link with `ld.lld` using `kernel/linker.ld` to produce `build/kernel.elf`;
- copy required files into `iso_root/`;
- create a hybrid ISO via `xorriso` at `build/NovaOS.iso`;
- install Limine to the ISO (BIOS);
- launch QEMU (BIOS) with serial output to the console.

- **Linux/macOS**
```bash
make           # build the ISO
make run-bios  # run under QEMU in BIOS mode
make run-uefi  # run under QEMU in UEFI mode (requires OVMF)
```

By default, the `all` target calls `iso`. The final image is produced at `build/NovaOS.iso`.

---

### Project layout
```text
build/              # build artifacts (kernel.elf, ISO)
iso_root/           # ISO contents (populated by scripts)
kernel/
  ├─ main.c         # kernel entry point (_start)
  └─ linker.ld      # linker script (x86_64, high-half)
Limine/             # Limine binaries/EFI used for the ISO
Makefile            # build (Linux/macOS), run BIOS/UEFI via QEMU
build_and_run.bat   # build & run (Windows)
limine.conf         # Limine configuration included in the ISO
```

---

### Key technical notes
- The kernel is linked in the high-half at `0xffffffff80000000` (see `kernel/linker.ld`).
- `.stivale2hdr` and `.liminehdr` sections are retained for Limine compatibility.
- Freestanding build: `-ffreestanding -fno-stack-protector -fno-pic -fno-pie -mno-red-zone -mcmodel=kernel`.
- The framebuffer is requested via Limine and used to draw a minimal 2D scene.

---

### Customize and develop
1) Modify rendering in `kernel/main.c` (background, square, text).
2) Rebuild and run the ISO:
   - Windows: `build_and_run.bat`
   - Linux/macOS: `make run-bios` (or `make run-uefi`)

If you add more C files, update the `Makefile` and/or the `.bat` script to compile and link all required objects.

---

### Clean

- **Linux/macOS**
```bash
make clean
```

On Windows, remove `build/` and `iso_root/` manually if needed.

---

### Troubleshooting
- **xorriso not found**: install `xorriso` and ensure it is in PATH.
- **QEMU not found**: install `qemu-system-x86_64` and ensure PATH is set.
- **OVMF required for UEFI**: for `make run-uefi`, adjust the `OVMF_CODE.fd` path in `Makefile` if your distro differs:
  ```
  qemu-system-x86_64 ... -bios /usr/share/OVMF/OVMF_CODE.fd
  ```
- **Clang/LLD missing**: install LLVM/Clang and ensure `clang` and `ld.lld` are available.
- **Windows permission issues**: run PowerShell/Terminal as Administrator if needed.

---

### License & credits
- The `Limine/` directory contains Limine’s license (`LICENSE`).
- This project is inspired by Limine bare-bones examples. Trademarks and copyrights belong to their respective owners.


