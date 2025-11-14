#!/usr/bin/env bash
set -euo pipefail

sudo apt-get update
sudo apt-get install -y nasm make qemu-system-x86 python3 build-essential
