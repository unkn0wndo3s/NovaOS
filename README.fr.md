Français | [English](README.md)

## Nova OS — Kernel minimal avec Limine

Nova OS est un kernel x86_64 minimal basé sur Limine, fourni avec une chaîne de build pour générer une image ISO amorçable hybride BIOS/UEFI et l’exécuter sous QEMU. Le projet suit une structure simple et s’appuie sur LLVM/Clang.

### Aperçu
- **Bootloader**: Limine (BIOS + UEFI)
- **Arch cible**: x86_64
- **Toolchain**: LLVM (clang, ld.lld, llvm-ar, llvm-objcopy)
- **Affichage**: Framebuffer (dessin d’un fond dégradé et d’un carré avec bordure + texte “NOVA OS”)

---

### Prérequis
- LLVM/Clang (clang, ld.lld, llvm-ar, llvm-objcopy dans le PATH)
- xorriso (pour la création de l’ISO hybride)
- QEMU (qemu-system-x86_64)
- Limine (déjà inclus dans `Limine/` et référencé par les scripts)
- OVMF (facultatif, uniquement pour tester UEFI avec QEMU si vous utilisez la cible UEFI dédiée)

Sous Windows, le script `build_and_run.bat` suppose que `clang`, `ld.lld`, `xorriso`, `qemu-system-x86_64` et `Limine\limine.exe` sont accessibles dans le PATH.

---

### Installation rapide des outils

- **Windows (PowerShell/Chocolatey)**
```powershell
choco install llvm qemu xorriso -y
# Assurez-vous que Limine est présent dans le dossier `Limine/` du projet
```

- **Linux (Debian/Ubuntu)**
```bash
sudo apt update
sudo apt install -y clang lld llvm xorriso qemu-system-x86 ovmf
```

- **macOS (Homebrew)**
```bash
brew install llvm xorriso qemu
# Ajoutez éventuellement llvm au PATH selon votre installation
```

---

### Construire et exécuter

- **Windows (recommandé sur cette base de projet)**
```powershell
./build_and_run.bat
```
Cela va:
- compiler `kernel/main.c` en objet avec les bons flags freestanding;
- lier avec `ld.lld` selon `kernel/linker.ld` pour produire `build/kernel.elf`;
- copier les fichiers nécessaires dans `iso_root/`;
- créer une ISO hybride via `xorriso` dans `build/NovaOS.iso`;
- installer Limine sur l’ISO (BIOS);
- lancer QEMU (BIOS) avec la sortie série sur la console.

- **Linux/macOS**
```bash
make           # génère l’ISO
make run-bios  # exécute sous QEMU en mode BIOS
make run-uefi  # exécute sous QEMU en mode UEFI (nécessite OVMF)
```

Par défaut, la cible `all` appelle `iso`. L’image finale est produite dans `build/NovaOS.iso`.

---

### Arborescence du projet
```text
build/              # artefacts de build (kernel.elf, ISO)
iso_root/           # contenu de l’ISO (copié/écrits par les scripts)
kernel/
  ├─ main.c         # point d’entrée du kernel (_start)
  └─ linker.ld      # script de lien (x86_64, high-half)
Limine/             # binaires/EFI Limine utilisés pour l’ISO
Makefile            # build (Linux/macOS), run BIOS/UEFI via QEMU
build_and_run.bat   # build & run (Windows)
limine.conf         # configuration Limine incluse dans l’ISO
```

---

### Détails techniques clés
- Le kernel est lié en high-half à `0xffffffff80000000` (voir `kernel/linker.ld`).
- Les sections `.stivale2hdr` et `.liminehdr` sont conservées pour la compatibilité avec Limine.
- Compilation freestanding: `-ffreestanding -fno-stack-protector -fno-pic -fno-pie -mno-red-zone -mcmodel=kernel`.
- Le framebuffer est demandé via les requêtes Limine et utilisé pour dessiner une scène 2D minimale.

---

### Personnaliser et développer
1) Modifiez le rendu dans `kernel/main.c` (dessin du fond, du carré, du texte).
2) Recompilez et relancez l’ISO:
   - Windows: `build_and_run.bat`
   - Linux/macOS: `make run-bios` (ou `make run-uefi`)

Si vous ajoutez des fichiers C supplémentaires, ajustez le `Makefile` et/ou le script `.bat` pour compiler et lier tous les objets nécessaires.

---

### Nettoyer

- **Linux/macOS**
```bash
make clean
```

Sous Windows, supprimez manuellement `build/` et `iso_root/` si nécessaire.

---

### Dépannage
- **xorriso introuvable**: installez `xorriso` et vérifiez qu’il est dans le PATH.
- **QEMU introuvable**: installez `qemu-system-x86_64` et vérifiez le PATH.
- **OVMF requis pour UEFI**: pour `make run-uefi`, ajustez le chemin vers `OVMF_CODE.fd` dans le `Makefile` si votre distribution diffère:
  ```
  qemu-system-x86_64 ... -bios /usr/share/OVMF/OVMF_CODE.fd
  ```
- **Clang/LLD non trouvés**: installez LLVM/Clang et assurez-vous que `clang` et `ld.lld` sont accessibles.
- **Problèmes d’autorisations sous Windows**: lancez PowerShell/Terminal en tant qu’administrateur si nécessaire.

---

### Licence et crédits
- Le répertoire `Limine/` contient la licence de Limine (`LICENSE`).
- Ce projet est inspiré des exemples bare-bones Limine. Marques et droits d’auteur réservés à leurs propriétaires respectifs.


