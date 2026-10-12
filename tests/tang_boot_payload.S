/* UART-loaded smoke program: Linux entry ABI, timer, UART/PLIC and DDR. */
    .option norvc
    .option norelax
    .section .text
    .globl _start
_start:
    bnez a0, fail
    li t0, 0x87e00000
    bne a1, t0, fail
    lw t1, 0(a1)
    li t2, 0xedfe0dd0
    bne t1, t2, fail
#ifdef WITH_LCD
    /* Error inputs are injected by the harness; enable comes from the ROM. */
    li t0, 0x11200000
    lw t1, 0(t0)
    li t2, 7
    bne t1, t2, fail
    sw zero, 0(t0) /* Enable cannot be cleared without common reset. */
    sh zero, 2(t0)
    li t3, -1
    sb t3, 1(t0) /* Upper byte must not change control/status. */
    lw t1, 0(t0)
    bne t1, t2, fail
#endif
    li t0, 0x1100bff8
    lw t1, 0(t0)
    li t2, 100
1:  addi t2, t2, -1
    bnez t2, 1b
    lw t2, 0(t0)
    beq t1, t2, fail
    li t0, 0x80010003
    li t1, 0x87654321
    sw t1, 0(t0)
    lw t2, 0(t0)
    bne t1, t2, fail
    li t0, 0x0c000004
    li t1, 1
    sw t1, 0(t0)
    li t0, 0x0c002000
    li t1, 2
    sw t1, 0(t0)
    li t0, 0x10000004
    sw t1, 0(t0) /* UART THRE interrupt */
    li t2, 1000
    li t4, 0x800
2:  csrr t3, mip
    and t3, t3, t4
    bnez t3, claim
    addi t2, t2, -1
    bnez t2, 2b
    j fail
claim:
    li t0, 0x0c200004
    lw t1, 0(t0)
    li t2, 1
    bne t1, t2, fail
    li t3, 0x10000004
    sw zero, 0(t3)
    sw t1, 0(t0)
    li t0, 0x10000000
    la t4, message
print:
    lbu t1, 0(t4)
    beqz t1, drained
4:  lw t2, 20(t0)
    andi t2, t2, 0x20
    beqz t2, 4b
    sw t1, 0(t0)
    addi t4, t4, 1
    j print
drained:
    lw t2, 20(t0)
    andi t2, t2, 0x40
    beqz t2, drained
    li t1, 0x5555
    j finish
fail:
    li t1, 0xdead
finish:
    li t0, 0x11100000
    sw t1, 0(t0)
3:  j 3b
message:
    .asciz "BOOT OK\n"
