#pragma once
#include <stdint.h>

/* Model Specific Registers used for SYSCALL/SYSRET and GS base */
#define MSR_EFER             0xC0000080u
#define MSR_STAR             0xC0000081u
#define MSR_LSTAR            0xC0000082u
#define MSR_CSTAR            0xC0000083u
#define MSR_SFMASK           0xC0000084u
#define MSR_FS_BASE          0xC0000100u
#define MSR_GS_BASE          0xC0000101u
#define MSR_KERNEL_GS_BASE   0xC0000102u

static inline uint64_t rdmsr(uint32_t msr) {
    uint32_t lo, hi;
    __asm__ __volatile__("rdmsr" : "=a"(lo), "=d"(hi) : "c"(msr));
    return ((uint64_t)hi << 32) | lo;
}

static inline void wrmsr(uint32_t msr, uint64_t value) {
    uint32_t lo = (uint32_t)(value & 0xFFFFFFFFu);
    uint32_t hi = (uint32_t)(value >> 32);
    __asm__ __volatile__("wrmsr" : : "c"(msr), "a"(lo), "d"(hi));
}


