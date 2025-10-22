@echo off
setlocal enableextensions

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
if not exist "kernel" mkdir "kernel"
if not exist "%INC_DIR%" mkdir "%INC_DIR%"
if not exist "%BITS_DIR%" mkdir "%BITS_DIR%"

REM ===== FETCH: full stb repo (Git first, then ZIP fallback) =====
if not exist "%STB_DIR%" (
  echo [+] Fetching nothings/stb (full repo)
  set GITEXE=
  if exist "%ProgramFiles%\Git\cmd\git.exe" set "GITEXE=%ProgramFiles%\Git\cmd\git.exe"
  if exist "%ProgramFiles(x86)%\Git\cmd\git.exe" set "GITEXE=%ProgramFiles(x86)%\Git\cmd\git.exe"
  if exist "%SystemRoot%\System32\git.exe" set "GITEXE=%SystemRoot%\System32\git.exe"
  if defined GITEXE (
    "%GITEXE%" clone --depth=1 https://github.com/nothings/stb.git "%STB_DIR%"
    if errorlevel 1 (
      echo [!] Git clone failed, trying ZIP fallback
      set "GITEXE="
    )
  )
  if not defined GITEXE (
    powershell -NoProfile -Command "try { Invoke-WebRequest -UseBasicParsing -Uri 'https://github.com/nothings/stb/archive/refs/heads/master.zip' -OutFile 'stb.zip'; Add-Type -A 'System.IO.Compression.FileSystem'; [IO.Compression.ZipFile]::ExtractToDirectory('stb.zip','kernel'); if (Test-Path 'kernel\stb-master'){ Rename-Item 'kernel\stb-master' 'kernel\stb' -Force; } Remove-Item 'stb.zip' -Force } catch { exit 1 }"
    if errorlevel 1 ( echo [!] Failed to download stb repo & exit /b 1 )
  )
) else (
  echo [=] stb repo already present, skip download.
)

