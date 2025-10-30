#include <stddef.h>
#include <stdint.h>
#include "sched.h"
#include "../drivers/serial.h"
#include "../mm/heap.h"

#define MAX_TASKS 8
#define STACK_SIZE (16 * 1024)

struct task {
    const char *name;
    uint8_t *stack_base;
    uint64_t saved_rsp; /* points to saved PUSH_ALL area */
    int started;
    int alive;
};

static struct task tasks[MAX_TASKS];
static int num_tasks = 0;
static int current = -1;

static void build_initial_stack(struct task *t, task_entry_t entry) {
    /* Layout: PUSH_ALL regs (15*8), then int_no, err_code, then iret frame: rip, cs, rflags */
    uint8_t *sp = t->stack_base + STACK_SIZE;
    /* iret frame */
    uint64_t *q;
    q = (uint64_t *)(sp -= 8); *q = 0x202;         /* rflags IF */
    q = (uint64_t *)(sp -= 8); *q = 0x28;          /* cs */
    q = (uint64_t *)(sp -= 8); *q = (uint64_t)entry; /* rip */
    /* err_code, int_no */
    q = (uint64_t *)(sp -= 8); *q = 0;             /* err */
    q = (uint64_t *)(sp -= 8); *q = 32;            /* int_no placeholder */
    /* PUSH_ALL 15 regs */
    for (int i = 0; i < 15; i++) { q = (uint64_t *)(sp -= 8); *q = 0; }
    t->saved_rsp = (uint64_t)sp;
}

void sched_init(void) {
    num_tasks = 0; current = -1;
}

int sched_create(task_entry_t entry, const char *name) {
    if (num_tasks >= MAX_TASKS) return -1;
    struct task *t = &tasks[num_tasks];
    t->name = name;
    t->stack_base = (uint8_t *)kmalloc(STACK_SIZE);
    if (!t->stack_base) return -1;
    build_initial_stack(t, entry);
    t->started = 0;
    t->alive = 1;
    return num_tasks++;
}

void scheduler_on_tick(struct isr_regs *r) {
    if (num_tasks == 0) return;
    if (current >= 0) {
        /* save current RSP (points at PUSH_ALL) */
        tasks[current].saved_rsp = (uint64_t)r;
    }
    /* pick next */
    int next = current;
    for (int i = 0; i < num_tasks; i++) {
        next = (next + 1) % num_tasks;
        if (tasks[next].alive) break;
    }
    current = next;
    /* switch: r should point to target's saved PUSH_ALL */
    r = (struct isr_regs *)tasks[current].saved_rsp;
    /* set IF in rflags to keep timer running */
    r->rflags |= (1ull << 9);
    /* actually swap by changing the hardware stack pointer seen by our stub */
    __asm__ __volatile__("mov %0, %%rsp" : : "r"(r) : "memory");
}


