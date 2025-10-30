#include <stddef.h>
#include "../drivers/serial.h"

__attribute__((noreturn)) void panic(const char *msg) {
    serial_write("PANIC: ");
    if (msg) serial_write(msg);
    serial_write("\nSystem halted.\n");
    for (;;) { __asm__ __volatile__("cli; hlt"); }
}


