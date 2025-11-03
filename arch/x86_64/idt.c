#include "idt.h"
#include "segments.h"

static struct idt_entry idt[256];
static struct idt_ptr idtr;

extern void isr_stub_0(void);
extern void isr_stub_1(void);
extern void isr_stub_2(void);
extern void isr_stub_3(void);
extern void isr_stub_4(void);
extern void isr_stub_5(void);
extern void isr_stub_6(void);
extern void isr_stub_7(void);
extern void isr_stub_8(void);
extern void isr_stub_9(void);
extern void isr_stub_10(void);
extern void isr_stub_11(void);
extern void isr_stub_12(void);
extern void isr_stub_13(void);
extern void isr_stub_14(void);
extern void isr_stub_15(void);
extern void isr_stub_16(void);
extern void isr_stub_17(void);
extern void isr_stub_18(void);
extern void isr_stub_19(void);
extern void isr_stub_20(void);
extern void isr_stub_21(void);
extern void isr_stub_22(void);
extern void isr_stub_23(void);
extern void isr_stub_24(void);
extern void isr_stub_25(void);
extern void isr_stub_26(void);
extern void isr_stub_27(void);
extern void isr_stub_28(void);
extern void isr_stub_29(void);
extern void isr_stub_30(void);
extern void isr_stub_31(void);
extern void irq_stub_32(void);
extern void irq_stub_33(void);

static void set_gate(int n, void *isr, uint8_t type_attr) {
    uint64_t off = (uint64_t)isr;
    idt[n].offset_low = (uint16_t)(off & 0xFFFF);
    idt[n].selector = GDT_SEL_KERNEL_CS; /* kernel code selector */
    idt[n].ist = 0;
    idt[n].type_attr = type_attr; /* present, DPL=0, type=0xE */
    idt[n].offset_mid = (uint16_t)((off >> 16) & 0xFFFF);
    idt[n].offset_high = (uint32_t)((off >> 32) & 0xFFFFFFFF);
    idt[n].zero = 0;
}

void idt_init(void) {
    for (int i = 0; i < 256; i++) {
        idt[i].offset_low = 0;
        idt[i].selector = GDT_SEL_KERNEL_CS;
        idt[i].ist = 0;
        idt[i].type_attr = 0x8E; /* present interrupt gate */
        idt[i].offset_mid = 0;
        idt[i].offset_high = 0;
        idt[i].zero = 0;
    }

    set_gate(0,  isr_stub_0,  0x8E);
    set_gate(1,  isr_stub_1,  0x8E);
    set_gate(2,  isr_stub_2,  0x8E);
    set_gate(3,  isr_stub_3,  0x8E);
    set_gate(4,  isr_stub_4,  0x8E);
    set_gate(5,  isr_stub_5,  0x8E);
    set_gate(6,  isr_stub_6,  0x8E);
    set_gate(7,  isr_stub_7,  0x8E);
    set_gate(8,  isr_stub_8,  0x8E);
    set_gate(9,  isr_stub_9,  0x8E);
    set_gate(10, isr_stub_10, 0x8E);
    set_gate(11, isr_stub_11, 0x8E);
    set_gate(12, isr_stub_12, 0x8E);
    set_gate(13, isr_stub_13, 0x8E);
    set_gate(14, isr_stub_14, 0x8E);
    set_gate(15, isr_stub_15, 0x8E);
    set_gate(16, isr_stub_16, 0x8E);
    set_gate(17, isr_stub_17, 0x8E);
    set_gate(18, isr_stub_18, 0x8E);
    set_gate(19, isr_stub_19, 0x8E);
    set_gate(20, isr_stub_20, 0x8E);
    set_gate(21, isr_stub_21, 0x8E);
    set_gate(22, isr_stub_22, 0x8E);
    set_gate(23, isr_stub_23, 0x8E);
    set_gate(24, isr_stub_24, 0x8E);
    set_gate(25, isr_stub_25, 0x8E);
    set_gate(26, isr_stub_26, 0x8E);
    set_gate(27, isr_stub_27, 0x8E);
    set_gate(28, isr_stub_28, 0x8E);
    set_gate(29, isr_stub_29, 0x8E);
    set_gate(30, isr_stub_30, 0x8E);
    set_gate(31, isr_stub_31, 0x8E);
    set_gate(32, irq_stub_32, 0x8E);
    set_gate(33, irq_stub_33, 0x8E);

    idtr.limit = (uint16_t)(sizeof(idt) - 1);
    idtr.base = (uint64_t)&idt[0];
    __asm__ __volatile__("lidt %0" : : "m"(idtr));
}


