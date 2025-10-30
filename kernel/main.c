#include <stdint.h>
#include <stddef.h>
#include <stdbool.h>
#include <limine.h>
#include "tga.h"

/* Limine requests */
__attribute__((used, section(".limine_requests")))
static volatile LIMINE_BASE_REVISION(4);

__attribute__((used, section(".limine_requests")))
static volatile struct limine_framebuffer_request framebuffer_request = {
    .id = LIMINE_FRAMEBUFFER_REQUEST,
    .revision = 0
};
__attribute__((used, section(".limine_requests_start")))
static volatile LIMINE_REQUESTS_START_MARKER;
__attribute__((used, section(".limine_requests_end")))
static volatile LIMINE_REQUESTS_END_MARKER;

/* Anim data générée */
extern const unsigned int ANIM_FRAMES_COUNT;
extern const unsigned char *ANIM_FRAMES[];
extern const unsigned int ANIM_FRAME_SIZES[];

static void hcf(void){ for(;;){ __asm__ __volatile__("hlt"); } }

/* mini libc freestanding */
void *memcpy(void *d, const void *s, size_t n){ uint8_t *pd=d; const uint8_t *ps=s; for(size_t i=0;i<n;i++) pd[i]=ps[i]; return d; }
void *memset(void *s, int c, size_t n){ uint8_t *p=s; for(size_t i=0;i<n;i++) p[i]=(uint8_t)c; return s; }
void *memmove(void *d, const void *s, size_t n){
    uint8_t *pd=d; const uint8_t *ps=s;
    if (ps>pd) for(size_t i=0;i<n;i++) pd[i]=ps[i];
    else if (ps<pd) for(size_t i=n;i>0;i--) pd[i-1]=ps[i-1];
    return d;
}
int memcmp(const void *a,const void *b,size_t n){
    const uint8_t *p1=a,*p2=b; for(size_t i=0;i<n;i++){ if(p1[i]!=p2[i]) return p1[i]<p2[i]?-1:1; } return 0;
}

void kmain(void) {
    if (LIMINE_BASE_REVISION_SUPPORTED == false) hcf();
    if (!framebuffer_request.response || framebuffer_request.response->framebuffer_count < 1) hcf();

    struct limine_framebuffer *fb = framebuffer_request.response->framebuffers[0];
    volatile uint32_t *fb_ptr = (volatile uint32_t*)fb->address;

    /* Si aucune frame -> noir et stop (pas d’écran rose) */
    if (ANIM_FRAMES_COUNT == 0) {
        fb_clear(fb_ptr, fb->width, fb->height, fb->pitch, 0xFF000000);
        hcf();
    }

    for (;;) {
        for (unsigned int i = 0; i < ANIM_FRAMES_COUNT; i++) {
            const unsigned char *p = ANIM_FRAMES[i];
            int sz = (int)ANIM_FRAME_SIZES[i];
            if (sz < 18) continue;

            uint16_t w = (uint16_t)(p[12] | (p[13]<<8));
            uint16_t h = (uint16_t)(p[14] | (p[15]<<8));

            uint32_t dx = 0, dy = 0;
            if (fb->width  > w) dx = (fb->width  - w) / 2;
            if (fb->height > h) dy = (fb->height - h) / 2;

            /* pas de flash noir à chaque frame -> commente si tu veux un clear */
            // fb_clear(fb_ptr, fb->width, fb->height, fb->pitch, 0xFF000000);

            bool ok = tga_blit_to_fb_from_memory(p, sz, fb_ptr, fb->width, fb->height, fb->pitch, dx, dy);
            if (!ok) {
                /* frame non supportée (probable RLE) -> on la saute */
                continue;
            }

            busy_wait(8000000ULL); /* ajuste la vitesse */
        }
    }
}
