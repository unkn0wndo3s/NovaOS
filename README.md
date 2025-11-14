# NovaOS — Bootloader (Developer README)

This branch contains the Nova OS custom bootloader responsible for loading the kernel and preparing the system environment.

This document explains:
- Required tools
- How to install them
- How to build
- How to run
- Contribution rules

No feature documentation is included here.

## Requirements

Nova OS bootloader development officially supports Linux (Ubuntu recommended).

Mandatory toolchain:
- x86_64-elf-gcc
- binutils (x86_64-elf target)
- make
- Standard Linux build utilities

All build commands are handled by the provided .sh scripts.

## Installation

Install all dependencies with:

./setup.sh

This installs:
- cross-compiler (x86_64-elf-gcc)
- binutils
- required system packages
- environment preparation

## Build

Compile the bootloader:

./build.sh

This compiles:
- bootloader sources
- required objects
- final binary output

## Run

Start the bootloader in QEMU:

./run.sh

This script launches the emulator with the correct configuration.

## Contribution Rules

- Never hardcode file paths
- Do not modify scripts without testing them
- Makefiles must remain POSIX-compliant
- The bootloader must always compile without warnings
- All changes must remain compatible with a clean Ubuntu install

## Notes

This branch only contains the bootloader logic. Kernel and OS layers are not part of this tree.
