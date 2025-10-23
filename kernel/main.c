// Nova OS — GIF player via libnsgif (C99, Limine 10.x)
// - Décode avec libnsgif (API nsgif_*), output 32bpp R8G8B8A8
// - Rendu centré dans le framebuffer Limine, damier sous alpha=0
// - Respect du délai par frame (centisecondes -> ms)
// - Aucun malloc système : petit arena statique

#include <stdint.h>
#include <stddef.h>
#include <limine.h>

#include "nsgif.h"  // fourni par third_party/libnsgif/include

/* ---------- Limine requests ---------- */
static volatile struct limine_framebuffer_request fb_req = {
    .id = LIMINE_FRAMEBUFFER_REQUEST, .revision = 0
};
static volatile struct limine_module_request mod_req = {
    .id = LIMINE_MODULE_REQUEST, .revision = 0
};

/* ---------- mini-libc ---------- */
static void *memcpy(void *d, const void *s, size_t n){
    uint8_t*D=(uint8_t*)d; const uint8_t*S=(const uint8_t*)s;
    for(size_t i=0;i<n;i++) D[i]=S[i]; return d;
}
static int memcmp(const void *a, const void *b, size_t n){
    const uint8_t*A=(const uint8_t*)a,*B=(const uint8_t*)b;
    for(size_t i=0;i<n;i++){ if(A[i]!=B[i]) return A[i]<B[i]?-1:1; } return 0;
}
static void hcf(void){ __asm__ __volatile__("cli"); for(;;) __asm__ __volatile__("hlt"); }

/* ---------- bump allocator (freestanding) pour les bitmaps libnsgif ---------- */
static uint8_t ARENA[16*1024*1024];
static size_t  AOFF = 0;
static void *AALLOC(size_t n){
    n = (n + 7u) & ~7u;
    if (AOFF + n > sizeof(ARENA)) return (void*)0;
    void *p = ARENA + AOFF; AOFF += n; return p;
}

/* ---------- framebuffer utils ---------- */
static inline uint32_t fb_pack(struct limine_framebuffer *fb, uint8_t r, uint8_t g, uint8_t b){
    uint32_t R=r,G=g,B=b;
    if (fb->red_mask_size  < 8) R >>= (8 - fb->red_mask_size);
    if (fb->green_mask_size< 8) G >>= (8 - fb->green_mask_size);
    if (fb->blue_mask_size < 8) B >>= (8 - fb->blue_mask_size);
    if (fb->red_mask_size  !=32) R &= ((1u<<fb->red_mask_size)-1u);
    if (fb->green_mask_size!=32) G &= ((1u<<fb->green_mask_size)-1u);
    if (fb->blue_mask_size !=32) B &= ((1u<<fb->blue_mask_size)-1u);
    return (R<<fb->red_mask_shift)|(G<<fb->green_mask_shift)|(B<<fb->blue_mask_shift);
}

static inline void put_px_raw(struct limine_framebuffer *fb, uint64_t x, uint64_t y, uint32_t rgb){
    if (x>=fb->width || y>=fb->height) return;
    uint32_t bpp = fb->bpp ? fb->bpp : 32;
    uint32_t bytes = (bpp + 7u)/8u;
    uint8_t *base = (uint8_t*)fb->address + y*fb->pitch + x*bytes;
    if (bytes >= 4){
        base[0]=(uint8_t)(rgb>>0); base[1]=(uint8_t)(rgb>>8);
        base[2]=(uint8_t)(rgb>>16); base[3]=(uint8_t)(rgb>>24);
    } else if (bytes == 3){
        base[0]=(uint8_t)(rgb>>0); base[1]=(uint8_t)(rgb>>8); base[2]=(uint8_t)(rgb>>16);
    } else if (bytes == 2){
        base[0]=(uint8_t)(rgb>>0); base[1]=(uint8_t)(rgb>>8);
    } else { base[0]=(uint8_t)(rgb & 0xFFu); }
}

static inline void put_px(struct limine_framebuffer *fb, uint64_t x, uint64_t y, uint8_t r, uint8_t g, uint8_t b){
    put_px_raw(fb, x, y, fb_pack(fb, r, g, b));
}

static void fill(struct limine_framebuffer *fb, uint8_t r, uint8_t g, uint8_t b){
    uint32_t rgb = fb_pack(fb,r,g,b);
    for (uint64_t y=0; y<fb->height; y++){
        uint8_t *row = (uint8_t*)fb->address + y*fb->pitch;
        uint32_t bpp = fb->bpp ? fb->bpp : 32;
        uint32_t bytes = (bpp + 7u)/8u;
        for (uint64_t x=0; x<fb->width; x++){
            if (bytes>=4){ ((uint32_t*)row)[x] = rgb; }
            else put_px_raw(fb,x,y,rgb);
        }
    }
}

static inline uint32_t checker_rgb(struct limine_framebuffer *fb, int x, int y){
    int tile = (((y >> 2) + (x >> 2)) & 1);
    return fb_pack(fb, tile ? 0x7F : 0x00, tile ? 0x7F : 0x00, tile ? 0x7F : 0x00);
}

