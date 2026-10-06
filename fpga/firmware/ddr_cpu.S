/* Runs from boot ROM. All tested data reaches DDR through the CPU bus. */
#ifndef FULL_WORDS
#define FULL_WORDS 33554432
#endif
#ifndef HOLD_CYCLES
#define HOLD_CYCLES 2700000
#endif
    .option norvc
    .option norelax
    .section .text.init
    .globl _start
_start:
    la t0, trap
    csrw mtvec, t0
    li s0, 0x80000000
    li s1, FULL_WORDS
    li s2, 0
    li s3, 0x10000000
pass:
    li t0, 0
    mv t1, s0
write:
    jal ra, pattern
    sw t2, 0(t1)
    addi t1, t1, 4
    addi t0, t0, 1
    bltu t0, s1, write
    /* Keep refresh running for at least 100 ms at 27 MHz. */
    csrr t3, mcycle
    li t4, HOLD_CYCLES
hold:
    csrr t5, mcycle
    sub t5, t5, t3
    bltu t5, t4, hold
read:
    addi t0, t0, -1
    addi t1, t1, -4
    jal ra, pattern
    lw t3, 0(t1)
    bne t2, t3, fail
    bnez t0, read
    not s2, s2
    bnez s2, pass
    /* Instruction fetches must traverse the same DDR path as data accesses. */
    li t2, 0x05a00513 /* addi a0,zero,0x5a */
    sw t2, 0(s0)
    li t2, 0x00008067 /* jalr zero,0(ra) */
    sw t2, 4(s0)
    fence.i
    li a0, 0
    jalr ra, 0(s0)
    li t2, 0x5a
    mv t1, s0
    mv t3, a0
    bne t2, t3, fail
    li t0, 1
    sw t0, 0(s3)
stop:
    j stop
pattern:
    li t2, 0x193a70c5
    xor t2, t2, t0
    slli t6, t2, 13
    xor t2, t2, t6
    srli t6, t2, 17
    xor t2, t2, t6
    slli t6, t2, 5
    xor t2, t2, t6
    xor t2, t2, s2
    ret
fail:
    sw t1, 4(s3)
    sw t3, 8(s3)
    li t0, 2
    sw t0, 0(s3)
    j stop
trap:
    csrr t1, mtval
    csrr t3, mcause
    j fail
