#pragma once
#include <stdint.h>

struct isr_regs; /* from idt.h */

void irq_common_handler(struct isr_regs *r);


