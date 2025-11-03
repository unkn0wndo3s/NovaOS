#pragma once
#include <stdint.h>

void tty_init(void);
/* Write len bytes from buf to active console/serial; returns bytes written */
int tty_write(const char *buf, uint64_t len);
/* Read up to len bytes into buf (blocking-polling simple); returns bytes read */
int tty_read(char *buf, uint64_t len);
/* Called by keyboard IRQ handler to feed input characters */
void tty_put_key(char ch);


