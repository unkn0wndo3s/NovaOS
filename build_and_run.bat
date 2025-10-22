@echo off
setlocal EnableExtensions
cd /d "%~dp0"

REM ===== Nova OS build & run (Windows, CMD syntax OK) =====

REM -------- Config & Paths --------
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

REM -------- Tool defaults --------
set CC=clang
set LD=ld.lld
set ARCH_TARGET=x86_64-unknown-elf
set XORRISO=xorriso
set QEMU=qemu-system-x86_64

REM Si MSYS2 xorriso existe, utilise-le
if exist "%USERPROFILE%\scoop\apps\msys2\current\usr\bin\xorriso.exe" set "XORRISO=%USERPROFILE%\scoop\apps\msys2\current\usr\bin\xorriso.exe"

echo.
echo [*] Prepa environnement...

REM ===== Detect package managers =====
where winget >nul 2>nul && set HAVE_WINGET=1
where scoop  >nul 2>nul && set HAVE_SCOOP=1

REM ===== Ensure: LLVM (clang, ld.lld) =====
where %CC% >nul 2>nul && where %LD% >nul 2>nul
if errorlevel 1 (
  echo [!] LLVM (clang/ld.lld) introuvable.
  if defined HAVE_WINGET (
    echo [.] Install via winget...
    winget install -e --id LLVM.LLVM -h
  ) else (
    if defined HAVE_SCOOP (
      echo [.] Install via scoop...
      scoop install llvm
    ) else (
      echo [X] Ni winget ni scoop. Installe LLVM et relance.
      exit /b 1
    )
  )
)

REM ===== Ensure: QEMU =====
where %QEMU% >nul 2>nul
if errorlevel 1 (
  echo [!] QEMU introuvable.
  if defined HAVE_WINGET (
    echo [.] Install via winget...
    winget install -e --id qemu.qemu -h
  ) else (
    if defined HAVE_SCOOP (
      echo [.] Install via scoop...
      scoop install qemu
    ) else (
      echo [X] Ni winget ni scoop. Installe QEMU et relance.
      exit /b 1
    )
  )
)

REM ===== Ensure: xorriso =====
where %XORRISO% >nul 2>nul
if errorlevel 1 (
  echo [!] xorriso introuvable.
  if defined HAVE_SCOOP (
    echo [.] Install MSYS2 via scoop (puis xorriso)...
    scoop install msys2
    "%USERPROFILE%\scoop\apps\msys2\current\usr\bin\bash.exe" -lc "pacman -S --noconfirm xorriso"
    if exist "%USERPROFILE%\scoop\apps\msys2\current\usr\bin\xorriso.exe" set "XORRISO=%USERPROFILE%\scoop\apps\msys2\current\usr\bin\xorriso.exe"
  ) else (
    if defined HAVE_WINGET (
      echo [.] Install MSYS2 via winget...
      winget install -e --id MSYS2.MSYS2 -h
      echo [!] Ouvre MSYS2 et installe 'xorriso' : pacman -S xorriso
      echo     Puis relance ce script.
      exit /b 1
    ) else (
      echo [X] Pas de xorriso. Installe MSYS2 + xorriso et relance.
      exit /b 1
    )
  )
)

REM ===== Limine assets sanity =====
if not exist "%LIMINE_DIR%\limine-bios.sys" (
  echo [!] Manque %LIMINE_DIR%\limine-bios.sys (et autres binaires Limine)
  echo     Mets: limine-bios.sys, limine-bios-cd.bin, limine-uefi-cd.bin, BOOTX64.EFI, limine.exe
  exit /b 1
)

REM ===== Clean =====
if exist "%BUILD_DIR%" rmdir /s /q "%BUILD_DIR%"
if exist "%ISO_DIR%" rmdir /s /q "%ISO_DIR%"

REM ===== Create dirs =====
mkdir "%BUILD_DIR%" >nul
mkdir "%ISO_DIR%" >nul
mkdir "%ISO_DIR%\boot\limine" >nul
mkdir "%ISO_DIR%\EFI\BOOT" >nul
mkdir "%ISO_DIR%\limine" >nul
mkdir "%ISO_DIR%\loader" >nul
if not exist "%INC_DIR%"  mkdir "%INC_DIR%"
if not exist "%BITS_DIR%" mkdir "%BITS_DIR%"

