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
                      qemu-system-x86 xorriso nasm git xxd
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

# ---------- Génération anim_data.c ----------
cd "$(dirname "$0")"
echo "[*] Génération src/anim_data.c depuis animations/(images_*.tga|image-*.tga)"

mkdir -p src
TMP=src/anim_data.c
{
  echo '#include <stdint.h>'
  echo '__attribute__((used)) const unsigned int ANIM_FRAMES_COUNT = 0;'
  echo '__attribute__((used)) const unsigned char *ANIM_FRAMES[] = { };'
  echo '__attribute__((used)) const unsigned int ANIM_FRAME_SIZES[] = { };'
} > "$TMP"

# Motifs acceptés et tri naturel
shopt -s nullglob
frames=(animations/images_*.tga animations/image-*.tga)
if ((${#frames[@]})); then
  mapfile -t FILES < <(printf '%s\n' "${frames[@]}" | LC_ALL=C sort -V)

  echo '#include <stdint.h>' > "$TMP"
  SYMS_DATA=()
  SYMS_SIZE=()
  i=0
  for f in "${FILES[@]}"; do
    sym="ANIM_IMG_${i}"
    # Génère le tableau const et ajoute une constante de compile
    xxd -i -n "$sym" "$f" \
      | sed -E '/^unsigned int .*_len =/d;s/^unsigned char /const unsigned char /' >> "$TMP"
    echo "enum { ${sym}_len = sizeof(${sym}) };" >> "$TMP"

    SYMS_DATA+=("${sym}")
    SYMS_SIZE+=("${sym}_len")
    i=$((i+1))
  done

  echo "__attribute__((used)) const unsigned int ANIM_FRAMES_COUNT = ${#SYMS_DATA[@]};" >> "$TMP"

  echo "__attribute__((used)) const unsigned char *ANIM_FRAMES[] = {" >> "$TMP"
  for s in "${SYMS_DATA[@]}"; do echo "  ${s}," >> "$TMP"; done
  echo "};" >> "$TMP"

  echo "__attribute__((used)) const unsigned int ANIM_FRAME_SIZES[] = {" >> "$TMP"
  for s in "${SYMS_SIZE[@]}"; do echo "  ${s}," >> "$TMP"; done
  echo "};" >> "$TMP"

  echo "[*] ${#SYMS_DATA[@]} frame(s) intégrée(s) dans src/anim_data.c"
else
  echo "[!] Aucune frame trouvée. Place des .tga dans animations/ (images_*.tga ou image-*.tga)."
fi

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

xorriso -as mkisofs -R -r -J -b boot/limine/limine-bios-cd.bin \
  -no-emul-boot -boot-load-size 4 -boot-info-table -hfsplus \
  -apm-block-size 2048 --efi-boot boot/limine/limine-uefi-cd.bin \
  -efi-boot-part --efi-boot-image --protective-msdos-label \
  iso_root -o image.iso

./limine/limine bios-install image.iso

# ---------- Run QEMU ----------
echo "[*] Lancement QEMU"
exec qemu-system-x86_64 -cdrom image.iso
