#include <stdint.h>
#include <stddef.h>
#include "elf64.h"
#include "vmm.h"
#include "limine_requests.h"
#include "../mm/pmm.h"

/* ELF64 basics */
struct elf64_ehdr {
	unsigned char e_ident[16];
	uint16_t e_type;
	uint16_t e_machine;
	uint32_t e_version;
	uint64_t e_entry;
	uint64_t e_phoff;
	uint64_t e_shoff;
	uint32_t e_flags;
	uint16_t e_ehsize;
	uint16_t e_phentsize;
	uint16_t e_phnum;
	uint16_t e_shentsize;
	uint16_t e_shnum;
	uint16_t e_shstrndx;
};

struct elf64_phdr {
	uint32_t p_type;
	uint32_t p_flags;
	uint64_t p_offset;
	uint64_t p_vaddr;
	uint64_t p_paddr;
	uint64_t p_filesz;
	uint64_t p_memsz;
	uint64_t p_align;
};

#define PT_LOAD 1u
#define PF_X    1u
#define PF_W    2u
#define PF_R    4u

static int is_valid_elf(const struct elf64_ehdr *eh, size_t size) {
	if (size < sizeof(*eh)) return 0;
	return eh->e_ident[0]==0x7F && eh->e_ident[1]=='E' && eh->e_ident[2]=='L' && eh->e_ident[3]=='F' && eh->e_ident[4]==2 && eh->e_ident[5]==1;
}

int elf64_load_image(const uint8_t *image, size_t size, uint64_t pml4_phys, uint64_t *entry_out) {
	if (!image || size < sizeof(struct elf64_ehdr)) return -1;
	const struct elf64_ehdr *eh = (const struct elf64_ehdr *)image;
	if (!is_valid_elf(eh, size)) return -1;
	if (eh->e_phoff + (uint64_t)eh->e_phnum * eh->e_phentsize > size) return -1;

	/* Load PT_LOAD segments */
	for (uint16_t i = 0; i < eh->e_phnum; i++) {
		const struct elf64_phdr *ph = (const struct elf64_phdr *)(image + eh->e_phoff + (uint64_t)i * eh->e_phentsize);
		if (ph->p_type != PT_LOAD) continue;
		uint64_t vaddr = ph->p_vaddr;
		uint64_t filesz = ph->p_filesz;
		uint64_t memsz  = ph->p_memsz;
		uint64_t off    = ph->p_offset;
		if (off + filesz > size) return -1;
		uint64_t first = vaddr & ~0xFFFull;
		uint64_t last  = (vaddr + memsz + 0xFFF) & ~0xFFFull;
		size_t pages = (size_t)((last - first) >> 12);
		uint64_t flags = VMM_FLAG_USER;
		if (ph->p_flags & PF_W) flags |= VMM_FLAG_WRITE;
		if (!(ph->p_flags & PF_X)) flags |= VMM_FLAG_NX;
		for (size_t p = 0; p < pages; p++) {
			uint64_t phys = pmm_alloc_page();
			if (!phys) return -1;
			if (vmm_map_pages_user(pml4_phys, first + (p<<12), phys, 1, flags) != 0) return -1;
		}
		/* Copy file bytes */
		uint64_t pos = 0;
		while (pos < filesz) {
			uint64_t va = vaddr + pos;
			uint64_t page = va & ~0xFFFull;
			uint64_t off_in_page = va & 0xFFFu;
			uint64_t to_copy = filesz - pos;
			if (to_copy > (0x1000 - off_in_page)) to_copy = 0x1000 - off_in_page;
			/* Find mapped phys: walk PTE */
			uint64_t *pml4 = (uint64_t *)((pml4_phys & 0x000FFFFFFFFFF000ull) + get_hhdm_offset());
			int l4 = (int)((page >> 39) & 0x1FF);
			int l3 = (int)((page >> 30) & 0x1FF);
			int l2 = (int)((page >> 21) & 0x1FF);
			int l1 = (int)((page >> 12) & 0x1FF);
			uint64_t pml3 = pml4[l4] & 0x000FFFFFFFFFF000ull;
			uint64_t *pt3 = (uint64_t *)(pml3 + get_hhdm_offset());
			uint64_t pml2 = pt3[l3] & 0x000FFFFFFFFFF000ull;
			uint64_t *pt2 = (uint64_t *)(pml2 + get_hhdm_offset());
			uint64_t pml1 = pt2[l2] & 0x000FFFFFFFFFF000ull;
			uint64_t *pt1 = (uint64_t *)(pml1 + get_hhdm_offset());
			uint64_t pte  = pt1[l1];
			uint64_t phys = pte & 0x000FFFFFFFFFF000ull;
			uint8_t *dst = (uint8_t *)(phys + get_hhdm_offset() + off_in_page);
			const uint8_t *src = image + off + pos;
			for (uint64_t k = 0; k < to_copy; k++) dst[k] = src[k];
			pos += to_copy;
		}
		/* Zero remainder up to memsz */
		for (uint64_t posz = filesz; posz < memsz; posz++) {
			uint64_t va = vaddr + posz;
			uint64_t phys;
			uint64_t page = va & ~0xFFFull;
			int l4 = (int)((page >> 39) & 0x1FF);
			int l3 = (int)((page >> 30) & 0x1FF);
			int l2 = (int)((page >> 21) & 0x1FF);
			int l1 = (int)((page >> 12) & 0x1FF);
			uint64_t *pml4 = (uint64_t *)((pml4_phys & 0x000FFFFFFFFFF000ull) + get_hhdm_offset());
			uint64_t *pt3 = (uint64_t *)(((pml4[l4] & 0x000FFFFFFFFFF000ull) + get_hhdm_offset()));
			uint64_t *pt2 = (uint64_t *)(((pt3[l3] & 0x000FFFFFFFFFF000ull) + get_hhdm_offset()));
			uint64_t *pt1 = (uint64_t *)(((pt2[l2] & 0x000FFFFFFFFFF000ull) + get_hhdm_offset()));
			phys = pt1[l1] & 0x000FFFFFFFFFF000ull;
			uint8_t *dst = (uint8_t *)(phys + get_hhdm_offset() + (va & 0xFFFu));
			*dst = 0;
		}
	}

	if (entry_out) *entry_out = eh->e_entry;
	return 0;
}


