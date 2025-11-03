#include <stdint.h>
#include "segments.h"

struct __attribute__((packed)) gdtr {
	uint16_t limit;
	uint64_t base;
};

/* 64-bit TSS */
struct __attribute__((packed)) tss64 {
	uint32_t reserved0;
	uint64_t rsp0;
	uint64_t rsp1;
	uint64_t rsp2;
	uint64_t reserved1;
	uint64_t ist1;
	uint64_t ist2;
	uint64_t ist3;
	uint64_t ist4;
	uint64_t ist5;
	uint64_t ist6;
	uint64_t ist7;
	uint64_t reserved2;
	uint16_t reserved3;
	uint16_t iomap_base;
};

static struct tss64 tss;

/* GDT entry representation (64-bit). */
static uint64_t gdt[7];

static uint64_t gdt_make_code(uint8_t dpl) {
	/* Base=0, Limit=0, G=0; type=0xA (code, read), S=1, L=1, D=0, P=1 */
	uint64_t e = 0;
	/* type(4)=1010b */
	e |= (uint64_t)0xA << 40;
	/* S=1 */
	e |= (uint64_t)1 << 44;
	/* DPL */
	e |= (uint64_t)(dpl & 3) << 45;
	/* P=1 */
	e |= (uint64_t)1 << 47;
	/* L=1 (bit 53) */
	e |= (uint64_t)1 << 53;
	return e;
}

static uint64_t gdt_make_data(uint8_t dpl) {
	/* type=0x2 (data, write), S=1, P=1 */
	uint64_t e = 0;
	e |= (uint64_t)0x2 << 40;
	e |= (uint64_t)1 << 44;
	e |= (uint64_t)(dpl & 3) << 45;
	e |= (uint64_t)1 << 47;
	return e;
}

static void gdt_set_tss(int idx, uint64_t base, uint32_t limit) {
	/* TSS descriptor is 16 bytes spanning two entries */
	uint64_t lo = 0, hi = 0;
	lo |= (limit & 0xFFFFu);
	lo |= (base & 0xFFFFFFull) << 16;
	lo |= (uint64_t)0x9 << 40; /* type=9 (available 64-bit TSS) */
	lo |= (uint64_t)1 << 47;   /* P=1 */
	lo |= ((limit >> 16) & 0xFu) << 48;
	lo |= (base & 0xFF000000ull) << 32;
	/* High dword has base[63:32] */
	hi = (base >> 32);
	/* Write into gdt */
	gdt[idx] = lo;
	gdt[idx+1] = hi;
}

void gdt_tss_init(void) {
	/* Zero GDT */
	for (int i = 0; i < 7; i++) gdt[i] = 0;
	/* Kernel code/data, user data/code */
	gdt[1] = gdt_make_code(0);           /* 0x08 */
	gdt[2] = gdt_make_data(0);           /* 0x10 */
	gdt[3] = gdt_make_data(3);           /* 0x18 */
	gdt[4] = gdt_make_code(3);           /* 0x20 */

	/* TSS */
	for (int i = 0; i < (int)sizeof(tss)/8; i++) ((uint64_t*)&tss)[i] = 0;
	tss.iomap_base = (uint16_t)sizeof(tss);
	gdt_set_tss(5, (uint64_t)(uintptr_t)&tss, (uint32_t)sizeof(tss)-1);

	struct gdtr gdtr;
	gdtr.limit = (uint16_t)(sizeof(gdt) - 1);
	gdtr.base = (uint64_t)(uintptr_t)&gdt[0];
	__asm__ __volatile__("lgdt %0" : : "m"(gdtr));

	/* Load segments: set DS/ES/SS to kernel data, CS via far return */
	uint16_t kds = GDT_SEL_KERNEL_DS;
	__asm__ __volatile__(
		"mov %0, %%ds\n\t"
		"mov %0, %%es\n\t"
		"mov %0, %%ss\n\t"
		: : "r"(kds) : "memory");

	/* Far jump to load CS */
	__asm__ __volatile__(
		"pushq %[cs];\n\t"
		"leaq 1f(%%rip), %%rax;\n\t"
		"pushq %%rax;\n\t"
		"lretq;\n\t"
		"1:" : : [cs] "i"(GDT_SEL_KERNEL_CS) : "rax", "memory");

	/* Load TR with TSS selector (0x28) */
	uint16_t tss_sel = 0x28; /* index 5 << 3 */
	__asm__ __volatile__("ltr %0" : : "r"(tss_sel));
}

void tss_set_rsp0(uint64_t rsp0) {
	tss.rsp0 = rsp0;
}


