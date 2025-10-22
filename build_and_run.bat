@echo off
setlocal EnableExtensions
cd /d "%~dp0"

REM ===== Nova OS build & run (Windows) =====

REM ---- Paths ----
set PROJECT_NAME=NovaOS
set BUILD_DIR=build
set ISO_DIR=iso_root
set KERNEL_ELF=%BUILD_DIR%\kernel.elf
set ISO_IMAGE=%BUILD_DIR%\%PROJECT_NAME%.iso
set LIMINE_DIR=Limine
set INC_DIR=kernel\include
set BITS_DIR=kernel\include\bits
set LOADER_DIR=kernel\loader
set MUSL_VER=1.2.5
set MUSL_ZIP=%BUILD_DIR%\musl-%MUSL_VER%.zip
set MUSL_DIR=%BUILD_DIR%\musl-%MUSL_VER%

REM ---- Tools (LLVM, xorriso, QEMU in PATH) ----
set CC=clang
set LD=ld.lld
set ARCH_TARGET=x86_64-unknown-elf
set XORRISO=xorriso
if exist "%USERPROFILE%\scoop\apps\msys2\current\usr\bin\xorriso.exe" set "XORRISO=%USERPROFILE%\scoop\apps\msys2\current\usr\bin\xorriso.exe"

REM ---- Clean ----
if exist "%BUILD_DIR%" rmdir /s /q "%BUILD_DIR%"
if exist "%ISO_DIR%" rmdir /s /q "%ISO_DIR%"

REM ---- Create dirs ----
mkdir "%BUILD_DIR%" >nul
mkdir "%ISO_DIR%" >nul
mkdir "%ISO_DIR%\boot\limine" >nul
mkdir "%ISO_DIR%\EFI\BOOT" >nul
mkdir "%ISO_DIR%\limine" >nul
mkdir "%ISO_DIR%\loader" >nul
if not exist "%INC_DIR%" mkdir "%INC_DIR%"
if not exist "%BITS_DIR%" mkdir "%BITS_DIR%"

REM ===== musl C headers (for types/macros only) =====
if exist "%INC_DIR%\stdlib.h" goto have_headers
echo [.] Downloading musl headers v%MUSL_VER%...
powershell -NoProfile -ExecutionPolicy Bypass -Command "try { Invoke-WebRequest -UseBasicParsing -Uri 'https://codeload.github.com/bminor/musl/zip/refs/tags/v%MUSL_VER%' -OutFile '%MUSL_ZIP%' } catch { exit 1 }"
if errorlevel 1 (
  where curl >nul 2>nul && curl -L "https://codeload.github.com/bminor/musl/zip/refs/tags/v%MUSL_VER%" -o "%MUSL_ZIP%"
)
if not exist "%MUSL_ZIP%" (
  echo [!] Failed to download musl headers.
  exit /b 1
)
powershell -NoProfile -ExecutionPolicy Bypass -Command "Expand-Archive -Path '%MUSL_ZIP%' -DestinationPath '%BUILD_DIR%' -Force"
for /d %%D in ("%BUILD_DIR%\musl-*%MUSL_VER%*") do set "MUSL_DIR=%%D"
if not defined MUSL_DIR (
  echo [!] musl extract directory not found.
  exit /b 1
)
echo [.] Installing musl include headers...
xcopy /E /I /Y "%MUSL_DIR%\include\" "%INC_DIR%\" >nul
echo [.] Installing musl generic bits...
if exist "%MUSL_DIR%\arch\generic\bits\" xcopy /E /I /Y "%MUSL_DIR%\arch\generic\bits\" "%BITS_DIR%\" >nul
echo [.] Installing musl x86_64 bits (overrides)...
if exist "%MUSL_DIR%\arch\x86_64\bits\" xcopy /E /I /Y "%MUSL_DIR%\arch\x86_64\bits\" "%BITS_DIR%\" >nul

:have_headers
echo [=] Using C headers in %INC_DIR%

REM ---- Fallback if bits/alltypes.h still missing ----
if not exist "%INC_DIR%\bits\alltypes.h" call :install_prebuilt_musl

REM ===== VERIFY GIF ASSETS (required) =====
if not exist "%LOADER_DIR%\stage1.gif" ( echo [!] Missing %LOADER_DIR%\stage1.gif & exit /b 1 )
if not exist "%LOADER_DIR%\stage2.gif" ( echo [!] Missing %LOADER_DIR%\stage2.gif & exit /b 1 )
if not exist "%LOADER_DIR%\stage3.gif" ( echo [!] Missing %LOADER_DIR%\stage3.gif & exit /b 1 )

