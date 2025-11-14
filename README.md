# NovaOS — Operating System Layer (Developer README)

This branch contains the Nova OS layer above the kernel (UI, services, high-level logic).

This README documents only:
- installation
- required tools
- build
- run
- contribution rules

No feature documentation is included here.

## Requirements

Official development environment: Ubuntu Linux

Mandatory toolchain:
- x86_64-elf-gcc
- binutils
- make

All build commands are executed through .sh scripts.

## Installation

Install dependencies:

./setup.sh

This installs:
- required toolchain
- system packages needed for building

## Build

Compile the OS layer:

./build.sh

This assembles the components sitting above the kernel.

## Run

Launch the OS test environment:

./run.sh

The emulator is automatically configured by the script.

## Contribution Rules

- OS code must remain compatible with the kernel
- Do not modify core scripts without testing
- Modules must compile without warnings
- Commits must be clean and isolated
- Scripts must work on a clean Ubuntu setup

## Notes

This branch contains only the OS logic. It does not include the kernel or the bootloader.
