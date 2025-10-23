@echo off
setlocal EnableExtensions
cd /d "%~dp0"

REM ===== Nova OS Build & Run (Limine 10.1.1) =====

REM ---- Config ----
set "PROJECT_NAME=NovaOS"
set "BUILD_DIR=build"
set "ISO_DIR=iso_root"
set "KERNEL_ELF=%BUILD_DIR%\kernel.elf"
set "ISO_IMAGE=%BUILD_DIR%\%PROJECT_NAME%.iso"
set "LIMINE_DIR=Limine"
set "INC_DIR=kernel\include"
set "BITS_DIR=kernel\include\bits"
set "LOADER_DIR=kernel\loader"
set "MUSL_VER=1.2.5"
set "MUSL_ZIP=%BUILD_DIR%\musl-%MUSL_VER%.zip"

REM ---- Tools ----
set "CC=clang"
set "LD=ld.lld"
set "ARCH_TARGET=x86_64-unknown-elf"
set "QEMU=qemu-system-x86_64"
set "XORRISO=%USERPROFILE%\scoop\apps\msys2\current\usr\bin\xorriso.exe"

echo [*] Prep environment...

REM ---- Detect package managers ----
set "HAVE_WINGET="
set "HAVE_SCOOP="
where winget >nul 2>nul && set "HAVE_WINGET=1"
where scoop  >nul 2>nul && set "HAVE_SCOOP=1"

REM ===== LLVM =====
where %CC% >nul 2>nul
if %ERRORLEVEL% NEQ 0 (
  echo [!] LLVM not found, installing...
  if defined HAVE_WINGET ( winget install -e --id LLVM.LLVM -h ) else if defined HAVE_SCOOP ( scoop install llvm ) else ( echo [X] No pkg mgr. Install LLVM and rerun. & exit /b 1 )
)
where %LD% >nul 2>nul
if %ERRORLEVEL% NEQ 0 (
  echo [!] ld.lld not found, installing...
  if defined HAVE_WINGET ( winget install -e --id LLVM.LLVM -h ) else if defined HAVE_SCOOP ( scoop install llvm ) else ( echo [X] No pkg mgr. Install LLVM and rerun. & exit /b 1 )
)

REM ===== QEMU =====
where %QEMU% >nul 2>nul
if %ERRORLEVEL% NEQ 0 (
  echo [!] QEMU not found, installing...
  if defined HAVE_WINGET ( winget install -e --id qemu.qemu -h ) else if defined HAVE_SCOOP ( scoop install qemu ) else ( echo [X] No pkg mgr. Install QEMU and rerun. & exit /b 1 )
)

REM ===== xorriso =====
if exist "%XORRISO%" (
  echo [=] Using xorriso: %XORRISO%
) else (
  where xorriso >nul 2>nul
  if %ERRORLEVEL% EQU 0 (
    set "XORRISO=xorriso"
    echo [=] Using system xorriso
  ) else (
    echo [!] xorriso not found.
    if defined HAVE_SCOOP (
      echo [.] Installing MSYS2 then xorriso...
      scoop install msys2
      "%USERPROFILE%\scoop\apps\msys2\current\usr\bin\bash.exe" -lc "pacman -S --noconfirm xorriso"
      if exist "%USERPROFILE%\scoop\apps\msys2\current\usr\bin\xorriso.exe" (
        set "XORRISO=%USERPROFILE%\scoop\apps\msys2\current\usr\bin\xorriso.exe"
        echo [=] Using MSYS2 xorriso: %XORRISO%
      ) else (
        echo [X] xorriso install failed. Install manually and rerun.
        exit /b 1
      )
    ) else if defined HAVE_WINGET (
      echo [!] Install MSYS2 via winget, then in MSYS2: pacman -S xorriso
      winget install -e --id MSYS2.MSYS2 -h
      exit /b 1
    ) else (
      echo [X] No xorriso available. Install MSYS2+xorriso.
      exit /b 1
    )
  )
)

REM ===== Limine binaries =====
if not exist "%LIMINE_DIR%\limine-bios.sys" (
  echo [X] Missing Limine binaries in %LIMINE_DIR%
  echo     Need: limine-bios.sys, limine-bios-cd.bin, limine-uefi-cd.bin, BOOTX64.EFI, limine.exe
  exit /b 1
)

REM ===== Clean =====
if exist "%BUILD_DIR%" rmdir /s /q "%BUILD_DIR%"
if exist "%ISO_DIR%"   rmdir /s /q "%ISO_DIR%"

mkdir "%BUILD_DIR%" >nul
mkdir "%ISO_DIR%" >nul
mkdir "%ISO_DIR%\boot\limine" >nul
mkdir "%ISO_DIR%\EFI\BOOT" >nul
mkdir "%ISO_DIR%\limine" >nul
mkdir "%ISO_DIR%\loader" >nul
if not exist "%INC_DIR%"  mkdir "%INC_DIR%"
if not exist "%BITS_DIR%" mkdir "%BITS_DIR%"

