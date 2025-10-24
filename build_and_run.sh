#!/bin/bash
set -e  # Exit on any error

# ===== Nova OS Build & Run (Limine 10.x + libnsgif) =====

# ---- Config ----
PROJECT_NAME="NovaOS"
BUILD_DIR="build"
ISO_DIR="iso_root"
KERNEL_ELF="$BUILD_DIR/kernel.elf"
ISO_IMAGE="$BUILD_DIR/$PROJECT_NAME.iso"
LIMINE_DIR="Limine"
INC_DIR="kernel/include"
BITS_DIR="kernel/include/bits"
LOADER_DIR="kernel/loader"
TP_DIR="third_party"
NSGIF_DIR="$TP_DIR/libnsgif"

MUSL_VER="1.2.5"
MUSL_ZIP="$BUILD_DIR/musl-$MUSL_VER.zip"

# ---- Tools ----
CC="clang"
LD="ld.lld"
ARCH_TARGET="x86_64-unknown-elf"
QEMU="qemu-system-x86_64"
XORRISO="xorriso"
GIT="git"

echo "[*] Prep environment..."

# ---- Detect package managers ----
HAVE_APT=""
HAVE_SNAP=""
command -v apt >/dev/null 2>&1 && HAVE_APT="1"
command -v snap >/dev/null 2>&1 && HAVE_SNAP="1"

# ===== LLVM =====
if ! command -v $CC >/dev/null 2>&1; then
  echo "[!] LLVM not found, installing..."
  if [ -n "$HAVE_APT" ]; then
    sudo apt update && sudo apt install -y clang lld
  elif [ -n "$HAVE_SNAP" ]; then
    sudo snap install clang --classic
  else
    echo "[X] No package manager. Install LLVM and rerun."
    exit 1
  fi
fi

if ! command -v $LD >/dev/null 2>&1; then
  echo "[!] ld.lld not found, installing..."
  if [ -n "$HAVE_APT" ]; then
    sudo apt update && sudo apt install -y lld
  else
    echo "[X] Install lld manually and rerun."
    exit 1
  fi
fi

# ===== QEMU =====
if ! command -v $QEMU >/dev/null 2>&1; then
  echo "[!] QEMU not found, installing..."
  if [ -n "$HAVE_APT" ]; then
    sudo apt update && sudo apt install -y qemu-system-x86
  elif [ -n "$HAVE_SNAP" ]; then
    sudo snap install qemu
  else
    echo "[X] No package manager. Install QEMU and rerun."
    exit 1
  fi
fi

# ===== xorriso =====
if ! command -v $XORRISO >/dev/null 2>&1; then
  echo "[!] xorriso not found, installing..."
  if [ -n "$HAVE_APT" ]; then
    sudo apt update && sudo apt install -y xorriso
  else
    echo "[X] Install xorriso manually and rerun."
    exit 1
  fi
fi

# ===== git =====
if ! command -v $GIT >/dev/null 2>&1; then
  echo "[!] Git not found, installing..."
  if [ -n "$HAVE_APT" ]; then
    sudo apt update && sudo apt install -y git
  elif [ -n "$HAVE_SNAP" ]; then
    sudo snap install git --classic
  else
    echo "[X] No package manager. Install Git and rerun."
    exit 1
  fi
fi

# ===== Limine binaries =====
if [ ! -f "$LIMINE_DIR/limine-bios.sys" ]; then
  echo "[X] Missing Limine binaries in $LIMINE_DIR"
  echo "    Need: limine-bios.sys, limine-bios-cd.bin, limine-uefi-cd.bin, BOOTX64.EFI, limine"
  exit 1
fi

# ===== Clean dirs =====
[ -d "$BUILD_DIR" ] && rm -rf "$BUILD_DIR"
[ -d "$ISO_DIR" ] && rm -rf "$ISO_DIR"

mkdir -p "$BUILD_DIR"
mkdir -p "$ISO_DIR"
mkdir -p "$ISO_DIR/boot/limine"
mkdir -p "$ISO_DIR/EFI/BOOT"
mkdir -p "$ISO_DIR/loader"
[ ! -d "$INC_DIR" ] && mkdir -p "$INC_DIR"
[ ! -d "$BITS_DIR" ] && mkdir -p "$BITS_DIR"
[ ! -d "$TP_DIR" ] && mkdir -p "$TP_DIR"

