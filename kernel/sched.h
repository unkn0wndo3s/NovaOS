#pragma once
#include <stdint.h>
#include "../arch/x86_64/idt.h"

typedef void (*task_entry_t)(void);

void sched_init(void);
int  sched_create(task_entry_t entry, const char *name);
void scheduler_on_tick(struct isr_regs *r);


