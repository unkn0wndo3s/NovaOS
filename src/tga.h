#pragma once
#include <stddef.h>
#include <stdint.h>
#include <stdbool.h>

bool tga_blit_to_fb_from_memory(
    const unsigned char *ptr, int size,
    volatile uint32_t *fb, uint64_t fb_w, uint64_t fb_h, uint64_t fb_pitch_bytes,
    uint32_t dst_x, uint32_t dst_y);

/* Clear framebuffer en ARGB32 (couleur) */
static inline void fb_clear(
    volatile uint32_t *fb, uint64_t fb_w, uint64_t fb_h, uint64_t fb_pitch_bytes,
    uint32_t color)
{
    uint64_t pitch = fb_pitch_bytes / 4;
    for (uint64_t y = 0; y < fb_h; y++) {
        volatile uint32_t *row = fb + y * pitch;
        for (uint64_t x = 0; x < fb_w; x++) row[x] = color;
    }
}

/* Petit délai busy-wait (pas d’IRQ ici) */
static inline void busy_wait(volatile uint64_t iters){
    for (volatile uint64_t i=0;i<iters;i++) __asm__ __volatile__("");
}