static void blit_center_R8G8B8A8(struct limine_framebuffer *fb, const uint8_t *rgba, int w, int h){
    if (!rgba || w<=0 || h<=0) return;
    int dx = (fb->width  > (uint64_t)w) ? (int)((fb->width  - (uint64_t)w)/2) : 0;
    int dy = (fb->height > (uint64_t)h) ? (int)((fb->height - (uint64_t)h)/2) : 0;
    for (int y=0; y<h; y++){
        int py = dy + y; if (py<0 || (uint64_t)py>=fb->height) continue;
        const uint8_t *src = rgba + (size_t)y*(size_t)w*4u;
        for (int x=0; x<w; x++){
            int px = dx + x; if (px<0 || (uint64_t)px>=fb->width) continue;
            uint8_t R=src[4u*(size_t)x+0], G=src[4u*(size_t)x+1], B=src[4u*(size_t)x+2], A=src[4u*(size_t)x+3];
            if (A) put_px(fb,(uint64_t)px,(uint64_t)py,R,G,B);
            else   put_px_raw(fb,(uint64_t)px,(uint64_t)py, checker_rgb(fb, px, py));
        }
    }
}

static void spin_ms(uint32_t ms){
    volatile uint64_t spins=(uint64_t)ms*250000ull;
    for(uint64_t i=0;i<spins;i++){ __asm__ __volatile__("":::"memory"); }
}

/* ---------- libnsgif: callbacks bitmap ---------- */
/* libnsgif décode toujours en 32bpp ; on choisit l’ordre R8G8B8A8 pour simplicité */
static nsgif_bitmap_t *bm_create(int w, int h){
    size_t sz = (size_t)w * (size_t)h * 4u;
    return AALLOC(sz); /* zone renvoyée = buffer pixels */
}
static void bm_destroy(nsgif_bitmap_t *bitmap){ (void)bitmap; /* no-op */ }
static uint8_t *bm_get_buffer(nsgif_bitmap_t *bitmap){ return (uint8_t*)bitmap; }
static void bm_modified(nsgif_bitmap_t *bitmap){ (void)bitmap; /* no-op */ }

/* ---------- entry ---------- */
void _start(void){
    if(!fb_req.response || fb_req.response->framebuffer_count<1) hcf();
    struct limine_framebuffer *fb = fb_req.response->framebuffers[0];

    /* Diag framebuffer : vert OK, bande jaune si bpp != 32 */
    fill(fb, 0, 120, 0);
    if (fb->bpp && fb->bpp != 32){
        for (uint64_t y=0; y<fb->height/6; y++)
            for (uint64_t x=0; x<fb->width; x++) put_px(fb,x,y,200,200,0);
    }
    spin_ms(120);

    /* Récupération du 1er module Limine (GIF) */
    if (!mod_req.response || mod_req.response->module_count == 0){
        fill(fb, 180, 0, 180); hcf(); // magenta: aucun module
    }
    struct limine_file *f = mod_req.response->modules[0];
    if (!f || !f->address || !f->size){
        fill(fb, 180, 0, 180); hcf();
    }
    const unsigned char *gif_bytes = (const unsigned char*)f->address;
    size_t gif_size = (size_t)f->size;

    /* Fond damier (comme example.c) */
    for (uint64_t y=0; y<fb->height; y++)
        for (uint64_t x=0; x<fb->width; x++)
            put_px_raw(fb, x, y, checker_rgb(fb, (int)x, (int)y));

    /* --- libnsgif setup --- */
    nsgif_bitmap_cb_vt cb = {
        .create     = bm_create,
        .destroy    = bm_destroy,
        .get_buffer = bm_get_buffer,
        .modified   = bm_modified
    };

    nsgif_t *gif = NULL;
    nsgif_error err = nsgif_create(&cb, NSGIF_BITMAP_FMT_R8G8B8A8, &gif);
    if (err != NSGIF_OK || !gif){ fill(fb,180,0,0); hcf(); }

    /* On indique toutes les données d’un coup (déjà en mémoire via Limine) */
    err = nsgif_data_scan(gif, gif_size, gif_bytes);
    if (err != NSGIF_OK){ fill(fb,180,0,0); hcf(); }
    nsgif_data_complete(gif); /* optionnel mais conseillé */

    /* Boucle d’animation façon example.c */
    for(;;){
        nsgif_rect_t area;
        uint32_t delay_cs;
        uint32_t frame_new;
        err = nsgif_frame_prepare(gif, &area, &delay_cs, &frame_new);
        if (err == NSGIF_ERR_ANIMATION_END){
            /* L’animation a une fin → recommencer depuis le début */
            nsgif_reset(gif);
            continue;
        }
        if (err != NSGIF_OK){
            fill(fb,180,0,0); hcf();
        }

        nsgif_bitmap_t *bitmap = NULL;
        err = nsgif_frame_decode(gif, frame_new, &bitmap);
        if (err != NSGIF_OK){
            fill(fb,180,0,0); hcf();
        }

        /* bitmap pointe sur notre buffer R8G8B8A8 (via callbacks) */
        const uint8_t *rgba = bm_get_buffer(bitmap);
        const nsgif_info_t *info = nsgif_get_info(gif);
        if (!info){ fill(fb,180,0,0); hcf(); }
        blit_center_R8G8B8A8(fb, rgba, (int)info->width, (int)info->height);

        /* Délai (centisecondes → ms). NSGIF_INFINITE => image fixe */
        uint32_t ms = (delay_cs == NSGIF_INFINITE) ? 1000u : (delay_cs*10u);
        if (ms == 0) ms = 33u;
        spin_ms(ms);
    }

    /* unreachable */
    // nsgif_destroy(gif);
    // hcf();
}
