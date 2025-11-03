#pragma once
#include <stdint.h>
#include <stddef.h>

#define VMM_FLAG_WRITE  (1ull << 1)
#define VMM_FLAG_USER   (1ull << 2)
#define VMM_FLAG_NX     (1ull << 63)

/* Create a new user PML4 that shares the higher-half kernel mappings from the current CR3. */
uint64_t vmm_new_user_pml4(void);

/* Map 'num_pages' 4KiB pages starting at 'phys' to 'virt' in given PML4. Flags are PTE flags. */
int vmm_map_pages_user(uint64_t pml4_phys, uint64_t virt, uint64_t phys, size_t num_pages, uint64_t flags);

/* Switch CR3 to the given PML4 physical address. */
static inline void vmm_switch(uint64_t pml4_phys) {
	__asm__ __volatile__("mov %0, %%cr3" : : "r"(pml4_phys) : "memory");
}


