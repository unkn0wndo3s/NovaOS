# Root build for minimal Limine-based kernel and ISO

PROJECT_NAME := NovaOS
BUILD_DIR := build
ISO_DIR := iso_root
KERNEL_ELF := $(BUILD_DIR)/kernel.elf

# Toolchain (override on command line if desired)
CC ?= clang
LD ?= ld.lld
AR ?= llvm-ar
OBJCOPY ?= llvm-objcopy

CFLAGS := -std=gnu11 -O2 -pipe -Wall -Wextra -ffreestanding -fno-stack-protector -fno-pic -fno-pie -mno-red-zone -m64 -mcmodel=kernel -I Limine -fno-asynchronous-unwind-tables -fno-exceptions
LDFLAGS := -nostdlib -z max-page-size=0x1000 -T kernel/linker.ld

LIMINE_DIR := Limine
ISO_IMAGE := $(BUILD_DIR)/$(PROJECT_NAME).iso

.PHONY: all clean iso run run-uefi run-bios

all: iso

$(BUILD_DIR):
	mkdir -p "$(BUILD_DIR)"

$(ISO_DIR):
	mkdir -p "$(ISO_DIR)"

$(BUILD_DIR)/kernel.o: kernel/main.c | $(BUILD_DIR)
	$(CC) $(CFLAGS) -c $< -o $@

$(KERNEL_ELF): $(BUILD_DIR)/kernel.o kernel/linker.ld | $(BUILD_DIR)
	$(LD) -o $@ $(LDFLAGS) $(BUILD_DIR)/kernel.o

iso: $(KERNEL_ELF) limine.conf | $(ISO_DIR)
	cp "$(KERNEL_ELF)" "$(ISO_DIR)/kernel.elf"
	cp "$(KERNEL_ELF)" "$(ISO_DIR)/KERNEL.ELF"
	cp limine.conf "$(ISO_DIR)/limine.conf"
	cp limine.conf "$(ISO_DIR)/LIMINE.CONF"
	cp limine.conf "$(ISO_DIR)/limine.cfg"
	cp limine.conf "$(ISO_DIR)/LIMINE.CFG"
	mkdir -p "$(ISO_DIR)/boot/limine"
	cp limine.conf "$(ISO_DIR)/boot/limine/limine.conf"
	cp limine.conf "$(ISO_DIR)/boot/limine/LIMINE.CONF"
	cp limine.conf "$(ISO_DIR)/boot/limine/limine.cfg"
	cp limine.conf "$(ISO_DIR)/boot/limine/LIMINE.CFG"
	mkdir -p "$(ISO_DIR)/limine"
	cp limine.conf "$(ISO_DIR)/limine/limine.conf"
	cp limine.conf "$(ISO_DIR)/limine/LIMINE.CONF"
	cp limine.conf "$(ISO_DIR)/limine/limine.cfg"
	cp limine.conf "$(ISO_DIR)/limine/LIMINE.CFG"
	cp "$(LIMINE_DIR)/limine-bios.sys" "$(ISO_DIR)/"
	cp "$(LIMINE_DIR)/limine-bios.sys" "$(ISO_DIR)/boot/limine/"
	cp "$(LIMINE_DIR)/limine-bios.sys" "$(ISO_DIR)/limine/"
	cp "$(LIMINE_DIR)/limine-bios-cd.bin" "$(ISO_DIR)/"
	cp "$(LIMINE_DIR)/limine-uefi-cd.bin" "$(ISO_DIR)/"
	mkdir -p "$(ISO_DIR)/EFI/BOOT"
	cp "$(LIMINE_DIR)/BOOTX64.EFI" "$(ISO_DIR)/EFI/BOOT/"
	cp limine.conf "$(ISO_DIR)/EFI/BOOT/limine.conf"
	cp limine.conf "$(ISO_DIR)/EFI/BOOT/LIMINE.CONF"
	cp limine.conf "$(ISO_DIR)/EFI/BOOT/limine.cfg"
	cp limine.conf "$(ISO_DIR)/EFI/BOOT/LIMINE.CFG"
	# Create hybrid BIOS/UEFI ISO
	xorriso -as mkisofs \
	  -b limine-bios-cd.bin \
	  -no-emul-boot -boot-load-size 4 -boot-info-table \
	  --efi-boot limine-uefi-cd.bin \
	  -efi-boot-part --efi-boot-image --protective-msdos-label \
	  "$(ISO_DIR)" -o "$(ISO_IMAGE)"
	# Install Limine to the ISO for BIOS boot
	"$(LIMINE_DIR)/limine" bios-install "$(ISO_IMAGE)"
	@echo "ISO created at $(ISO_IMAGE)"

run: run-bios

run-bios: iso
	qemu-system-x86_64 -m 256M -cdrom "$(ISO_IMAGE)" -boot d -serial stdio

run-uefi: iso
	# Adjust OVMF path if needed for your distro
	qemu-system-x86_64 -m 256M -cdrom "$(ISO_IMAGE)" -boot d -serial stdio -bios /usr/share/OVMF/OVMF_CODE.fd

clean:
	rm -rf "$(BUILD_DIR)" "$(ISO_DIR)"


