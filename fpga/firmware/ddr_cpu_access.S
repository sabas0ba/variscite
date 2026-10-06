/* CPU access-width, boundary and atomic tests; separate from the full scan. */
    .option norvc
    .option norelax
    .section .text.init
    .globl _start
    .macro verify_amo opcode, initial, operand, expected
    li t2, \initial
    sw t2, 0(t1)
    li t4, \operand
    \opcode t3, t4, (t1)
    bne t2, t3, fail
    li t2, \expected
    lw t3, 0(t1)
    bne t2, t3, fail
    .endm
_start:
    li s3, 0x10000000
    li s4, 0                 /* expected exception, zero means none */
    li s7, 0                 /* number of expected exceptions observed */
    la t0, trap
    csrw mtvec, t0
    li s0, 0x80001000
    jal ra, fill
    li s1, 0
byte_store:
    add t1, s0, s1
    xori t2, s1, 0xa5
    sb t2, 0(t1)
    li t0, 0
byte_check:
    add t1, s0, t0
    li t2, 0x5a
    bltu s1, t0, byte_expected
    xori t2, t0, 0xa5
byte_expected:
    lbu t3, 0(t1)
    bne t2, t3, fail
    slli t4, t2, 24
    srai t4, t4, 24
    lb t3, 0(t1)
    bne t4, t3, fail
    addi t0, t0, 1
    li t4, 32
    bltu t0, t4, byte_check
    jal ra, guards
    addi s1, s1, 1
    li t0, 16
    bltu s1, t0, byte_store

    li s2, 2
width_pass:
    li s1, 0
width_store:
    jal ra, fill
    add t1, s0, s1
    li t2, 0xdeadbeef
    li t0, 2
    bne s2, t0, word_store
    sh t2, 0(t1)
    li t2, 0xbeef
    lhu t3, 0(t1)
    bne t2, t3, fail
    li t2, -16657            /* sign-extended 0xbeef */
    lh t3, 0(t1)
    bne t2, t3, fail
    j width_check_start
word_store:
    sw t2, 0(t1)
    lw t3, 0(t1)
    bne t2, t3, fail
width_check_start:
    li t0, 0
width_check:
    add t1, s0, t0
    li t2, 0x5a
    bltu t0, s1, width_expected
    add t4, s1, s2
    bgeu t0, t4, width_expected
    sub t4, t0, s1
    slli t4, t4, 3
    li t2, 0xdeadbeef
    srl t2, t2, t4
    andi t2, t2, 255
width_expected:
    lbu t3, 0(t1)
    bne t2, t3, fail
    addi t0, t0, 1
    li t4, 32
    bltu t0, t4, width_check
    jal ra, guards
    addi s1, s1, 1
    li t0, 16
    bltu s1, t0, width_store
    addi s2, s2, 2
    li t0, 4
    bgeu t0, s2, width_pass

    /* Last valid split word: bytes 0x87fffffb..0x87fffffe. */
    li t1, 0x87fffff8
    li t2, 0x5a5a5a5a
    sw t2, 0(t1)
    sw t2, 4(t1)
    li t2, 0xdeadbeef
    sw t2, 3(t1)
    lw t3, 3(t1)
    bne t2, t3, fail
    li t2, 0xef5a5a5a
    lw t3, 0(t1)
    bne t2, t3, fail
    li t2, 0x5adeadbe
    lw t3, 4(t1)
    bne t2, t3, fail

    /* Each expected trap returns to s6 and clears s4. */
    li s4, 5
    li s5, 0x88000000
    la s6, split_load_return
    li t1, 0x87ffffff
    lw t3, 0(t1)
split_load_return:
    bnez s4, missing_trap
    li s4, 7
    la s6, split_store_return
    li t1, 0x87ffffff
    li t2, 0xabcdef12
    sw t2, 0(t1)
split_store_return:
    bnez s4, missing_trap
    li t1, 0x87fffffc
    li t2, 0x12deadbe        /* successful first byte is not rolled back */
    lw t3, 0(t1)
    bne t2, t3, fail
    li s4, 5
    la s6, load_return
    lw t3, 0(s5)
