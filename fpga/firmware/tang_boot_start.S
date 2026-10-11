    .option norvc
    .option norelax
    .section .text.init
    .globl _start
_start:
    csrw mie, zero
    la t0, trap
    csrw mtvec, t0
    li sp, 0x87fff000
    call boot_main
trap:
    li t0, 0x11100000
    li t1, 0xbad
    sw t1, 0(t0)
1:  j 1b
    .globl boot_jump
boot_jump:
    csrw mie, zero
    li t0, 8
    csrc mstatus, t0
    fence rw, rw
    fence.i
    li a0, 0
    li a1, 0x87e00000
    li t0, 0x80000000
    jr t0
