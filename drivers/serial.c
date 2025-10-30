#include <stddef.h>
#include <stdint.h>
#include "../arch/x86_64/io.h"

#define COM1 0x3F8

void serial_init(void) {
    outb(COM1 + 1, 0x00);    /* Disable all interrupts */
    outb(COM1 + 3, 0x80);    /* Enable DLAB */
    outb(COM1 + 0, 0x01);    /* Divisor low (115200/1 = 115200) */
    outb(COM1 + 1, 0x00);    /* Divisor high */
    outb(COM1 + 3, 0x03);    /* 8 bits, no parity, one stop bit */
    outb(COM1 + 2, 0xC7);    /* Enable FIFO, clear, 14-byte threshold */
    outb(COM1 + 4, 0x0B);    /* IRQs enabled, RTS/DSR set */
}

static int serial_tx_empty(void) { return inb(COM1 + 5) & 0x20; }

void serial_write_char(char c) {
    if (c == '\n') serial_write_char('\r');
    while (!serial_tx_empty()) { }
    outb(COM1, (uint8_t)c);
}

void serial_write(const char *s) {
    if (!s) return;
    for (; *s; s++) serial_write_char(*s);
}

void serial_write_hex64(uint64_t v) {
    static const char *hex = "0123456789ABCDEF";
    serial_write("0x");
    for (int i = 15; i >= 0; i--) {
        uint8_t nib = (v >> (i * 4)) & 0xF;
        serial_write_char(hex[nib]);
    }
}


