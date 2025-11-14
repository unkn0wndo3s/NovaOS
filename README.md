# NovaOS — Kernel (Developer README)

This branch contains the Nova OS kernel.

This README covers only:
- tools
- installation
- build
- run
- contribution rules

No feature documentation is included here.

## Requirements

Supported system: Linux (Ubuntu recommended)

Mandatory toolchain:
- x86_64-elf-gcc
- binutils
- make

All build commands are executed through the provided .sh scripts.

## Installation

Install dependencies:

./setup.sh

This installs:
- cross compiler
- binutils
- required system packages

## Build

Compile the kernel:

./build.sh

This generates:
- the kernel ELF binary
- required bootable objects

## Run

Run the kernel through QEMU:

./run.sh

The script automatically configures the emulator.

## Contribution Rules

- Kernel must always compile without warnings
- Do not push untested low-level code
- Makefile must remain functional at all times
- Avoid breaking compatibility with the bootloader
- All code must work on a clean Ubuntu installation

## Notes

This branch only contains the kernel. UI, OS logic, and bootloader are not included here.
