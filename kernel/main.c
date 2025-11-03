#include <stdint.h>
#include <stddef.h>
#include <stdbool.h>
#include <limine.h>
#include "tga.h"
#include "../drivers/serial.h"
#include "../arch/x86_64/idt.h"
#include "../arch/x86_64/pic.h"
#include "../drivers/timer.h"
#include "limine_requests.h"
#include "../mm/pmm.h"
#include "../mm/heap.h"
#include "../drivers/keyboard.h"
#include "sched.h"
#include "threads.h"
#include "vfs.h"
#include "gdt_tss2.h"
#include "syscall.h"
#include "tty.h"
#include "proc.h"

/* Limine base revision check */
__attribute__((used, section(".limine_requests")))
static volatile LIMINE_BASE_REVISION(4);

/* Anim chargée via initrd (VFS) */

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
    serial_init();
    gdt_tss_init();
    idt_init();
    pic_remap(0x20, 0x28);
    timer_init(1000);
    keyboard_init();
    tty_init();
    syscall_init();
    __asm__ __volatile__("sti");

    if (LIMINE_BASE_REVISION_SUPPORTED == false) hcf();

    /* Init memory: PMM + heap using Limine */
    volatile struct limine_memmap_response *mm = get_memmap_response();
    uint64_t hhdm = get_hhdm_offset();
    pmm_init(mm, hhdm);
    heap_init(hhdm);
    struct limine_framebuffer *fb = get_framebuffer0();
    if (!fb || !fb->address) hcf();
    volatile uint32_t *fb_ptr = (volatile uint32_t*)fb->address;

    /* Monter initrd (module "initrd") en VFS */
    void *initrd_ptr = 0; uint64_t initrd_sz = 0;
    if (!get_module_by_string("initrd", &initrd_ptr, &initrd_sz) || !initrd_ptr || initrd_sz == 0) {
        fb_clear(fb_ptr, fb->width, fb->height, fb->pitch, 0xFF000000);
        hcf();
    }
    serial_write("[initrd] addr="); serial_write_hex64((uint64_t)initrd_ptr); serial_write(", size="); serial_write_hex64(initrd_sz); serial_write("\n");
    vfs_init();
    vfs_mount_cpio_newc(initrd_ptr, (size_t)initrd_sz);
    serial_write("[vfs] mounted cpio newc\n");

    /* Try to load and start /bin/init in userland (if present) */
    proc_spawn_init_from_vfs();

    /* Collecte des frames dans animations/ triées lexicographiquement */
    const struct vfs_node **frames = 0; size_t frames_count = vfs_find_prefix("animations/", &frames);
    serial_write("[vfs] frames_count="); serial_write_hex64((uint64_t)frames_count); serial_write("\n");
    if (frames_count == 0 || !frames) {
        fb_clear(fb_ptr, fb->width, fb->height, fb->pitch, 0xFF000000);
        hcf();
    }

    /* Scheduler and threads */
    sched_init();
    threads_configure_animation(frames, frames_count, fb);
    (void)sched_create(thread_anim, "anim");
    (void)sched_create(thread_log, "log");
    (void)sched_create(thread_idle, "idle");

    /* Let the scheduler run; this thread will be preempted */
    for (;;) { __asm__ __volatile__("hlt"); }
}
