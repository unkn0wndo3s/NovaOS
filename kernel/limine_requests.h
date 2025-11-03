#pragma once
#include <stdint.h>
#include <limine.h>

volatile struct limine_memmap_response *get_memmap_response(void);
uint64_t get_hhdm_offset(void);
void get_kernel_phys_range(uint64_t *phys_base, uint64_t *virt_base);

/* Modules (e.g., initrd) */
volatile struct limine_module_response *get_module_response(void);
/* Returns true on success and fills out ptr/size if module with matching string is found */
int get_module_by_string(const char *string, void **ptr, uint64_t *size);

/* Framebuffer access */
struct limine_framebuffer *get_framebuffer0(void);


