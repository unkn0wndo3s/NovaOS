#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 2 ]]; then
    echo "Usage: $0 <stage2-bin> <output-include>" >&2
    exit 1
fi

stage2_bin="$1"
include_file="$2"

if [[ ! -f "$stage2_bin" ]]; then
    echo "stage2 binary '$stage2_bin' not found" >&2
    exit 1
fi

size=$(stat -c%s "$stage2_bin")
if [[ "$size" -eq 0 ]]; then
    echo "stage2 binary is empty" >&2
    exit 1
fi

sectors=$(( (size + 511) / 512 ))
expected_size=$(( sectors * 512 ))
padding=$(( expected_size - size ))

if [[ $padding -gt 0 ]]; then
    dd if=/dev/zero bs=1 count="$padding" status=none >> "$stage2_bin"
fi

mkdir -p "$(dirname "$include_file")"
printf "%%define STAGE2_SECTORS %d\n" "$sectors" > "$include_file"
