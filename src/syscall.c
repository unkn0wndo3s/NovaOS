#include <stdint.h>
#include "msr.h"
#include "segments.h"
#include "syscall.h"
#include "serial.h"
#include "proc.h"

/* Optional TTY interface */
__attribute__((weak)) void tty_init(void) {}
__attribute__((weak)) int tty_write(const char *buf, uint64_t len) {
	/* Fallback to serial */
	for (uint64_t i = 0; i < len; i++) serial_write_char(buf[i]);
	return (int)len;
}
__attribute__((weak)) int tty_read(char *buf, uint64_t len) {
	(void)buf; (void)len; return 0;
}

/* Kernel syscall stack (single core, interrupts masked on entry) */
static uint8_t syscall_stack[16 * 1024];
uint64_t syscall_stack_top; /* referenced by assembly */

static uint64_t sys_write_impl(uint64_t fd, uint64_t buf, uint64_t len) {
	(void)fd; /* single TTY; ignore fd (0=stdin,1=stdout,2=stderr) */
	return (uint64_t)tty_write((const char *)buf, len);
}

static __attribute__((noreturn)) void sys_exit_impl(uint64_t code) {
	(void)code;
	/* For now, just halt the CPU. Later: mark task exited and schedule next. */
	for (;;) { __asm__ __volatile__("cli; hlt"); }
}

static uint64_t sys_read_impl(uint64_t fd, uint64_t buf, uint64_t len) {
	(void)fd;
	return (uint64_t)tty_read((char *)buf, len);
}

static uint64_t sys_getpid_impl(void) {
	return current_task ? (uint64_t)current_task->pid : 1;
}

uint64_t syscall_handle(uint64_t num,
			uint64_t arg0,
			uint64_t arg1,
			uint64_t arg2,
			uint64_t arg3,
			uint64_t arg4,
			uint64_t arg5) {
	(void)arg3; (void)arg4; (void)arg5; /* Unused for now */
	switch (num) {
		case SYS_write:   return sys_write_impl(arg0, arg1, arg2);
		case SYS_exit:    sys_exit_impl(arg0);
		case SYS_read:    return sys_read_impl(arg0, arg1, arg2);
		case SYS_getpid:  return sys_getpid_impl();
		default:          return (uint64_t)-1;
	}
}

void syscall_init(void) {
	/* Compute kernel/user selectors for STAR: kernel in [47:32], user in [63:48] */
	uint64_t star = 0;
	star |= ((uint64_t)GDT_SEL_KERNEL_CS) << 32;
	star |= ((uint64_t)GDT_SEL_USER_CS) << 48;
	wrmsr(MSR_STAR, star);

	/* Entry point */
	wrmsr(MSR_LSTAR, (uint64_t)(uintptr_t)syscall_entry);

	/* Mask RFLAGS on entry: clear IF (bit 9) to avoid reentrancy on shared stack */
	const uint64_t RFLAGS_IF = (1ull << 9);
	wrmsr(MSR_SFMASK, RFLAGS_IF);

	/* Enable SYSCALL/SYSRET (EFER.SCE) and NX (EFER.NXE) */
	uint64_t efer = rdmsr(MSR_EFER);
	efer |= 1ull;            /* SCE */
	efer |= (1ull << 11);    /* NXE */
	wrmsr(MSR_EFER, efer);

	/* Initialize the syscall stack top pointer */
	syscall_stack_top = (uint64_t)(uintptr_t)(syscall_stack + sizeof(syscall_stack));
}


