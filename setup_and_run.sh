#!/usr/bin/env bash
set -euo pipefail

# ---------- Config ----------
TARGET="x86_64-elf"
PREFIX="$HOME/opt/cross"
PATH="$PREFIX/bin:$PATH"

# ---------- Helpers ----------
need() { command -v "$1" >/dev/null 2>&1 || { echo "Manquant: $1"; return 1; }; }
fail_missing() { echo "Erreur: dépendances manquantes. Installe-les puis relance."; exit 1; }

# ---------- Déps système (OSDev) ----------
echo "[*] Vérif/installation dépendances système (build & tools liés aux tutos OSDev)"
if command -v apt >/dev/null 2>&1; then
  sudo apt update
  sudo apt install -y build-essential make bison flex libgmp3-dev libmpfr-dev libmpc-dev texinfo \
                      qemu-system-x86 xorriso nasm git
else
  echo "Apt non détecté. Installe les dépendances équivalentes selon ta distro (OSDev)."
fi

# ---------- Check outils ----------
echo "[*] Vérif outils requis"
MIS=0
for b in make nasm xorriso qemu-system-x86_64 git; do need "$b" || MIS=1; done
[ $MIS -eq 1 ] && fail_missing

# ---------- Cross-compiler (OSDev GCC Cross-Compiler) ----------
if ! command -v "${TARGET}-gcc" >/dev/null 2>&1; then
  echo "[*] Cross-compiler ${TARGET}-gcc absent -> construction (OSDev GCC Cross-Compiler)"
  mkdir -p "$HOME/src" && cd "$HOME/src"
  # NOTE: Télécharge manuellement binutils-<ver> et gcc-<ver> comme expliqué sur le wiki OSDev.
  # Exemple de répertoire:
  #   $HOME/src/binutils-<ver>  $HOME/src/gcc-<ver>
  if [ ! -d "binutils-"* ] || [ ! -d "gcc-"* ]; then
    echo "Télécharge binutils-<ver> et gcc-<ver> dans $HOME/src (conformément au wiki OSDev), puis relance."
    exit 1
  fi

  BINUTILS_DIR=$(echo binutils-*)
  GCC_DIR=$(echo gcc-*)

  mkdir -p build-binutils && cd build-binutils
  "../$BINUTILS_DIR/configure" --target="$TARGET" --prefix="$PREFIX" --with-sysroot --disable-nls --disable-werror
  make -j"$(nproc)"
  make install

  cd "$HOME/src"
  mkdir -p build-gcc && cd build-gcc
  "../$GCC_DIR/configure" --target="$TARGET" --prefix="$PREFIX" --disable-nls --enable-languages=c,c++ --without-headers
  make -j"$(nproc)" all-gcc
  make -j"$(nproc)" all-target-libgcc
  make install-gcc
  make install-target-libgcc
  echo "[*] Cross-compiler installé dans $PREFIX"
fi

cd "$(dirname "$0")"  # racine du projet

# ---------- Build kernel (Limine Bare Bones makefile) ----------
echo "[*] Build kernel (myos)"
make TOOLCHAIN_PREFIX="${TARGET}-"

# ---------- Récupérer et builder Limine (binaire) ----------
if [ ! -d "limine" ]; then
  echo "[*] Clone Limine binaire (v10.x)"
  git clone https://codeberg.org/Limine/Limine.git limine --branch=v10.x-binary --depth=1
fi
echo "[*] Build utilitaire limine"
make -C limine

# ---------- Préparer ISO (selon Limine Bare Bones) ----------
echo "[*] Préparation ISO (BIOS+UEFI)"
rm -rf iso_root image.iso || true
mkdir -p iso_root/boot/limine
cp -v bin/myos iso_root/boot/
cp -v limine.conf limine/limine-bios.sys limine/limine-bios-cd.bin limine/limine-uefi-cd.bin iso_root/boot/limine/
mkdir -p iso_root/EFI/BOOT
cp -v limine/BOOTX64.EFI iso_root/EFI/BOOT/
cp -v limine/BOOTIA32.EFI iso_root/EFI/BOOT/

xorriso -as mkisofs -R -r -J -b boot/limine/limine-bios-cd.bin \
  -no-emul-boot -boot-load-size 4 -boot-info-table -hfsplus \
  -apm-block-size 2048 --efi-boot boot/limine/limine-uefi-cd.bin \
  -efi-boot-part --efi-boot-image --protective-msdos-label \
  iso_root -o image.iso

./limine/limine bios-install image.iso

# ---------- Run QEMU ----------
echo "[*] Lancement QEMU"
exec qemu-system-x86_64 -cdrom image.iso