# ===== musl headers (stdint.h, etc.) =====
if [ ! -f "$INC_DIR/stdlib.h" ]; then
  echo "[.] Downloading musl headers v$MUSL_VER..."
  wget -q "https://codeload.github.com/bminor/musl/zip/refs/tags/v$MUSL_VER" -O "$MUSL_ZIP"
  if [ ! -f "$MUSL_ZIP" ]; then
    echo "[X] musl download failed"
    exit 1
  fi
  unzip -q "$MUSL_ZIP" -d "$BUILD_DIR"
  MUSL_DIR=$(find "$BUILD_DIR" -name "musl-*$MUSL_VER*" -type d | head -1)
  if [ -z "$MUSL_DIR" ]; then
    echo "[X] musl extract dir not found"
    exit 1
  fi
  cp -r "$MUSL_DIR/include/"* "$INC_DIR/"
  [ -d "$MUSL_DIR/arch/generic/bits" ] && cp -r "$MUSL_DIR/arch/generic/bits/"* "$BITS_DIR/"
  [ -d "$MUSL_DIR/arch/x86_64/bits" ] && cp -r "$MUSL_DIR/arch/x86_64/bits/"* "$BITS_DIR/"
fi

if [ ! -f "$INC_DIR/bits/alltypes.h" ]; then
  echo "[!] bits/alltypes.h missing; fetching prebuilt headers..."
  MUSL_TOOL_URL="https://musl.cc/x86_64-linux-musl-native.tgz"
  MUSL_TOOL_TGZ="$BUILD_DIR/x86_64-linux-musl-native.tgz"
  wget -q "$MUSL_TOOL_URL" -O "$MUSL_TOOL_TGZ"
  mkdir -p "$BUILD_DIR/_musl_tmp"
  tar -xf "$MUSL_TOOL_TGZ" -C "$BUILD_DIR/_musl_tmp"
  cp -r "$BUILD_DIR/_musl_tmp/x86_64-linux-musl-native/include/"* "$INC_DIR/"
  rm -rf "$BUILD_DIR/_musl_tmp"
  if [ ! -f "$INC_DIR/bits/alltypes.h" ]; then
    echo "[X] still missing alltypes.h"
    exit 1
  fi
fi

echo "[=] Using C headers in $INC_DIR"

# ===== libnsgif (sparse checkout Linux-safe, no test/ paths) =====
# Si un ancien clone foireux existe -> purge
if [ -f "$NSGIF_DIR/include/nsgif.h" ]; then
  echo "[=] libnsgif ready"
else
  [ -d "$NSGIF_DIR" ] && rm -rf "$NSGIF_DIR"
  mkdir -p "$TP_DIR" 2>/dev/null || true

  echo "[*] Cloning libnsgif (no-checkout)"
  $GIT clone --depth 1 --no-checkout https://github.com/netsurf-browser/libnsgif "$NSGIF_DIR"
  if [ $? -ne 0 ]; then
    echo "[X] git clone libnsgif failed"
    exit 1
  fi

  echo "[*] Checking out libnsgif subset (include/, src/, COPYING, README.md)"
  $GIT -C "$NSGIF_DIR" rev-parse --verify origin/HEAD >/dev/null 2>&1
  if [ $? -ne 0 ]; then
    echo "[X] libnsgif origin/HEAD not found"
    exit 1
  fi
  $GIT -C "$NSGIF_DIR" checkout --force --quiet origin/HEAD -- include src COPYING README.md
  if [ $? -ne 0 ]; then
    echo "[X] git selective checkout failed"
    exit 1
  fi

  echo "[=] libnsgif ready"
fi

# ===== Verify GIF module =====
if [ ! -f "$LOADER_DIR/stage1.gif" ]; then
  echo "[X] Missing $LOADER_DIR/stage1.gif"
  exit 1
fi

# ===== Compile kernel + libnsgif =====
echo "[*] Compile kernel..."
$CC -target $ARCH_TARGET -std=gnu11 -O2 -pipe -Wall -Wextra -ffreestanding -fno-stack-protector -fno-pic -fno-pie -mno-red-zone -m64 -mcmodel=kernel \
  -I "$LIMINE_DIR" -I "$INC_DIR" -I "$NSGIF_DIR/include" \
  -fno-asynchronous-unwind-tables -fno-exceptions -c kernel/main.c -o "$BUILD_DIR/kernel.o"
