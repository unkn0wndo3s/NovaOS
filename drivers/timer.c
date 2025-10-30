#include <stdint.h>
#include "../arch/x86_64/io.h"

#define PIT_CH0 0x40
#define PIT_CMD 0x43
#define PIT_BASE_HZ 1193182

static volatile uint64_t ticks_ms = 0;

void timer_init(uint32_t hz) {
    if (hz == 0) hz = 1000;
    uint16_t divisor = (uint16_t)(PIT_BASE_HZ / hz);
    outb(PIT_CMD, 0x36);           /* ch0, lobyte/hibyte, mode 3 */
    outb(PIT_CH0, (uint8_t)(divisor & 0xFF));
    outb(PIT_CH0, (uint8_t)((divisor >> 8) & 0xFF));

    /* Unmask IRQ0 on master PIC */
    uint8_t mask = inb(0x21);
    outb(0x21, (uint8_t)(mask & ~0x01));
}

void timer_irq0_tick(void) {
    ticks_ms++;
}

uint64_t timer_ticks_ms(void) { return ticks_ms; }

void timer_sleep_ms(uint64_t ms) {
    uint64_t target = ticks_ms + ms;
    while (ticks_ms < target) {
        __asm__ __volatile__("hlt");
    }
}


