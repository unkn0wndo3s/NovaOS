@echo off
setlocal EnableExtensions EnableDelayedExpansion

cd /d "%~dp0"

REM ===== Nova OS build & run (Windows) =====

REM ---- Paths ----
set PROJECT_NAME=NovaOS
set BUILD_DIR=build
set ISO_DIR=iso_root
set KERNEL_ELF=%BUILD_DIR%\kernel.elf
set ISO_IMAGE=%BUILD_DIR%\%PROJECT_NAME%.iso
set LIMINE_DIR=Limine
set STB_DIR=kernel\stb
set INC_DIR=kernel\include
set BITS_DIR=kernel\include\bits
set LOADER_DIR=kernel\loader
set MUSL_VER=1.2.5
set MUSL_ZIP=%BUILD_DIR%\musl-%MUSL_VER%.zip
set MUSL_DIR=%BUILD_DIR%\musl-%MUSL_VER%

REM ---- Tools (require LLVM, xorriso, QEMU in PATH) ----
set CC=clang
set LD=ld.lld
set ARCH_TARGET=x86_64-unknown-elf
set XORRISO=xorriso
if exist "%USERPROFILE%\scoop\apps\msys2\current\usr\bin\xorriso.exe" set "XORRISO=%USERPROFILE%\scoop\apps\msys2\current\usr\bin\xorriso.exe"

REM ---- Clean previous build to force full rebuild ----
if exist "%BUILD_DIR%" rmdir /s /q "%BUILD_DIR%"
if exist "%ISO_DIR%" rmdir /s /q "%ISO_DIR%"

REM ---- Create directories ----
if not exist "%BUILD_DIR%" mkdir "%BUILD_DIR%"
if not exist "%ISO_DIR%" mkdir "%ISO_DIR%"
if not exist "%ISO_DIR%\boot\limine" mkdir "%ISO_DIR%\boot\limine"
if not exist "%ISO_DIR%\EFI\BOOT" mkdir "%ISO_DIR%\EFI\BOOT"
if not exist "%ISO_DIR%\limine" mkdir "%ISO_DIR%\limine"
if not exist "%ISO_DIR%\assets" mkdir "%ISO_DIR%\assets"
if not exist "%ISO_DIR%\assets\loader" mkdir "%ISO_DIR%\assets\loader"
if not exist "kernel" mkdir "kernel"
if not exist "%INC_DIR%" mkdir "%INC_DIR%"
if not exist "%BITS_DIR%" mkdir "%BITS_DIR%"

REM ===== stb_image header: fetch if missing =====
if not exist "kernel\stb_image.h" (
  echo [.] Downloading stb_image.h...
  powershell -NoProfile -ExecutionPolicy Bypass -Command "try { Invoke-WebRequest -UseBasicParsing -Uri 'https://raw.githubusercontent.com/nothings/stb/master/stb_image.h' -OutFile 'kernel/stb_image.h'; exit 0 } catch { exit 1 }"
  if errorlevel 1 (
    where curl >nul 2>nul && curl -L "https://raw.githubusercontent.com/nothings/stb/master/stb_image.h" -o "kernel/stb_image.h"
  )
  if not exist "kernel\stb_image.h" (
    echo [!] Failed to fetch kernel\stb_image.h automatically.
    echo     Please download from: https://raw.githubusercontent.com/nothings/stb/master/stb_image.h
    echo     and place it at: kernel\stb_image.h
    exit /b 1
  )
)
echo [=] Using stb_image.h

REM ===== musl C headers: fetch if missing =====
if exist "%INC_DIR%\stdlib.h" goto have_headers
echo [.] Downloading musl headers v%MUSL_VER%...
if not exist "%BUILD_DIR%" mkdir "%BUILD_DIR%"
powershell -NoProfile -ExecutionPolicy Bypass -Command "try { Invoke-WebRequest -UseBasicParsing -Uri 'https://codeload.github.com/bminor/musl/zip/refs/tags/v%MUSL_VER%' -OutFile '%MUSL_ZIP%'; exit 0 } catch { exit 1 }"
if errorlevel 1 (
  where curl >nul 2>nul && curl -L "https://codeload.github.com/bminor/musl/zip/refs/tags/v%MUSL_VER%" -o "%MUSL_ZIP%"
)
if not exist "%MUSL_ZIP%" (
  echo [!] Failed to download musl headers archive.
  echo     URL: https://codeload.github.com/bminor/musl/zip/refs/tags/v%MUSL_VER%
  exit /b 1
)
powershell -NoProfile -ExecutionPolicy Bypass -Command "Expand-Archive -Path '%MUSL_ZIP%' -DestinationPath '%BUILD_DIR%' -Force"
for /d %%D in ("%BUILD_DIR%\musl-*%MUSL_VER%*") do set "MUSL_DIR=%%D"
if not defined MUSL_DIR (
  echo [!] musl extract directory not found.
  exit /b 1
)
if not exist "%INC_DIR%" mkdir "%INC_DIR%"
if not exist "%BITS_DIR%" mkdir "%BITS_DIR%"
echo [.] Installing musl include headers...
xcopy /E /I /Y "%MUSL_DIR%\include\" "%INC_DIR%\" >nul
echo [.] Installing musl generic bits...
if exist "%MUSL_DIR%\arch\generic\bits\" xcopy /E /I /Y "%MUSL_DIR%\arch\generic\bits\" "%BITS_DIR%\" >nul
echo [.] Installing musl x86_64 bits (overrides)...
if exist "%MUSL_DIR%\arch\x86_64\bits\" xcopy /E /I /Y "%MUSL_DIR%\arch\x86_64\bits\" "%BITS_DIR%\" >nul

