// Nova OS — Inter TTF rendering via stb_truetype + Limine module
// Freestanding, no libm, custom allocators (arena)

#include <stdint.h>
#include <stddef.h>
#include <limine.h>

// ----------------- Limine requests -----------------
static volatile struct limine_framebuffer_request framebuffer_request = {
    .id = LIMINE_FRAMEBUFFER_REQUEST,
    .revision = 0
};

static volatile struct limine_module_request module_request = {
    .id = LIMINE_MODULE_REQUEST,
    .revision = 0
};

// ----------------- libc minis -----------------
void *memcpy(void *dest, const void *src, size_t n) {
    uint8_t *d = (uint8_t *)dest; const uint8_t *s = (const uint8_t *)src;
    for (size_t i = 0; i < n; i++) d[i] = s[i];
    return dest;
}
void *memset(void *s, int c, size_t n) {
    uint8_t *p = (uint8_t *)s; for (size_t i = 0; i < n; i++) p[i] = (uint8_t)c; return s;
}
void *memmove(void *dest, const void *src, size_t n) {
    uint8_t *d = (uint8_t *)dest; const uint8_t *s = (const uint8_t *)src;
    if (s > d) for (size_t i = 0; i < n; i++) d[i] = s[i];
    else if (s < d) for (size_t i = n; i > 0; i--) d[i-1] = s[i-1];
    return dest;
}
int memcmp(const void *s1, const void *s2, size_t n) {
    const uint8_t *a = (const uint8_t *)s1, *b = (const uint8_t *)s2;
    for (size_t i = 0; i < n; i++) if (a[i] != b[i]) return a[i] < b[i] ? -1 : 1;
    return 0;
}

// ----------------- Halt -----------------
static void hcf(void) { asm ("cli"); for (;;) asm ("hlt"); }

// ----------------- FB helpers -----------------
static inline uint32_t fb_pack_rgb(struct limine_framebuffer *fb,
                                   uint8_t r, uint8_t g, uint8_t b) {
    uint32_t r_mask = (fb->red_mask_size   >= 8) ? (uint32_t)r : ((uint32_t)r >> (8 - fb->red_mask_size));
    uint32_t g_mask = (fb->green_mask_size >= 8) ? (uint32_t)g : ((uint32_t)g >> (8 - fb->green_mask_size));
    uint32_t b_mask = (fb->blue_mask_size  >= 8) ? (uint32_t)b : ((uint32_t)b >> (8 - fb->blue_mask_size));
    r_mask &= (fb->red_mask_size   == 32 ? 0xFFFFFFFFu : ((1u << fb->red_mask_size)   - 1u));
    g_mask &= (fb->green_mask_size == 32 ? 0xFFFFFFFFu : ((1u << fb->green_mask_size) - 1u));
    b_mask &= (fb->blue_mask_size  == 32 ? 0xFFFFFFFFu : ((1u << fb->blue_mask_size)  - 1u));
    return (r_mask << fb->red_mask_shift) |
           (g_mask << fb->green_mask_shift) |
           (b_mask << fb->blue_mask_shift);
}

static inline void put_px(struct limine_framebuffer *fb, uint64_t x, uint64_t y, uint32_t c) {
    if (x >= fb->width || y >= fb->height) return;
    ((uint32_t *)fb->address)[(fb->pitch/4) * y + x] = c;
}

