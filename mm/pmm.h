#pragma once
#include <stdint.h>
#include <limine.h>

void pmm_init(volatile struct limine_memmap_response *memmap, uint64_t hhdm_offset);
uint64_t pmm_alloc_page(void);         /* returns physical address of 4KiB page or 0 on failure */
void pmm_free_page(uint64_t phys);
uint64_t pmm_total_pages(void);
uint64_t pmm_used_pages(void);