if [ $? -ne 0 ]; then exit 1; fi

echo "[*] Compile runtime..."
$CC -target $ARCH_TARGET -std=gnu11 -O2 -ffreestanding -fno-stack-protector -fno-pic -fno-pie -mno-red-zone -m64 -mcmodel=kernel \
  -I "$INC_DIR" -c kernel/runtime.c -o "$BUILD_DIR/runtime.o"
if [ $? -ne 0 ]; then exit 1; fi

echo "[*] Compile libnsgif..."
$CC -target $ARCH_TARGET -std=gnu11 -O2 -ffreestanding -fno-stack-protector -fno-pic -fno-pie -mno-red-zone -m64 -mcmodel=kernel \
  -I "$INC_DIR" -I "$NSGIF_DIR/include" -c "$NSGIF_DIR/src/gif.c" -o "$BUILD_DIR/gif.o"
if [ $? -ne 0 ]; then exit 1; fi
$CC -target $ARCH_TARGET -std=gnu11 -O2 -ffreestanding -fno-stack-protector -fno-pic -fno-pie -mno-red-zone -m64 -mcmodel=kernel \
  -I "$INC_DIR" -I "$NSGIF_DIR/include" -c "$NSGIF_DIR/src/lzw.c" -o "$BUILD_DIR/lzw.o"
if [ $? -ne 0 ]; then exit 1; fi

# ===== Link kernel =====
echo "[*] Linking kernel..."
$LD -m elf_x86_64 -o "$KERNEL_ELF" -nostdlib -z max-page-size=0x1000 -T kernel/linker.ld \
  "$BUILD_DIR/kernel.o" "$BUILD_DIR/runtime.o" "$BUILD_DIR/gif.o" "$BUILD_DIR/lzw.o"
if [ $? -ne 0 ]; then exit 1; fi

# ===== Prepare ISO contents =====
echo "[*] Preparing ISO contents..."
cp "$KERNEL_ELF" "$ISO_DIR/kernel.elf"
cp limine.conf "$ISO_DIR/limine.conf"
cp "$LIMINE_DIR/limine-bios.sys" "$ISO_DIR/"
cp "$LIMINE_DIR/limine-bios-cd.bin" "$ISO_DIR/"
cp "$LIMINE_DIR/limine-uefi-cd.bin" "$ISO_DIR/"
cp "$LIMINE_DIR/BOOTX64.EFI" "$ISO_DIR/EFI/BOOT/"
cp "$LOADER_DIR/stage1.gif" "$ISO_DIR/loader/stage1.gif"

# ===== Create ISO =====
echo "[*] Creating ISO image..."
$XORRISO -as mkisofs -b limine-bios-cd.bin -no-emul-boot -boot-load-size 4 -boot-info-table --efi-boot limine-uefi-cd.bin -efi-boot-part --efi-boot-image --protective-msdos-label "$ISO_DIR" -o "$ISO_IMAGE"
if [ $? -ne 0 ]; then exit 1; fi

# ===== Install Limine (BIOS) =====
if [ -f "$LIMINE_DIR/limine" ]; then
  echo "[*] Installing Limine BIOS..."
  "$LIMINE_DIR/limine" bios-install "$ISO_IMAGE" 2>&1 || echo "[!] Limine BIOS install failed, continuing anyway..."
else
  echo "[!] Limine binary not found, skipping BIOS install"
fi
echo "[OK] ISO created at $ISO_IMAGE"

# ===== List ISO =====
echo "[*] ISO contents:"
$XORRISO -indev "$ISO_IMAGE" -ls / 2>/dev/null || echo "[!] Could not list ISO contents"
echo "[*] Loader directory:"
$XORRISO -indev "$ISO_IMAGE" -ls /loader 2>/dev/null || echo "[!] Could not list loader directory"

# ===== Run QEMU =====
echo "[*] Running QEMU..."
echo "[*] Press Ctrl+C to stop QEMU"
$QEMU -m 256M -cdrom "$ISO_IMAGE" -boot d -serial stdio -no-reboot -no-shutdown -vga std

exit 0
