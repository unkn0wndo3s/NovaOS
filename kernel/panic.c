#include <stddef.h>
#include <stdint.h>
#include "../drivers/serial.h"
#include "tga.h"
#include "limine_requests.h"

__attribute__((noreturn)) void panic(const char *msg) {
    /* Paint screen red if framebuffer is available */
    struct limine_framebuffer *fb = get_framebuffer0();
    if (fb && fb->address) {
        volatile uint32_t *fb_ptr = (volatile uint32_t*)fb->address;
        fb_clear(fb_ptr, fb->width, fb->height, fb->pitch, 0xFFAA0000);
    }

    serial_write("PANIC: ");
    if (msg) serial_write(msg);
    serial_write("\nSystem halted.\n");
    for (;;) { __asm__ __volatile__("cli; hlt"); }
}


