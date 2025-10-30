#pragma once
#include <stdint.h>
#include <limine.h>

volatile struct limine_memmap_response *get_memmap_response(void);
uint64_t get_hhdm_offset(void);
void get_kernel_phys_range(uint64_t *phys_base, uint64_t *virt_base);


