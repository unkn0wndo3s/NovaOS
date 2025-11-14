#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

if [[ ! -f build/novaos.img ]]; then
    ./build.sh
fi

qemu-system-x86_64 -drive format=raw,file=build/novaos.img "$@"