static void blit_alpha_glyph_u8(struct limine_framebuffer *fb,
                                int64_t dst_x, int64_t dst_y,
                                const unsigned char *g, int gw, int gh,
                                uint32_t color) {
    if (!g || gw <= 0 || gh <= 0) return;
    uint8_t r = (uint8_t)((color >> fb->red_mask_shift)   & 0xFF);
    uint8_t gch = (uint8_t)((color >> fb->green_mask_shift) & 0xFF);
    uint8_t b = (uint8_t)((color >> fb->blue_mask_shift)  & 0xFF);
    for (int y = 0; y < gh; y++) {
        int64_t py = dst_y + y;
        if (py < 0 || (uint64_t)py >= fb->height) continue;
        for (int x = 0; x < gw; x++) {
            int64_t px = dst_x + x;
            if (px < 0 || (uint64_t)px >= fb->width) continue;
            uint8_t a = g[y*gw + x]; // 0..255
            if (!a) continue;

            // Simple src-over on opaque bg: just set premultiplied-ish
            // If tu veux un blending correct, lis le pixel, fais lerp.
            uint32_t out =
                ((uint32_t)r << fb->red_mask_shift) |
                ((uint32_t)gch << fb->green_mask_shift) |
                ((uint32_t)b << fb->blue_mask_shift);
            put_px(fb, (uint64_t)px, (uint64_t)py, out);
        }
    }
}

// ----------------- Tiny arena for stb (no malloc) -----------------
static unsigned char TT_ARENA[1024 * 1024]; // 1 MiB (suffisant pour "NOVA OS")
static size_t TT_OFF = 0;
static void *tt_alloc(size_t sz, void *ud) {
    (void)ud;
    sz = (sz + 7) & ~((size_t)7);
    if (TT_OFF + sz > sizeof(TT_ARENA)) return NULL;
    void *p = &TT_ARENA[TT_OFF];
    TT_OFF += sz;
    return p;
}
static void tt_free(void *p, void *ud) { (void)p; (void)ud; }

// ----------------- stb_truetype -----------------
#define STBTT_STATIC
#define STBTT_malloc(x,u) tt_alloc((x),(u))
#define STBTT_free(x,u)   tt_free((x),(u))
#define STB_TRUETYPE_IMPLEMENTATION
#include "stb_truetype.h"

// ----------------- Font utils -----------------
typedef struct {
    const unsigned char *data;
    size_t size;
} file_view;

static const file_view find_module_by_suffix(const char *suffix) {
    const struct limine_module_response *resp = module_request.response;
    if (!resp) return (file_view){0};
    for (uint64_t i = 0; i < resp->module_count; i++) {
        struct limine_file *f = resp->modules[i];
        if (!f || !f->path) continue;
        // match fin de chemin (…/assets/Inter.ttf)
        const char *p = f->path;
        // cherche suffix à la fin
        size_t j = 0; while (suffix[j]) j++;
        size_t k = 0; while (p[k]) k++;
        while (j && k && suffix[j-1] == p[k-1]) { j--; k--; }
        if (j == 0) {
            return (file_view){ (const unsigned char *)f->address, (size_t)f->size };
        }
    }
    return (file_view){0};
}

static int is_space(char c) { return c == ' '; }

