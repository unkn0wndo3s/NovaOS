# NovaOS — develop Branch (Integration & Testing)

The develop branch integrates:
- bootloader
- kernel
- OS layer

It is used to test combined behavior across all components.

This README does not document features.

## Requirements

Supported system: Linux (Ubuntu recommended)

Mandatory toolchain:
- x86_64-elf-gcc
- binutils
- make

All commands are handled by .sh scripts.

## Installation

Install required dependencies:

./setup.sh

This prepares the shared cross-compilation environment.

## Build (all components)

Build bootloader + kernel + OS at once:

./build.sh

This ensures:
- all layers compile correctly
- no cross-branch incompatibility is introduced
- the final integrated image is produced

## Run (full system)

Start the full Nova OS system:

./run.sh

The script loads bootloader, kernel, and OS together.

## Contribution Rules

- All layers must always build successfully
- Breaking commits are strictly forbidden
- Never push untested integration logic
- Keep component boundaries clean
- Bootloader, kernel, and OS must remain individually buildable
- Scripts must stay consistent with other branches

## Notes

This branch is not production-ready.  
It is dedicated to integration, testing, and validation before merging into stable branches.
