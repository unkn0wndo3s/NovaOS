#include <stdint.h>
#include "../drivers/serial.h"
#include "../drivers/timer.h"

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


