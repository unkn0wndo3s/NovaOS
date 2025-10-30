#include <stddef.h>
#include <stdint.h>
#include "pmm.h"

struct alloc_hdr { uint64_t pages; };
static uint64_t hhdm_off;

static inline void *hhdm_ptr(uint64_t phys) { return (void *)(phys + hhdm_off); }
static inline uint64_t ptr_phys(void *ptr) { return (uint64_t)ptr - hhdm_off; }

void heap_init(uint64_t hhdm_offset) { hhdm_off = hhdm_offset; }

void *kmalloc(size_t size) {
    size_t total = size + sizeof(struct alloc_hdr);
    uint64_t pages = (total + 0xFFF) >> 12;
    if (pages == 0) pages = 1;
    uint64_t first_phys = 0;
    /* allocate pages contiguously (naive) */
    for (uint64_t i = 0; i < pages; i++) {
        uint64_t p = pmm_alloc_page();
        if (!p) return NULL;
        if (i == 0) first_phys = p;
        else if (p != first_phys + (i << 12)) { /* not contiguous: fail simplistic impl */
            /* free what we allocated */
            for (uint64_t j = 0; j <= i; j++) pmm_free_page(first_phys + (j << 12));
            return NULL;
        }
    }
    struct alloc_hdr *h = (struct alloc_hdr *)hhdm_ptr(first_phys);
    h->pages = pages;
    return (void *)((uint8_t *)h + sizeof(struct alloc_hdr));
}

void kfree(void *ptr) {
    if (!ptr) return;
    struct alloc_hdr *h = (struct alloc_hdr *)((uint8_t *)ptr - sizeof(struct alloc_hdr));
    uint64_t first_phys = ptr_phys(h);
    for (uint64_t i = 0; i < h->pages; i++) pmm_free_page(first_phys + (i << 12));
}


