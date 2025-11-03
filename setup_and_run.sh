#!/usr/bin/env bash
set -euo pipefail

# ---------- Config ----------
TARGET="x86_64-elf"
PREFIX="$HOME/opt/cross"
PATH="$PREFIX/bin:$PATH"

# ---------- Helpers ----------
need() { command -v "$1" >/dev/null 2>&1 || { echo "Manquant: $1"; return 1; }; }
fail_missing() { echo "Erreur: dépendances manquantes. Installe-les puis relance."; exit 1; }

# ---------- Déps système ----------
echo "[*] Vérif/installation dépendances système"
if command -v apt >/dev/null 2>&1; then
  sudo apt update -y
  sudo apt install -y build-essential make bison flex libgmp3-dev libmpfr-dev libmpc-dev texinfo \
                      qemu-system-x86 xorriso nasm git xxd cpio
else
  echo "Apt non détecté. Installe équivalents (incluant xxd)."
fi

# ---------- Check outils ----------
echo "[*] Vérif outils requis"
MIS=0
for b in make nasm xorriso qemu-system-x86_64 git xxd; do need "$b" || MIS=1; done
[ $MIS -eq 1 ] && fail_missing

# ---------- Cross-compiler ----------
if ! command -v "${TARGET}-gcc" >/dev/null 2>&1; then
  echo "[*] Cross-compiler ${TARGET}-gcc absent -> construction (réf. OSDev)"
  mkdir -p "$HOME/src" && cd "$HOME/src"
  if [ ! -d "binutils-"* ] || [ ! -d "gcc-"* ]; then
    echo "Télécharge binutils-<ver> et gcc-<ver> dans $HOME/src (suivant OSDev), puis relance."
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
fi

# ---------- Init ----------
cd "$(dirname "$0")"

# ---------- Construire initrd.cpio ----------
echo "[*] Construction initrd.cpio (animations/ + /bin /etc /home)"
rm -rf initrd_root || true
mkdir -p initrd_root/animations initrd_root/bin initrd_root/etc initrd_root/home

# Copier animations
mkdir -p animations
if compgen -G 'animations/*.tga' > /dev/null; then
  cp -a animations/*.tga initrd_root/animations/ 2>/dev/null || true
fi

# Générer /etc/passwd et /etc/shadow simples si absents
if [ ! -f initrd_root/etc/passwd ]; then
  cat > initrd_root/etc/passwd <<'EOF'
root:x:0:0:root:/root:/bin/sh
user:x:1000:1000:user:/home/user:/bin/sh
EOF
fi

if [ ! -f initrd_root/etc/shadow ]; then
  SALT=$(head -c 8 /dev/urandom | xxd -p 2>/dev/null || echo "somesalt")
  # mot de passe par défaut: nova
  HASH=$(printf "%s" "${SALT}nova" | sha256sum | awk '{print $1}')
  cat > initrd_root/etc/shadow <<EOF
root:${HASH}:${SALT}:0:0:0:0
user:${HASH}:${SALT}:0:0:0:0
EOF
fi

# Construire /bin/init utilisateur minimal (NASM)
if [ -f userland/init.asm ]; then
  echo "[*] Build userland /bin/init"
  nasm -f elf64 -g -F dwarf userland/init.asm -o userland/init.o
  ld -m elf_x86_64 -nostdlib -static -T userland/link.ld userland/init.o -o userland/init
  cp -v userland/init initrd_root/bin/init
fi

# Construire archive CPIO newc avec NUL terminators
(
  cd initrd_root
  { find . -type d -print0; find . -type f -print0; } \
    | LC_ALL=C sort -z \
    | cpio --null -o -H newc --reproducible
) > initrd.cpio
echo "[*] initrd.cpio généré"

# ---------- Build kernel ----------
echo "[*] Build kernel (myos)"
make TOOLCHAIN_PREFIX="${TARGET}-"

# ---------- Limine (binaire) ----------
if [ ! -d "limine" ]; then
  echo "[*] Clone Limine binaire (v10.x)"
  git clone https://codeberg.org/Limine/Limine.git limine --branch=v10.x-binary --depth=1
fi
echo "[*] Build utilitaire limine"
make -C limine

# ---------- Préparer ISO ----------
echo "[*] Préparation ISO (BIOS+UEFI)"
rm -rf iso_root image.iso || true
mkdir -p iso_root/boot/limine
cp -v bin/myos iso_root/boot/
cp -v limine.conf limine/limine-bios.sys limine/limine-bios-cd.bin limine/limine-uefi-cd.bin iso_root/boot/limine/
mkdir -p iso_root/EFI/BOOT
cp -v limine/BOOTX64.EFI iso_root/EFI/BOOT/
cp -v limine/BOOTIA32.EFI iso_root/EFI/BOOT/
cp -v initrd.cpio iso_root/

xorriso -as mkisofs -R -r -J -b boot/limine/limine-bios-cd.bin \
  -no-emul-boot -boot-load-size 4 -boot-info-table -hfsplus \
  -apm-block-size 2048 --efi-boot boot/limine/limine-uefi-cd.bin \
  -efi-boot-part --efi-boot-image --protective-msdos-label \
  iso_root -o image.iso

./limine/limine bios-install image.iso

# ---------- Run QEMU ----------
echo "[*] Lancement QEMU"
exec qemu-system-x86_64 -cdrom image.iso -serial stdio
