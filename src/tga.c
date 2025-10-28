#include <stdint.h>
#include <stdbool.h>
#include <stddef.h>

/* Header TGA minimal (offsets “classiques”) */
static inline uint8_t  rd8 (const unsigned char *p, int off){ return (uint8_t)p[off]; }
static inline uint16_t rd16(const unsigned char *p, int off){ return (uint16_t)(p[off] | (p[off+1]<<8)); }

bool tga_blit_to_fb_from_memory(
    const unsigned char *ptr, int size,
    volatile uint32_t *fb, uint64_t fb_w, uint64_t fb_h, uint64_t fb_pitch_bytes,
    uint32_t dst_x, uint32_t dst_y)
{
    if (!ptr || size < 18 || !fb) return false;

    uint8_t  id_len   = ptr[0];
    uint8_t  cmap_type= ptr[1];
    uint8_t  image_type = ptr[2];
    uint16_t w = ptr[12] | (ptr[13] << 8);
    uint16_t h = ptr[14] | (ptr[15] << 8);
    uint8_t  bpp = ptr[16];
    uint8_t  img_desc = ptr[17];

    if (w == 0 || h == 0) return false;
    if (cmap_type != 0) return false;
    if (image_type != 2) return false;
    if (!(bpp == 24 || bpp == 32)) return false;

    int pixel_offset = 18 + id_len;
    int bytes_per_px = (bpp >> 3);
    int img_bytes = w * h * bytes_per_px;
    if (pixel_offset + img_bytes > size) return false;

    uint64_t fb_pitch = fb_pitch_bytes / 4ULL;

    /* On FORCE l’origine TOP-LEFT */
    for (uint32_t row = 0; row < h; row++) {
        uint32_t src_y = (h - 1 - row); // inversion volontaire
        const unsigned char *src = ptr + pixel_offset + src_y * w * bytes_per_px;

        uint64_t y = (uint64_t)dst_y + row;
        if (y >= fb_h) break;
        volatile uint32_t *dst = fb + y * fb_pitch + dst_x;

        for (uint32_t x = 0; x < w; x++) {
            uint64_t fx = (uint64_t)dst_x + x;
            if (fx >= fb_w) break;

            uint8_t B = src[0], G = src[1], R = src[2];
            uint8_t A = (bytes_per_px == 4) ? src[3] : 0xFF;
            dst[x] = ((uint32_t)A << 24) | ((uint32_t)R << 16) | ((uint32_t)G << 8) | B;

            src += bytes_per_px;
        }
    }
    return true;
}
