@echo off
setlocal enableextensions

REM Build and run Nova OS (Windows, no loops)

REM ---- Paths ----
set PROJECT_NAME=NovaOS
set BUILD_DIR=build
set ISO_DIR=iso_root
set KERNEL_ELF=%BUILD_DIR%\kernel.elf
set ISO_IMAGE=%BUILD_DIR%\%PROJECT_NAME%.iso
set LIMINE_DIR=Limine

REM ---- Tools (require LLVM, xorriso, QEMU in PATH) ----
set CC=clang
set LD=ld.lld

REM ---- Create directories ----
if not exist "%BUILD_DIR%" mkdir "%BUILD_DIR%"
if not exist "%ISO_DIR%" mkdir "%ISO_DIR%"
if not exist "%ISO_DIR%\boot\limine" mkdir "%ISO_DIR%\boot\limine"
if not exist "%ISO_DIR%\EFI\BOOT" mkdir "%ISO_DIR%\EFI\BOOT"
if not exist "%ISO_DIR%\limine" mkdir "%ISO_DIR%\limine"

REM ---- Compile kernel ----
"%CC%" -std=gnu11 -O2 -pipe -Wall -Wextra -ffreestanding -fno-stack-protector -fno-pic -fno-pie -mno-red-zone -m64 -mcmodel=kernel -I "%LIMINE_DIR%" -fno-asynchronous-unwind-tables -fno-exceptions -c kernel\main.c -o "%BUILD_DIR%\kernel.o"

REM ---- Link kernel ----
"%LD%" -o "%KERNEL_ELF%" -nostdlib -z max-page-size=0x1000 -T kernel\linker.ld "%BUILD_DIR%\kernel.o"

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
copy /Y limine.conf "%ISO_DIR%\EFI\BOOT\limine.conf" >nul
copy /Y limine.conf "%ISO_DIR%\EFI\BOOT\LIMINE.CONF" >nul
copy /Y limine.conf "%ISO_DIR%\EFI\BOOT\limine.cfg" >nul
copy /Y limine.conf "%ISO_DIR%\EFI\BOOT\LIMINE.CFG" >nul

REM ---- Create hybrid BIOS/UEFI ISO ----
xorriso -as mkisofs -b limine-bios-cd.bin -no-emul-boot -boot-load-size 4 -boot-info-table --efi-boot limine-uefi-cd.bin -efi-boot-part --efi-boot-image --protective-msdos-label "%ISO_DIR%" -o "%ISO_IMAGE%"

REM ---- Install Limine to ISO (BIOS) ----
"%LIMINE_DIR%\limine.exe" bios-install "%ISO_IMAGE%"

echo ISO created at %ISO_IMAGE%

REM ---- Run with QEMU (BIOS) ----
qemu-system-x86_64 -m 256M -cdrom "%ISO_IMAGE%" -boot d -serial stdio

endlocal