REM ===== musl headers (pour <stdint.h>, etc.) =====
if not exist "%INC_DIR%\stdlib.h" (
  echo [.] Downloading musl headers v%MUSL_VER%...
  powershell -NoProfile -ExecutionPolicy Bypass -Command "Invoke-WebRequest -UseBasicParsing -Uri 'https://codeload.github.com/bminor/musl/zip/refs/tags/v%MUSL_VER%' -OutFile '%MUSL_ZIP%'"
  if not exist "%MUSL_ZIP%" ( echo [X] musl download failed & exit /b 1 )
  powershell -NoProfile -ExecutionPolicy Bypass -Command "Expand-Archive -Path '%MUSL_ZIP%' -DestinationPath '%BUILD_DIR%' -Force"
  for /d %%D in ("%BUILD_DIR%\musl-*%MUSL_VER%*") do set "MUSL_DIR=%%D"
  if not defined MUSL_DIR ( echo [X] musl extract dir not found & exit /b 1 )
  xcopy /E /I /Y "%MUSL_DIR%\include\" "%INC_DIR%\" >nul
  if exist "%MUSL_DIR%\arch\generic\bits\"  xcopy /E /I /Y "%MUSL_DIR%\arch\generic\bits\"  "%BITS_DIR%\" >nul
  if exist "%MUSL_DIR%\arch\x86_64\bits\"   xcopy /E /I /Y "%MUSL_DIR%\arch\x86_64\bits\" "%BITS_DIR%\" >nul
)
if not exist "%INC_DIR%\bits\alltypes.h" (
  echo [!] bits\alltypes.h missing; fetching prebuilt headers...
  set "MUSL_TOOL_URL=https://musl.cc/x86_64-linux-musl-native.tgz"
  set "MUSL_TOOL_TGZ=%BUILD_DIR%\x86_64-linux-musl-native.tgz"
  powershell -NoProfile -ExecutionPolicy Bypass -Command "Invoke-WebRequest -UseBasicParsing -Uri '%MUSL_TOOL_URL%' -OutFile '%MUSL_TOOL_TGZ%'"
  mkdir "%BUILD_DIR%\_musl_tmp"
  tar -xf "%MUSL_TOOL_TGZ%" -C "%BUILD_DIR%\_musl_tmp%"
  xcopy /E /I /Y "%BUILD_DIR%\_musl_tmp%\x86_64-linux-musl-native\include\" "%INC_DIR%\" >nul
  rmdir /s /q "%BUILD_DIR%\_musl_tmp%" >nul 2>nul
  if not exist "%INC_DIR%\bits\alltypes.h" ( echo [X] still missing alltypes.h & exit /b 1 )
)

echo [=] Using C headers in %INC_DIR%

REM ===== Vérif GIF (on utilise désormais le 1er module seulement) =====
if not exist "%LOADER_DIR%\stage1.gif" ( echo [X] Missing %LOADER_DIR%\stage1.gif & exit /b 1 )
if not exist "%LOADER_DIR%\stage2.gif" ( echo [X] Missing %LOADER_DIR%\stage2.gif & exit /b 1 )
if not exist "%LOADER_DIR%\stage3.gif" ( echo [X] Missing %LOADER_DIR%\stage3.gif & exit /b 1 )

REM ===== Compile kernel =====
echo [*] Compile kernel...
"%CC%" -target %ARCH_TARGET% -std=gnu11 -O2 -pipe -Wall -Wextra -ffreestanding -fno-stack-protector -fno-pic -fno-pie -mno-red-zone -m64 -mcmodel=kernel -I "%LIMINE_DIR%" -I "%INC_DIR%" -fno-asynchronous-unwind-tables -fno-exceptions -c kernel\main.c -o "%BUILD_DIR%\kernel.o"
if %ERRORLEVEL% NEQ 0 exit /b 1

REM ===== Link kernel =====
echo [*] Linking kernel...
"%LD%" -m elf_x86_64 -o "%KERNEL_ELF%" -nostdlib -z max-page-size=0x1000 -T kernel\linker.ld "%BUILD_DIR%\kernel.o"
if %ERRORLEVEL% NEQ 0 exit /b 1

REM ===== Prepare ISO contents =====
echo [*] Preparing ISO contents...
copy /Y "%KERNEL_ELF%" "%ISO_DIR%\kernel.elf" >nul
copy /Y limine.conf "%ISO_DIR%\limine.conf" >nul
copy /Y "%LIMINE_DIR%\limine-bios.sys"    "%ISO_DIR%\" >nul
copy /Y "%LIMINE_DIR%\limine-bios-cd.bin" "%ISO_DIR%\" >nul
copy /Y "%LIMINE_DIR%\limine-uefi-cd.bin" "%ISO_DIR%\" >nul
copy /Y "%LIMINE_DIR%\BOOTX64.EFI"        "%ISO_DIR%\EFI\BOOT\" >nul
copy /Y "%LOADER_DIR%\stage1.gif" "%ISO_DIR%\loader\stage1.gif" >nul
copy /Y "%LOADER_DIR%\stage2.gif" "%ISO_DIR%\loader\stage2.gif" >nul
copy /Y "%LOADER_DIR%\stage3.gif" "%ISO_DIR%\loader\stage3.gif" >nul

REM ===== Create ISO =====
echo [*] Creating ISO image...
"%XORRISO%" -as mkisofs -b limine-bios-cd.bin -no-emul-boot -boot-load-size 4 -boot-info-table --efi-boot limine-uefi-cd.bin -efi-boot-part --efi-boot-image --protective-msdos-label "%ISO_DIR%" -o "%ISO_IMAGE%"
if %ERRORLEVEL% NEQ 0 exit /b 1

REM ===== Install Limine (BIOS) =====
"%LIMINE_DIR%\limine.exe" bios-install "%ISO_IMAGE%" >nul 2>nul
echo [OK] ISO created at %ISO_IMAGE%

REM ===== List ISO =====
"%XORRISO%" -indev "%ISO_IMAGE%" -ls /
"%XORRISO%" -indev "%ISO_IMAGE%" -ls /loader

REM ===== Run QEMU =====
echo [*] Running QEMU...
"%QEMU%" -m 256M -cdrom "%ISO_IMAGE%" -boot d -serial stdio -no-reboot -no-shutdown -vga std

endlocal
exit /b 0