// ----------------- Text drawing using Inter.ttf -----------------
static void draw_text_inter_ttf(struct limine_framebuffer *fb,
                                uint64_t x, uint64_t y,
                                const char *text,
                                float pixel_height,
                                uint32_t color,
                                int letter_spacing_px) {
    // Récupère Inter.ttf passé en module Limine
    file_view inter = find_module_by_suffix("/assets/Inter.ttf");
    if (!inter.data || inter.size == 0) return;

    // Init stb font
    stbtt_fontinfo font;
    if (!stbtt_InitFont(&font, inter.data, stbtt_GetFontOffsetForIndex(inter.data, 0))) return;

    float scale = stbtt_ScaleForPixelHeight(&font, pixel_height);

    int ascent, descent, lineGap;
    stbtt_GetFontVMetrics(&font, &ascent, &descent, &lineGap);
    int baseline = (int)(ascent * scale);

    int pen_x = (int)x;
    int pen_y = (int)y + baseline;

    for (const char *p = text; *p; p++) {
        unsigned int code = (unsigned char)*p;
        if (is_space((char)code)) {
            // espace: avance arbitraire ~ 0.5em
            int ax, lsb;
            stbtt_GetCodepointHMetrics(&font, 'n', &ax, &lsb);
            pen_x += (int)(ax * scale * 0.5f) + letter_spacing_px;
            continue;
        }

        int ax, lsb;
        stbtt_GetCodepointHMetrics(&font, (int)code, &ax, &lsb);

        int x0, y0, x1, y1;
        stbtt_GetCodepointBitmapBox(&font, (int)code, scale, scale, &x0, &y0, &x1, &y1);

        int gw = x1 - x0;
        int gh = y1 - y0;
        if (gw > 0 && gh > 0) {
            // raster directement dans un buffer fourni
            unsigned char *bmp = (unsigned char *)tt_alloc((size_t)gw * (size_t)gh, NULL);
            if (bmp) {
                memset(bmp, 0, (size_t)gw * (size_t)gh);
                stbtt_MakeCodepointBitmap(&font, bmp, gw, gh, gw, scale, scale, (int)code);

                int gx = pen_x + (int)(lsb * scale) + x0;
                int gy = pen_y + y0;
                blit_alpha_glyph_u8(fb, gx, gy, bmp, gw, gh, color);
            }
        }

        // Avance + kerning + espacement
        pen_x += (int)(ax * scale);
        if (p[1]) pen_x += (int)(stbtt_GetCodepointKernAdvance(&font, (int)code, (int)(unsigned char)p[1]) * scale);
        pen_x += letter_spacing_px;
    }
}

// Mesure largeur (approx) pour centrer
static uint64_t measure_text_inter_ttf(const unsigned char *data, size_t size,
                                       const char *text, float pixel_height, int letter_spacing_px) {
    stbtt_fontinfo font;
    if (!stbtt_InitFont(&font, data, stbtt_GetFontOffsetForIndex(data, 0))) return 0;

    float scale = stbtt_ScaleForPixelHeight(&font, pixel_height);
    int width = 0;
    for (const char *p = text; *p; p++) {
        if (is_space(*p)) { // espace ~ 0.5em
            int ax, lsb;
            stbtt_GetCodepointHMetrics(&font, 'n', &ax, &lsb);
            width += (int)(ax * scale * 0.5f) + letter_spacing_px;
            continue;
        }
        int ax, lsb;
        stbtt_GetCodepointHMetrics(&font, (int)(unsigned char)*p, &ax, &lsb);
        width += (int)(ax * scale) + letter_spacing_px;
        if (p[1]) width += (int)(stbtt_GetCodepointKernAdvance(&font, (int)(unsigned char)p[0], (int)(unsigned char)p[1]) * scale);
    }
    if (width < 0) width = 0;
    return (uint64_t)width;
}

// ----------------- Entry -----------------
void _start(void) {
    if (framebuffer_request.response == NULL
     || framebuffer_request.response->framebuffer_count < 1) {
        hcf();
    }

    struct limine_framebuffer *fb = framebuffer_request.response->framebuffers[0];

    const char *title = "NOVA OS";

    // Taille “Inter” : hauteur de capes ~ 14*scale pixels. Ici on vise ~100 px.
    float pixel_height = 98.0f;     // ajuste à ton goût
    int letter_spacing = 2;         // px supplémentaires

    // Couleur (blanc)
    uint32_t white = fb_pack_rgb(fb, 0xFF, 0xFF, 0xFF);

    // Mesure pour centrage
    file_view inter = find_module_by_suffix("/assets/Inter.ttf");
    uint64_t text_w = inter.data ? measure_text_inter_ttf(inter.data, inter.size, title, pixel_height, letter_spacing) : 0;
    uint64_t text_h = (uint64_t)(pixel_height); // assez proche

    uint64_t x = (fb->width  > text_w) ? (fb->width  - text_w) / 2 : 0;
    uint64_t y = (fb->height > text_h) ? (fb->height - text_h) / 2 : 0;

    // Render
    draw_text_inter_ttf(fb, x, y, title, pixel_height, white, letter_spacing);

    hcf();
}