REM ===== musl C headers =====
if exist "%INC_DIR%\stdlib.h" goto have_headers
echo [.] Telechargement headers musl v%MUSL_VER%...
powershell -NoProfile -ExecutionPolicy Bypass -Command "try { Invoke-WebRequest -UseBasicParsing -Uri 'https://codeload.github.com/bminor/musl/zip/refs/tags/v%MUSL_VER%' -OutFile '%MUSL_ZIP%' } catch { exit 1 }"
if errorlevel 1 (
  where curl >nul 2>nul && curl -L "https://codeload.github.com/bminor/musl/zip/refs/tags/v%MUSL_VER%" -o "%MUSL_ZIP%"
)
if not exist "%MUSL_ZIP%" (
  echo [!] Echec telechargement musl headers.
  exit /b 1
)
powershell -NoProfile -ExecutionPolicy Bypass -Command "Expand-Archive -Path '%MUSL_ZIP%' -DestinationPath '%BUILD_DIR%' -Force"
for /d %%D in ("%BUILD_DIR%\musl-*%MUSL_VER%*") do set "MUSL_DIR=%%D"
if not defined MUSL_DIR (
  echo [!] Dossier musl extrait introuvable.
  exit /b 1
)
echo [.] Install des en-tetes musl...
xcopy /E /I /Y "%MUSL_DIR%\include\" "%INC_DIR%\" >nul
echo [.] bits generiques...
if exist "%MUSL_DIR%\arch\generic\bits\" xcopy /E /I /Y "%MUSL_DIR%\arch\generic\bits\" "%BITS_DIR%\" >nul
echo [.] bits x86_64 (override)...
if exist "%MUSL_DIR%\arch\x86_64\bits\" xcopy /E /I /Y "%MUSL_DIR%\arch\x86_64\bits\" "%BITS_DIR%\" >nul

:have_headers
if not exist "%INC_DIR%\bits\alltypes.h" call :install_prebuilt_musl
echo [=] Headers C: %INC_DIR%

REM ===== Verif GIF assets =====
if not exist "%LOADER_DIR%\stage1.gif" ( echo [!] Manque %LOADER_DIR%\stage1.gif & exit /b 1 )
if not exist "%LOADER_DIR%\stage2.gif" ( echo [!] Manque %LOADER_DIR%\stage2.gif & exit /b 1 )
if not exist "%LOADER_DIR%\stage3.gif" ( echo [!] Manque %LOADER_DIR%\stage3.gif & exit /b 1 )

REM ===== Compile kernel =====
echo.
echo [*] Compilation kernel...
"%CC%" -target %ARCH_TARGET% -std=gnu11 -O2 -pipe -Wall -Wextra ^
  -ffreestanding -fno-stack-protector -fno-pic -fno-pie -mno-red-zone -m64 -mcmodel=kernel ^
  -I "%LIMINE_DIR%" -I "%INC_DIR%" -fno-asynchronous-unwind-tables -fno-exceptions ^
  -c kernel\main.c -o "%BUILD_DIR%\kernel.o"
if errorlevel 1 exit /b 1

REM ===== Link kernel =====
"%LD%" -m elf_x86_64 -o "%KERNEL_ELF%" -nostdlib -z max-page-size=0x1000 -T kernel\linker.ld "%BUILD_DIR%\kernel.o"
if errorlevel 1 exit /b 1

REM ===== Populate ISO root =====
echo [*] Preparation ISO...
copy /Y "%KERNEL_ELF%" "%ISO_DIR%\kernel.elf" >nul
copy /Y limine.conf "%ISO_DIR%\limine.conf" >nul
copy /Y limine.conf "%ISO_DIR%\limine.cfg"  >nul

copy /Y "%LIMINE_DIR%\limine-bios.sys"    "%ISO_DIR%\" >nul
copy /Y "%LIMINE_DIR%\limine-bios-cd.bin" "%ISO_DIR%\" >nul
copy /Y "%LIMINE_DIR%\limine-uefi-cd.bin" "%ISO_DIR%\" >nul
copy /Y "%LIMINE_DIR%\BOOTX64.EFI"        "%ISO_DIR%\EFI\BOOT\" >nul

