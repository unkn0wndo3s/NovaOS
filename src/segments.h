#pragma once

/* GDT selector constants after our GDT setup */
/* Layout: 0x00 null, 0x08 kernel code, 0x10 kernel data, 0x18 user data, 0x20 user code, 0x28 TSS (system) */
#define GDT_SEL_KERNEL_CS 0x08
#define GDT_SEL_KERNEL_DS 0x10
#define GDT_SEL_USER_DS   0x18
#define GDT_SEL_USER_CS   0x20

/* RPL 3 variants */
#define GDT_SEL_USER_CS_R3 (GDT_SEL_USER_CS | 0x3)
#define GDT_SEL_USER_DS_R3 (GDT_SEL_USER_DS | 0x3)


