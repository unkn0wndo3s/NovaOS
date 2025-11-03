#pragma once
#include <stdint.h>

/* System call numbers */
enum syscall_number {
    SYS_write   = 0,
    SYS_exit    = 1,
    SYS_read    = 2,
    SYS_getpid  = 3,
};

/* Initialize SYSCALL/SYSRET MSRs and syscall table */
void syscall_init(void);

/* Low-level entry stub defined in assembly */
void syscall_entry(void);

/* Core handler (called by assembly entry) */
uint64_t syscall_handle(uint64_t num,
                        uint64_t arg0,
                        uint64_t arg1,
                        uint64_t arg2,
                        uint64_t arg3,
                        uint64_t arg4,
                        uint64_t arg5);