:have_headers
echo [=] Using C headers in %INC_DIR%

REM NOTE: musl fournit des en-tetes de libc. Tu compiles en freestanding: evite d'appeler des fonctions libc.
REM       Ici on les prend pour satisfaire des #include (types/macros). Pas de linkage libm/libc.

REM ---- Compile kernel (ajout des includes locaux) ----
"%CC%" -target %ARCH_TARGET% -std=gnu11 -O2 -pipe -Wall -Wextra -ffreestanding -fno-stack-protector -fno-pic -fno-pie -mno-red-zone -m64 -mcmodel=kernel -I "%LIMINE_DIR%" -I "%INC_DIR%" -fno-asynchronous-unwind-tables -fno-exceptions -c kernel\main.c -o "%BUILD_DIR%\kernel.o"
if errorlevel 1 exit /b 1

REM ---- Link kernel ----
"%LD%" -m elf_x86_64 -o "%KERNEL_ELF%" -nostdlib -z max-page-size=0x1000 -T kernel\linker.ld "%BUILD_DIR%\kernel.o"
if errorlevel 1 exit /b 1

REM ---- Populate ISO root ----
copy /Y "%KERNEL_ELF%" "%ISO_DIR%\kernel.elf" >nul
copy /Y "%KERNEL_ELF%" "%ISO_DIR%\KERNEL.ELF" >nul
copy /Y limine.conf "%ISO_DIR%\limine.conf" >nul
copy /Y limine.conf "%ISO_DIR%\LIMINE.CONF" >nul
copy /Y limine.conf "%ISO_DIR%\limine.cfg" >nul
copy /Y limine.conf "%ISO_DIR%\LIMINE.CFG" >nul
copy /Y limine.conf "%ISO_DIR%\boot\limine\limine.conf" >nul
copy /Y limine.conf "%ISO_DIR%\boot\limine\LIMINE.CONF" >nul
copy /Y limine.conf "%ISO_DIR%\boot\limine\limine.cfg" >nul
copy /Y limine.conf "%ISO_DIR%\boot\limine\LIMINE.CFG" >nul
copy /Y limine.conf "%ISO_DIR%\limine\limine.conf" >nul
copy /Y limine.conf "%ISO_DIR%\limine\LIMINE.CONF" >nul
copy /Y limine.conf "%ISO_DIR%\limine\limine.cfg" >nul
copy /Y limine.conf "%ISO_DIR%\limine\LIMINE.CFG" >nul
copy /Y "%LIMINE_DIR%\limine-bios.sys" "%ISO_DIR%\" >nul
copy /Y "%LIMINE_DIR%\limine-bios.sys" "%ISO_DIR%\boot\limine\" >nul
copy /Y "%LIMINE_DIR%\limine-bios.sys" "%ISO_DIR%\limine\" >nul
copy /Y "%LIMINE_DIR%\limine-bios-cd.bin" "%ISO_DIR%\" >nul
copy /Y "%LIMINE_DIR%\limine-uefi-cd.bin" "%ISO_DIR%\" >nul
copy /Y "%LIMINE_DIR%\BOOTX64.EFI" "%ISO_DIR%\EFI\BOOT\" >nul

REM Copy GIF loader assets if present
if exist "%LOADER_DIR%\stage1.gif" copy /Y "%LOADER_DIR%\stage1.gif" "%ISO_DIR%\assets\loader\stage1.gif" >nul
if exist "%LOADER_DIR%\stage2.gif" copy /Y "%LOADER_DIR%\stage2.gif" "%ISO_DIR%\assets\loader\stage2.gif" >nul
if exist "%LOADER_DIR%\stage3.gif" copy /Y "%LOADER_DIR%\stage3.gif" "%ISO_DIR%\assets\loader\stage3.gif" >nul

copy /Y limine.conf "%ISO_DIR%\EFI\BOOT\limine.conf" >nul
copy /Y limine.conf "%ISO_DIR%\EFI\BOOT\LIMINE.CONF" >nul
copy /Y limine.conf "%ISO_DIR%\EFI\BOOT\limine.cfg" >nul
copy /Y limine.conf "%ISO_DIR%\EFI\BOOT\LIMINE.CFG" >nul

REM ---- Create hybrid BIOS/UEFI ISO ----
"%XORRISO%" -as mkisofs -b limine-bios-cd.bin -no-emul-boot -boot-load-size 4 -boot-info-table --efi-boot limine-uefi-cd.bin -efi-boot-part --efi-boot-image --protective-msdos-label "%ISO_DIR%" -o "%ISO_IMAGE%"
if errorlevel 1 exit /b 1

REM ---- Install Limine to ISO (BIOS) ----
"%LIMINE_DIR%\limine.exe" bios-install "%ISO_IMAGE%" >nul 2>nul

echo ISO created at %ISO_IMAGE%

REM ---- Run with QEMU (BIOS) ----
qemu-system-x86_64 -m 256M -cdrom "%ISO_IMAGE%" -boot d -serial stdio -no-reboot -no-shutdown

endlocal
