#include <stdint.h>
#include <stddef.h>
#include "../drivers/serial.h"
#include "../drivers/timer.h"
#include "tga.h"
#include "vfs.h"
#include "limine_requests.h"

static const struct vfs_node **anim_frames;
static size_t anim_frames_count;
static struct limine_framebuffer *anim_fb;

void threads_configure_animation(const struct vfs_node **frames, size_t count, struct limine_framebuffer *fb) {
    anim_frames = frames;
    anim_frames_count = count;
    anim_fb = fb;
}

void thread_log(void) {
    for (;;) {
        serial_write("[log] tick ");
        serial_write_hex64(timer_ticks_ms());
        serial_write("\n");
        timer_sleep_ms(500);
    }
}

void thread_idle(void) {
    for (;;) { __asm__ __volatile__("hlt"); }
}

void thread_anim(void) {
    if (!anim_fb || !anim_fb->address || !anim_frames || anim_frames_count == 0) {
        serial_write("[anim] missing resources, exiting anim thread\n");
        for (;;) { __asm__ __volatile__("hlt"); }
    }
    volatile uint32_t *fb_ptr = (volatile uint32_t*)anim_fb->address;
    uint64_t pitch = anim_fb->pitch;
    uint64_t fb_w = anim_fb->width;
    uint64_t fb_h = anim_fb->height;

    uint64_t next_ms = timer_ticks_ms();
    for (;;) {
        for (size_t i = 0; i < anim_frames_count; i++) {
            const unsigned char *p = (const unsigned char*)anim_frames[i]->data;
            int sz = (int)anim_frames[i]->size;
            if (sz < 18 || !p) continue;

            uint16_t w = (uint16_t)(p[12] | (p[13]<<8));
            uint16_t h = (uint16_t)(p[14] | (p[15]<<8));

            uint32_t dx = 0, dy = 0;
            if (fb_w > w) dx = (uint32_t)((fb_w - w) / 2);
            if (fb_h > h) dy = (uint32_t)((fb_h - h) / 2);

            bool ok = tga_blit_to_fb_from_memory(p, sz, fb_ptr, fb_w, fb_h, pitch, dx, dy);
            if (!ok) continue;

            next_ms += 33; /* ~30 FPS */
            while (timer_ticks_ms() < next_ms) { __asm__ __volatile__("hlt"); }
        }
    }
}


