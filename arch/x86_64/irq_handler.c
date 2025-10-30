#include <stdint.h>
#include "idt.h"
#include "../drivers/serial.h"
#include "../drivers/timer.h"
#include "../drivers/keyboard.h"
#include "../kernel/sched.h"
#include "io.h"

#define PIC1_CMD 0x20
#define PIC2_CMD 0xA0

static void pic_send_eoi(uint8_t vec) {
    if (vec >= 40) outb(PIC2_CMD, 0x20);
    outb(PIC1_CMD, 0x20);
}

void irq_common_handler(struct isr_regs *r) {
    uint64_t vec = r->int_no;
    if (vec == 32) {
        timer_irq0_tick();
        /* Temporarily disable preemptive switch to avoid corrupting return frame */
    } else if (vec == 33) {
        keyboard_irq1();
    }
    pic_send_eoi((uint8_t)vec);
}


