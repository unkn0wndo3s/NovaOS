#pragma once
#include <stdint.h>
#include <stddef.h>

/* Load an ELF64 image into the provided user page table (pml4_phys).
 * Maps PT_LOAD segments with appropriate flags, returns entry point in entry_out.
 * Returns 0 on success, -1 on error. */
int elf64_load_image(const uint8_t *image, size_t size, uint64_t pml4_phys, uint64_t *entry_out);


