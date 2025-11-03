#include <stddef.h>
#include <stdint.h>
#include "tty.h"
#include "serial.h"
#include "io.h"

/* Simple stdin ring buffer fed by keyboard IRQ. */
#define TTY_INBUF_SIZE 1024
static volatile char inbuf[TTY_INBUF_SIZE];
static volatile uint32_t in_head = 0; /* write index */
static volatile uint32_t in_tail = 0; /* read index */

void tty_init(void) {
	in_head = in_tail = 0;
}

int tty_write(const char *buf, uint64_t len) {
	if (!buf) return 0;
	for (uint64_t i = 0; i < len; i++) serial_write_char(buf[i]);
	return (int)len;
}

int tty_read(char *buf, uint64_t len) {
	if (!buf || len == 0) return 0;
	uint64_t n = 0;
	for (;;) {
		/* Consume available chars */
		while (n < len) {
			cli();
			uint32_t t = in_tail;
			uint32_t h = in_head;
			if (t == h) { sti(); break; }
			char ch = inbuf[t % TTY_INBUF_SIZE];
			in_tail = (t + 1) % (2 * TTY_INBUF_SIZE); /* safe wrap */
			sti();
			buf[n++] = ch;
			if (ch == '\n') break; /* line-based simple */
		}
		if (n > 0) break;
		/* Busy-wait; CPU will sleep until next IRQ */
		__asm__ __volatile__("hlt");
	}
	return (int)n;
}

void tty_put_key(char ch) {
	/* Echo to serial and enqueue */
	serial_write_char(ch);
	cli();
	uint32_t h = in_head;
	inbuf[h % TTY_INBUF_SIZE] = ch;
	in_head = (h + 1) % (2 * TTY_INBUF_SIZE);
	sti();
}


