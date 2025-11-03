.global enter_userland
.extern tss_set_rsp0

/* Enter ring 3 at RIP=RDI, RSP=RSI, with RFLAGS having IF set. */
/* Uses IRETQ to transition to user mode. */
enter_userland:
    /* Arguments: rdi=rip, rsi=rsp */
    mov %rsi, %rax                /* user RSP in rax */
    /* Build IRET frame */
    pushq $0x1B                   /* USER_DS | RPL=3 (0x18|3) */
    pushq %rax                    /* user RSP */
    pushq $0x202                  /* RFLAGS with IF */
    pushq $0x23                   /* USER_CS | RPL=3 (0x20|3) */
    pushq %rdi                    /* user RIP */
    iretq


