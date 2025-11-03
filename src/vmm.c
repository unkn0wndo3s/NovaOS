#include <stdint.h>
#include <stddef.h>
#include "vmm.h"
#include "limine_requests.h"
#include "../mm/pmm.h"

static inline void *hhdm_ptr(uint64_t phys) {
	return (void *)(phys + get_hhdm_offset());
}

/* Page table entry flags */
#define PTE_P   (1ull << 0)
#define PTE_W   (1ull << 1)
#define PTE_U   (1ull << 2)
#define PTE_NX  (1ull << 63)

static uint64_t make_flags(uint64_t flags) {
	uint64_t f = PTE_P;
	if (flags & VMM_FLAG_WRITE) f |= PTE_W;
	if (flags & VMM_FLAG_USER)  f |= PTE_U;
	if (flags & VMM_FLAG_NX)    f |= PTE_NX;
	return f;
}

/* Allocate a zeroed page table */
static uint64_t alloc_pt(void) {
	uint64_t phys = pmm_alloc_page();
	if (!phys) return 0;
	uint64_t *p = (uint64_t *)hhdm_ptr(phys);
	for (int i = 0; i < 512; i++) p[i] = 0;
	return phys;
}

/* Get or create next-level table; 'index' selects 9-bit index at that level. */
static uint64_t get_next(uint64_t table_phys, int index, int user) {
	uint64_t *tbl = (uint64_t *)hhdm_ptr(table_phys);
	uint64_t e = tbl[index];
	if (!(e & PTE_P)) {
		uint64_t new_phys = alloc_pt();
		if (!new_phys) return 0;
		uint64_t flags = PTE_P | PTE_W;
		if (user) flags |= PTE_U;
		tbl[index] = (new_phys & 0x000FFFFFFFFFF000ull) | flags;
		return new_phys;
	}
	return e & 0x000FFFFFFFFFF000ull;
}

uint64_t vmm_new_user_pml4(void) {
	/* Clone higher-half kernel mappings from current CR3 */
	uint64_t cur_cr3;
	__asm__ __volatile__("mov %%cr3, %0" : "=r"(cur_cr3));
	uint64_t *cur_pml4 = (uint64_t *)hhdm_ptr(cur_cr3 & 0x000FFFFFFFFFF000ull);
	uint64_t new_pml4_phys = alloc_pt();
	if (!new_pml4_phys) return 0;
	uint64_t *new_pml4 = (uint64_t *)hhdm_ptr(new_pml4_phys);
	/* Zeroed by alloc_pt; copy entries 256..511 (higher half) */
	for (int i = 256; i < 512; i++) new_pml4[i] = cur_pml4[i];
	return new_pml4_phys;
}

int vmm_map_pages_user(uint64_t pml4_phys, uint64_t virt, uint64_t phys, size_t num_pages, uint64_t flags) {
	uint64_t pml4e = pml4_phys;
	for (size_t p = 0; p < num_pages; p++) {
		uint64_t v = virt + (p << 12);
		uint64_t pa = phys + (p << 12);
		int l4 = (int)((v >> 39) & 0x1FF);
		int l3 = (int)((v >> 30) & 0x1FF);
		int l2 = (int)((v >> 21) & 0x1FF);
		int l1 = (int)((v >> 12) & 0x1FF);
		uint64_t pml3 = get_next(pml4e, l4, 1);
		if (!pml3) return -1;
		uint64_t pml2 = get_next(pml3, l3, 1);
		if (!pml2) return -1;
		uint64_t pml1 = get_next(pml2, l2, 1);
		if (!pml1) return -1;
		uint64_t *pt1 = (uint64_t *)hhdm_ptr(pml1);
		uint64_t f = make_flags(flags);
		pt1[l1] = (pa & 0x000FFFFFFFFFF000ull) | f;
	}
	return 0;
}


