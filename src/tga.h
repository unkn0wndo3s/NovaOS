#pragma once
#include <stdint.h>
#include <stdbool.h>
#include <stddef.h>

/* Décode et BLITTE un TGA (truecolor, non compressé) directement dans le framebuffer.
   Supportés: image_type=2, 24bpp ou 32bpp, avec origine haut-gauche ou bas-gauche.
   - ptr/size: octets du fichier TGA
   - fb: framebuffer Limine (ARGB32)
   - fb_w/fb_h/fb_pitch_bytes: infos framebuffer
   - dst_x/dst_y: position où dessiner
   Retourne true si OK. */
bool tga_blit_to_fb_from_memory(
    const unsigned char *ptr, int size,
    volatile uint32_t *fb, uint64_t fb_w, uint64_t fb_h, uint64_t fb_pitch_bytes,
    uint32_t dst_x, uint32_t dst_y);
