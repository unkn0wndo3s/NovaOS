# NovaOS — Bootloader (Developer README)

This branch contains the **Nova OS custom bootloader**, responsible for loading the kernel and preparing the system environment.

This document explains:
- Required tools  
- How to install them  
- How to build  
- How to run  
- Contribution rules  

No feature documentation is included here.

---

## 📦 Requirements

Nova OS bootloader development officially supports **Linux (Ubuntu recommended)**.

### Mandatory toolchain
- **x86_64-elf-gcc**
- **binutils** (target: x86_64-elf)
- **make**
- Standard Linux build utilities

All commands are already handled by provided `.sh` files.

---

## 🔧 Installation

Run the setup script:

```bash
./setup.sh