copy /Y "%LOADER_DIR%\stage1.gif" "%ISO_DIR%\loader\stage1.gif" >nul
copy /Y "%LOADER_DIR%\stage2.gif" "%ISO_DIR%\loader\stage2.gif" >nul
copy /Y "%LOADER_DIR%\stage3.gif" "%ISO_DIR%\loader\stage3.gif" >nul

REM ===== Create ISO =====
echo [*] Creation ISO...
"%XORRISO%" -as mkisofs ^
  -b limine-bios-cd.bin -no-emul-boot -boot-load-size 4 -boot-info-table ^
  --efi-boot limine-uefi-cd.bin -efi-boot-part --efi-boot-image ^
  --protective-msdos-label "%ISO_DIR%" -o "%ISO_IMAGE%"
if errorlevel 1 exit /b 1

REM ===== Install Limine (BIOS) =====
"%LIMINE_DIR%\limine.exe" bios-install "%ISO_IMAGE%" >nul 2>nul

echo [OK] ISO: %ISO_IMAGE%

REM ===== Sanity list =====
"%XORRISO%" -indev "%ISO_IMAGE%" -ls /
"%XORRISO%" -indev "%ISO_IMAGE%" -ls /loader

REM ===== Run QEMU =====
echo.
echo [*] Lancement QEMU...
"%QEMU%" -m 256M -cdrom "%ISO_IMAGE%" -boot d -serial stdio -no-reboot -no-shutdown
exit /b 0


REM ---------------------- FUNCTIONS ----------------------
:install_prebuilt_musl
echo [!] bits\alltypes.h manquant; recup headers (musl.cc)...
set MUSL_TOOL_URL=https://musl.cc/x86_64-linux-musl-native.tgz
set MUSL_TOOL_TGZ=%BUILD_DIR%\x86_64-linux-musl-native.tgz
set MUSL_TMP=%BUILD_DIR%\_musl_tmp

powershell -NoProfile -ExecutionPolicy Bypass -Command "try { Invoke-WebRequest -UseBasicParsing -Uri '%MUSL_TOOL_URL%' -OutFile '%MUSL_TOOL_TGZ%' } catch { exit 1 }"
if errorlevel 1 (
  where curl >nul 2>nul && curl -L "%MUSL_TOOL_URL%" -o "%MUSL_TOOL_TGZ%"
)
if not exist "%MUSL_TOOL_TGZ%" (
  echo [X] Echec telechargement toolchain musl.cc
  exit /b 1
)

if exist "%MUSL_TMP%" rmdir /s /q "%MUSL_TMP%"
mkdir "%MUSL_TMP%"

powershell -NoProfile -ExecutionPolicy Bypass -Command ^
  "$p='%MUSL_TOOL_TGZ%'; $d='%MUSL_TMP%'; Add-Type -A 'System.IO.Compression.FileSystem';" ^
  ";$gz=[IO.File]::OpenRead($p);" ^
  ";$ms=New-Object IO.MemoryStream;" ^
  ";(New-Object IO.Compression.GzipStream($gz,[IO.Compression.CompressionMode]::Decompress)).CopyTo($ms);" ^
  ";$gz.Dispose();" ^
  ";[IO.File]::WriteAllBytes((Join-Path $d 'musl.tar'), $ms.ToArray())"

if not exist "%MUSL_TMP%\musl.tar" (
  echo [X] Echec creation musl.tar depuis tgz
  exit /b 1
)

tar -xf "%MUSL_TMP%\musl.tar" --wildcards "x86_64-linux-musl-native/include/*" -C "%MUSL_TMP%"
if errorlevel 1 (
  echo [X] Echec extraction include/
  exit /b 1
)

xcopy /E /I /Y "%MUSL_TMP%\x86_64-linux-musl-native\include\" "%INC_DIR%\" >nul

if not exist "%INC_DIR%\bits\alltypes.h" (
  echo [X] Toujours pas de bits\alltypes.h
  exit /b 1
)

echo [=] Headers musl OK
rmdir /s /q "%MUSL_TMP%" >nul 2>nul
exit /b 0
