# Freestanding userspace init for the rv32 NOMMU boot demo.
# Linked as ET_DYN (PIE) with no relocations; loaded by binfmt_elf_fdpic.
# Raw syscalls only, no libc.
#
# Commands on the console:
#   p<enter>  poweroff (reboot syscall -> syscon-poweroff)
#   r<enter>  reboot
#   others    echoed back

#define NR_read      63
#define NR_write     64
#define NR_reboot    142

#define REBOOT_MAGIC1    0xfee1dead
#define REBOOT_MAGIC2    0x28121969
#define RB_POWER_OFF     0x4321fedc
#define RB_AUTOBOOT      0x01234567

    .section .rodata
banner:
    .ascii "\n=== rv32ima_veryl init: userspace is alive (FDPIC) ===\n"
    .ascii "commands: p=poweroff r=reboot other=echo\n"
banner_end:
prompt:
    .ascii "veryl$ "
prompt_end:
echo_pre:
    .ascii "echo: "
echo_pre_end:

    .equ BANNER_LEN, banner_end - banner
    .equ PROMPT_LEN, prompt_end - prompt
    .equ ECHO_PRE_LEN, echo_pre_end - echo_pre

    .section .bss
    .align 2
buf:
    .space 128

    .section .text
    .globl _start
_start:
    li   a0, 1
    lla  a1, banner
    li   a2, BANNER_LEN
    li   a7, NR_write
    ecall

loop:
    li   a0, 1
    lla  a1, prompt
    li   a2, PROMPT_LEN
    li   a7, NR_write
    ecall

    li   a0, 0
    lla  a1, buf
    li   a2, 128
    li   a7, NR_read
    ecall
    blez a0, loop
    mv   s0, a0

    lla  t0, buf
    lbu  t1, 0(t0)
    li   t2, 'p'
    beq  t1, t2, poweroff
    li   t2, 'r'
    beq  t1, t2, do_reboot

    li   a0, 1
    lla  a1, echo_pre
    li   a2, ECHO_PRE_LEN
    li   a7, NR_write
    ecall
    li   a0, 1
    lla  a1, buf
    mv   a2, s0
    li   a7, NR_write
    ecall
    j    loop

poweroff:
    li   a2, RB_POWER_OFF
    j    reboot_call
do_reboot:
    li   a2, RB_AUTOBOOT
reboot_call:
    li   a0, REBOOT_MAGIC1
    li   a1, REBOOT_MAGIC2
    li   a3, 0
    li   a7, NR_reboot
    ecall
1:
    j    1b
