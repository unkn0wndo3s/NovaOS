#pragma once
#include <stdint.h>

void timer_init(uint32_t hz);
uint64_t timer_ticks_ms(void);
void timer_sleep_ms(uint64_t ms);
void timer_irq0_tick(void);