REM ===== FETCH: musl headers (include + bits for x86_64) =====
echo [+] Fetching musl headers (C base + bits/x86_64)
powershell -NoProfile -Command ^
  "$ErrorActionPreference='Stop';" ^
  "$files=@(" ^
  "  @{u='https://git.musl-libc.org/cgit/musl/plain/include/assert.h'     ; p='%INC_DIR%\assert.h'}," ^
  "  @{u='https://git.musl-libc.org/cgit/musl/plain/include/string.h'     ; p='%INC_DIR%\string.h'}," ^
  "  @{u='https://git.musl-libc.org/cgit/musl/plain/include/math.h'       ; p='%INC_DIR%\math.h'}," ^
  "  @{u='https://git.musl-libc.org/cgit/musl/plain/include/features.h'   ; p='%INC_DIR%\features.h'}," ^
  "  @{u='https://git.musl-libc.org/cgit/musl/plain/include/stddef.h'     ; p='%INC_DIR%\stddef.h'}," ^
  "  @{u='https://git.musl-libc.org/cgit/musl/plain/include/stdint.h'     ; p='%INC_DIR%\stdint.h'}," ^
  "  @{u='https://git.musl-libc.org/cgit/musl/plain/include/limits.h'     ; p='%INC_DIR%\limits.h'}," ^
  "  @{u='https://git.musl-libc.org/cgit/musl/plain/include/stdbool.h'    ; p='%INC_DIR%\stdbool.h'}," ^
  "  @{u='https://git.musl-libc.org/cgit/musl/plain/include/stdarg.h'     ; p='%INC_DIR%\stdarg.h'}," ^
  "  @{u='https://git.musl-libc.org/cgit/musl/plain/include/ctype.h'      ; p='%INC_DIR%\ctype.h'}," ^
  "  @{u='https://git.musl-libc.org/cgit/musl/plain/include/errno.h'      ; p='%INC_DIR%\errno.h'}," ^
  "  @{u='https://git.musl-libc.org/cgit/musl/plain/include/time.h'       ; p='%INC_DIR%\time.h'}," ^
  "  @{u='https://git.musl-libc.org/cgit/musl/plain/arch/x86_64/bits/alltypes.h.in'; p='%BITS_DIR%\alltypes.h'}," ^
  "  @{u='https://git.musl-libc.org/cgit/musl/plain/arch/x86_64/bits/endian.h'     ; p='%BITS_DIR%\endian.h'}," ^
  "  @{u='https://git.musl-libc.org/cgit/musl/plain/arch/x86_64/bits/limits.h'     ; p='%BITS_DIR%\limits.h'}," ^
  "  @{u='https://git.musl-libc.org/cgit/musl/plain/arch/x86_64/bits/stdint.h'     ; p='%BITS_DIR%\stdint.h'}," ^
  "  @{u='https://git.musl-libc.org/cgit/musl/plain/arch/x86_64/bits/float.h'      ; p='%BITS_DIR%\float.h'}," ^
  "  @{u='https://git.musl-libc.org/cgit/musl/plain/arch/x86_64/bits/wordsize.h'   ; p='%BITS_DIR%\wordsize.h'}," ^
  "  @{u='https://git.musl-libc.org/cgit/musl/plain/arch/x86_64/bits/types.h'      ; p='%BITS_DIR%\types.h'}," ^
  "  @{u='https://git.musl-libc.org/cgit/musl/plain/arch/generic/bits/time.h'      ; p='%BITS_DIR%\time.h'}," ^
  "  @{u='https://git.musl-libc.org/cgit/musl/plain/arch/generic/bits/signal.h'    ; p='%BITS_DIR%\signal.h'}," ^
  "  @{u='https://git.musl-libc.org/cgit/musl/plain/arch/generic/bits/setjmp.h'    ; p='%BITS_DIR%\setjmp.h'}," ^
  "  @{u='https://git.musl-libc.org/cgit/musl/plain/arch/generic/bits/stdarg.h'    ; p='%BITS_DIR%\stdarg.h'}," ^
  "  @{u='https://git.musl-libc.org/cgit/musl/plain/arch/generic/bits/errno.h'     ; p='%BITS_DIR%\errno.h'}" ^
  ");" ^
  "foreach($f in $files){ if(!(Test-Path (Split-Path $f.p))){ New-Item -ItemType Directory -Force -Path (Split-Path $f.p) | Out-Null }; try { Invoke-WebRequest -UseBasicParsing -Uri $f.u -OutFile $f.p } catch { Write-Error \"DL fail: $($f.u)\"; exit 1 } }"
if errorlevel 1 (
  echo [!] Failed to fetch musl headers
  exit /b 1
)

REM NOTE: musl fournit des en-tetes de libc. Tu compiles en freestanding: evite d'appeler des fonctions libc.
REM       Ici on les prend pour satisfaire des #include (types/macros). Pas de linkage libm/libc.

REM ---- Compile kernel (ajout des includes locaux) ----
"%CC%" -target %ARCH_TARGET% -std=gnu11 -O2 -pipe -Wall -Wextra -ffreestanding -fno-stack-protector -fno-pic -fno-pie -mno-red-zone -m64 -mcmodel=kernel -I "%LIMINE_DIR%" -I "%INC_DIR%" -I "%STB_DIR%" -fno-asynchronous-unwind-tables -fno-exceptions -c kernel\main.c -o "%BUILD_DIR%\kernel.o"
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

REM Download Inter font (for future use) if missing
if not exist "%ISO_DIR%\assets\Inter.ttf" (
    powershell -NoProfile -Command "try { Invoke-WebRequest -UseBasicParsing -Uri 'https://github.com/rsms/inter/releases/download/v4.1/Inter-4.1.zip' -OutFile 'inter.zip'; Add-Type -A 'System.IO.Compression.FileSystem'; [IO.Compression.ZipFile]::ExtractToDirectory('inter.zip','inter_tmp'); Copy-Item -Path inter_tmp\*.ttf -Destination '%ISO_DIR%\assets\' -ErrorAction SilentlyContinue; Remove-Item inter.zip -Force; Remove-Item inter_tmp -Recurse -Force } catch { }"
)

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
