.global isr_stub_0
.global isr_stub_1
.global isr_stub_2
.global isr_stub_3
.global isr_stub_4
.global isr_stub_5
.global isr_stub_6
.global isr_stub_7
.global isr_stub_8
.global isr_stub_9
.global isr_stub_10
.global isr_stub_11
.global isr_stub_12
.global isr_stub_13
.global isr_stub_14
.global isr_stub_15
.global isr_stub_16
.global isr_stub_17
.global isr_stub_18
.global isr_stub_19
.global isr_stub_20
.global isr_stub_21
.global isr_stub_22
.global isr_stub_23
.global isr_stub_24
.global isr_stub_25
.global isr_stub_26
.global isr_stub_27
.global isr_stub_28
.global isr_stub_29
.global isr_stub_30
.global isr_stub_31
.global irq_stub_32
.global irq_stub_33

.extern isr_common_handler
.extern irq_common_handler

.macro PUSH_ALL
    pushq %rax
    pushq %rbx
    pushq %rcx
    pushq %rdx
    pushq %rbp
    pushq %rdi
    pushq %rsi
    pushq %r8
    pushq %r9
    pushq %r10
    pushq %r11
    pushq %r12
    pushq %r13
    pushq %r14
    pushq %r15
.endm

.macro POP_ALL
    popq %r15
    popq %r14
    popq %r13
    popq %r12
    popq %r11
    popq %r10
    popq %r9
    popq %r8
    popq %rsi
    popq %rdi
    popq %rbp
    popq %rdx
    popq %rcx
    popq %rbx
    popq %rax
.endm

.macro ISR_NOERR n
isr_stub_\n:
    pushq $0
    pushq $\n
    PUSH_ALL
    mov %rsp, %rdi
    call isr_common_handler
    POP_ALL
    addq $16, %rsp
    iretq
.endm

.macro ISR_ERR n
isr_stub_\n:
    pushq $\n
    PUSH_ALL
    mov %rsp, %rdi
    call isr_common_handler
    POP_ALL
    addq $8, %rsp
    iretq
.endm

/* IRQ stub macro (no error code), calls irq_common_handler */
.macro IRQ_NOERR n
irq_stub_\n:
    pushq $0
    pushq $\n
    PUSH_ALL
    mov %rsp, %rdi
    call irq_common_handler
    POP_ALL
    addq $16, %rsp
    iretq
.endm

/* 0-31 CPU exceptions; those with error code: 8,10-14,17 */
ISR_NOERR 0
ISR_NOERR 1
ISR_NOERR 2
ISR_NOERR 3
ISR_NOERR 4
ISR_NOERR 5
ISR_NOERR 6
ISR_NOERR 7
ISR_ERR   8
ISR_NOERR 9
ISR_ERR   10
ISR_ERR   11
ISR_ERR   12
ISR_ERR   13
ISR_ERR   14
ISR_NOERR 15
ISR_NOERR 16
ISR_ERR   17
ISR_NOERR 18
ISR_NOERR 19
ISR_NOERR 20
ISR_NOERR 21
ISR_NOERR 22
ISR_NOERR 23
ISR_NOERR 24
ISR_NOERR 25
ISR_NOERR 26
ISR_NOERR 27
ISR_NOERR 28
ISR_NOERR 29
ISR_NOERR 30
ISR_NOERR 31

/* Hardware IRQs we care about now */
IRQ_NOERR 32
IRQ_NOERR 33

/* ------------------------- SYSCALL entry ------------------------- */
.global syscall_entry
.extern syscall_handle
.extern syscall_stack_top

syscall_entry:
    /* Switch to kernel context and stack; store user RSP */
    swapgs
    mov %rsp, %r12                    /* save user RSP */
    lea syscall_stack_top(%rip), %rsp
    mov (%rsp), %rsp                  /* load kernel syscall stack top */

    /* Save user return state */
    pushq %rcx                        /* user RIP */
    pushq %r11                        /* user RFLAGS */
    pushq %r12                        /* user RSP */

    /* Prepare arguments for syscall_handle */
    pushq %r9                         /* stack arg: arg5 */
    mov %r8, %r9                      /* arg4 in r9 */
    mov %r10, %r8                     /* arg3 in r8 */
    mov %rdx, %rcx                    /* arg2 in rcx */
    mov %rsi, %rdx                    /* arg1 in rdx */
    mov %rdi, %rsi                    /* arg0 in rsi */
    mov %rax, %rdi                    /* num  in rdi */

    call syscall_handle

    add $8, %rsp                      /* pop arg5 */

    /* Restore and return to user */
    pop %r12                          /* user RSP */
    pop %r11                          /* user RFLAGS */
    pop %rcx                          /* user RIP */
    mov %r12, %rsp
    swapgs
    sysretq
