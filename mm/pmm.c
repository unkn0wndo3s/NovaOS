#include <stddef.h>
#include <stdint.h>
#include <limine.h>
#include "../drivers/serial.h"

static uint8_t *bitmap;            /* HHDM-mapped pointer to the bitmap */
static uint64_t bitmap_bytes;
static uint64_t num_pages;
static uint64_t used_pages;
static uint64_t hhdm;

static inline void *hhdm_ptr(uint64_t phys) { return (void *)(phys + hhdm); }

static void bitmap_set(uint64_t idx) { bitmap[idx >> 3] |=  (uint8_t)(1u << (idx & 7)); }
static void bitmap_clr(uint64_t idx) { bitmap[idx >> 3] &= (uint8_t)~(1u << (idx & 7)); }
static int  bitmap_get(uint64_t idx) { return (bitmap[idx >> 3] >> (idx & 7)) & 1u; }

static void mark_region(uint64_t base, uint64_t length, int used) {
    uint64_t start = base >> 12;
    uint64_t end = (base + length + 0xFFF) >> 12;
    if (end > num_pages) end = num_pages;
    for (uint64_t i = start; i < end; i++) {
        if (used) { if (!bitmap_get(i)) { bitmap_set(i); used_pages++; } }
        else { if (bitmap_get(i)) { bitmap_clr(i); used_pages--; } }
    }
}

void pmm_init(volatile struct limine_memmap_response *memmap, uint64_t hhdm_offset) {
    hhdm = hhdm_offset;
    /* determine highest address */
    uint64_t max_addr = 0;
    for (uint64_t i = 0; i < memmap->entry_count; i++) {
        struct limine_memmap_entry *e = memmap->entries[i];
        uint64_t end = e->base + e->length;
        if (end > max_addr) max_addr = end;
    }
    num_pages = (max_addr + 0xFFF) >> 12;
    bitmap_bytes = (num_pages + 7) / 8;

    /* place bitmap in a usable region */
    uint64_t bm_phys = 0;
    for (uint64_t i = 0; i < memmap->entry_count; i++) {
        struct limine_memmap_entry *e = memmap->entries[i];
        if (e->type == LIMINE_MEMMAP_USABLE && e->length >= bitmap_bytes + 0x1000) {
            bm_phys = e->base;
            break;
        }
    }
    if (!bm_phys) {
        serial_write("PMM: no space for bitmap\n");
        for (;;) { __asm__ __volatile__("cli; hlt"); }
    }
    bitmap = (uint8_t *)hhdm_ptr(bm_phys);
    for (uint64_t i = 0; i < bitmap_bytes; i++) bitmap[i] = 0xFF; /* mark used */
    used_pages = num_pages;

    /* free all usable regions */
    for (uint64_t i = 0; i < memmap->entry_count; i++) {
        struct limine_memmap_entry *e = memmap->entries[i];
        if (e->type == LIMINE_MEMMAP_USABLE) {
            mark_region(e->base, e->length, 0);
        }
    }
    /* mark bitmap itself used */
    mark_region(bm_phys, bitmap_bytes, 1);
}

uint64_t pmm_alloc_page(void) {
    for (uint64_t i = 0; i < num_pages; i++) {
        if (!bitmap_get(i)) {
            bitmap_set(i);
            used_pages++;
            return i << 12;
        }
    }
    return 0;
}

void pmm_free_page(uint64_t phys) {
    uint64_t idx = phys >> 12;
    if (idx < num_pages && bitmap_get(idx)) { bitmap_clr(idx); used_pages--; }
}

uint64_t pmm_total_pages(void) { return num_pages; }
uint64_t pmm_used_pages(void) { return used_pages; }