load_return:
    bnez s4, missing_trap
    li s4, 7
    la s6, store_return
    sw t2, 0(s5)
store_return:
    bnez s4, missing_trap
    li s4, 1
    la s6, fetch_return
    jalr zero, 0(s5)
fetch_return:
    bnez s4, missing_trap
    li s4, 7
    la s6, amo_return
    amoadd.w t3, t2, (s5)
amo_return:
    bnez s4, missing_trap

    /* Atomic values and successful/failed SC must preserve guard words. */
    jal ra, fill
    mv t1, s0
    li t2, 0x12345678
    sw t2, 0(t1)
    lr.w t3, (t1)
    bne t2, t3, fail
    li t4, 0x31415926
    sc.w t3, t4, (t1)
    bnez t3, fail
    lw t3, 0(t1)
    bne t4, t3, fail
    sc.w t3, t2, (t1)
    beqz t3, fail
    lw t3, 0(t1)
    bne t4, t3, fail
    li t2, 7
    amoadd.w t3, t2, (t1)
    bne t4, t3, fail
    addi t4, t4, 7
    lw t3, 0(t1)
    bne t4, t3, fail
    amoswap.w t3, t2, (t1)
    bne t4, t3, fail
    lw t3, 0(t1)
    bne t2, t3, fail
    verify_amo amoxor.w, 0xffff0000, 0x12345678, 0xedcb5678
    verify_amo amoand.w, 0xffff0000, 0x12345678, 0x12340000
    verify_amo amoor.w,  0xffff0000, 0x12345678, 0xffff5678
    verify_amo amomin.w, 0x80000000, 0x7fffffff, 0x80000000
    verify_amo amomin.w, 0x7fffffff, 0x80000000, 0x80000000
    verify_amo amomax.w, 0x80000000, 0x7fffffff, 0x7fffffff
    verify_amo amomax.w, 0x7fffffff, 0x80000000, 0x7fffffff
    verify_amo amominu.w, 0x80000000, 0x7fffffff, 0x7fffffff
    verify_amo amominu.w, 0x7fffffff, 0x80000000, 0x7fffffff
    verify_amo amomaxu.w, 0x80000000, 0x7fffffff, 0x80000000
    verify_amo amomaxu.w, 0x7fffffff, 0x80000000, 0x80000000
    li t0, 4
atomic_neighbors:
    add t1, s0, t0
    li t2, 0x5a5a5a5a
    lw t3, 0(t1)
    bne t2, t3, fail
    addi t0, t0, 4
    li t4, 32
    bltu t0, t4, atomic_neighbors
    jal ra, guards
    li t2, 6
    mv t3, s7
    bne t2, t3, fail
    li t0, 1
    sw t0, 0(s3)
stop:
    j stop

/* Restore the 32-byte test area and its two surrounding guard words. */
fill:
    mv t1, s0
    li t0, 8
    li t2, 0x5a5a5a5a
fill_word:
    sw t2, 0(t1)
    addi t1, t1, 4
    addi t0, t0, -1
    bnez t0, fill_word
    li t2, 0xdeadbeef
    sw t2, -4(s0)
    sw t2, 32(s0)
    ret
guards:
    addi t1, s0, -4
    li t2, 0xdeadbeef
    lw t3, 0(t1)
    bne t2, t3, fail
    addi t1, s0, 32
    lw t3, 0(t1)
    bne t2, t3, fail
    ret
missing_trap:
    mv t1, s5
    li t3, 0xffffffff
fail:
    sw t1, 4(s3)
    sw t3, 8(s3)
    li t0, 2
    sw t0, 0(s3)
    j stop
trap:
    csrr t1, mtval
    csrr t3, mcause
    beqz s4, fail
    bne t3, s4, fail
    bne t1, s5, fail
    li s4, 0
    addi s7, s7, 1
    csrw mepc, s6
    mret
