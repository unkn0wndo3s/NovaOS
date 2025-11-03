#pragma once
#include <stdint.h>

/* Initialize GDT with kernel/user segments and a single TSS; load TR. */
void gdt_tss_init(void);

/* Update TSS.rsp0 (kernel stack used when interrupting from ring 3). */
void tss_set_rsp0(uint64_t rsp0);