REM ---- Compile kernel (freestanding) ----
"%CC%" -target %ARCH_TARGET% -std=gnu11 -O2 -pipe -Wall -Wextra ^
  -ffreestanding -fno-stack-protector -fno-pic -fno-pie -mno-red-zone -m64 -mcmodel=kernel ^
  -I "%LIMINE_DIR%" -I "%INC_DIR%" -fno-asynchronous-unwind-tables -fno-exceptions ^
  -c kernel\main.c -o "%BUILD_DIR%\kernel.o"
if errorlevel 1 exit /b 1

REM ---- Link kernel ----
"%LD%" -m elf_x86_64 -o "%KERNEL_ELF%" -nostdlib -z max-page-size=0x1000 -T kernel\linker.ld "%BUILD_DIR%\kernel.o"
if errorlevel 1 exit /b 1

REM ---- Populate ISO root ----
copy /Y "%KERNEL_ELF%" "%ISO_DIR%\kernel.elf" >nul
copy /Y limine.conf "%ISO_DIR%\limine.conf" >nul
copy /Y limine.conf "%ISO_DIR%\limine.cfg"  >nul
copy /Y "%LIMINE_DIR%\limine-bios.sys"    "%ISO_DIR%\" >nul
copy /Y "%LIMINE_DIR%\limine-bios-cd.bin" "%ISO_DIR%\" >nul
copy /Y "%LIMINE_DIR%\limine-uefi-cd.bin" "%ISO_DIR%\" >nul
copy /Y "%LIMINE_DIR%\BOOTX64.EFI"        "%ISO_DIR%\EFI\BOOT\" >nul

REM ---- Copy GIF modules EXACT PATHS used by limine.conf ----
copy /Y "%LOADER_DIR%\stage1.gif" "%ISO_DIR%\loader\stage1.gif" >nul
copy /Y "%LOADER_DIR%\stage2.gif" "%ISO_DIR%\loader\stage2.gif" >nul
copy /Y "%LOADER_DIR%\stage3.gif" "%ISO_DIR%\loader\stage3.gif" >nul

REM ---- Create hybrid BIOS/UEFI ISO ----
"%XORRISO%" -as mkisofs ^
  -b limine-bios-cd.bin -no-emul-boot -boot-load-size 4 -boot-info-table ^
  --efi-boot limine-uefi-cd.bin -efi-boot-part --efi-boot-image ^
  --protective-msdos-label "%ISO_DIR%" -o "%ISO_IMAGE%"
if errorlevel 1 exit /b 1

REM ---- Install Limine to ISO (BIOS) ----
"%LIMINE_DIR%\limine.exe" bios-install "%ISO_IMAGE%" >nul 2>nul

echo ISO created at %ISO_IMAGE%

REM ---- (Optional) List ISO contents for sanity ----
"%XORRISO%" -indev "%ISO_IMAGE%" -find / -type f -print

REM ---- Run with QEMU (BIOS) ----
qemu-system-x86_64 -m 256M -cdrom "%ISO_IMAGE%" -boot d -serial stdio -no-reboot -no-shutdown

endlocal
goto :eof


:install_prebuilt_musl
echo [!] bits\alltypes.h missing; fetching prebuilt musl headers (musl.cc)...
set MUSL_TOOL_URL=https://musl.cc/x86_64-linux-musl-native.tgz
set MUSL_TOOL_TGZ=%BUILD_DIR%\x86_64-linux-musl-native.tgz
set MUSL_TOOL_DIR=%BUILD_DIR%\x86_64-linux-musl-native
powershell -NoProfile -ExecutionPolicy Bypass -Command "try { Invoke-WebRequest -UseBasicParsing -Uri '%MUSL_TOOL_URL%' -OutFile '%MUSL_TOOL_TGZ%' } catch { exit 1 }"
if errorlevel 1 (
  where curl >nul 2>nul && curl -L "%MUSL_TOOL_URL%" -o "%MUSL_TOOL_TGZ%"
)
if not exist "%MUSL_TOOL_TGZ%" (
  echo [!] Failed to download musl toolchain archive from musl.cc
  exit /b 1
)
if exist "%MUSL_TOOL_DIR%" rmdir /s /q "%MUSL_TOOL_DIR%"
mkdir "%MUSL_TOOL_DIR%"
tar -xf "%MUSL_TOOL_TGZ%" -C "%BUILD_DIR%"
if not exist "%BUILD_DIR%\x86_64-linux-musl-native\include\stdio.h" (
  echo [!] Unexpected musl toolchain layout; include not found
  exit /b 1
)
echo [.] Installing prebuilt musl include headers...
xcopy /E /I /Y "%BUILD_DIR%\x86_64-linux-musl-native\include\" "%INC_DIR%\" >nul
if not exist "%INC_DIR%\bits\alltypes.h" (
  echo [!] Still missing bits\alltypes.h after installing prebuilt headers
  exit /b 1
)
echo [=] Using prebuilt musl headers from musl.cc
exit /b 0
