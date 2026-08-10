# Directed test to close coverage holes not exercised by riscv-tests:
# WFI, mie/mcountinhibit/mcycle CSR accesses, remaining illegal-instruction
# decode paths, AMO alignment exceptions, and PMP register toggling.

#include "riscv_test.h"
#include "test_macros.h"

RVTEST_RV32M
RVTEST_CODE_BEGIN

  li s11, 0                  # trap counter

  # ---- test 2: wfi executes as nop -------------------------------------
  li TESTNUM, 2
  wfi

  # ---- test 3: mie write mask ------------------------------------------
  li TESTNUM, 3
  li t0, 0xffffffff
  csrw mie, t0
  csrr t1, mie
  li t2, 0x888
  bne t1, t2, fail
  csrw mie, x0
  csrr t1, mie
  bnez t1, fail

  # ---- test 4: mcountinhibit CY/IR -------------------------------------
  li TESTNUM, 4
  li t0, 0xffffffff
  csrw mcountinhibit, t0
  csrr t1, mcountinhibit
  li t2, 0x5
  bne t1, t2, fail
  nop
  nop
  csrw mcountinhibit, x0

  # ---- test 5: mcycle/mcycleh access -----------------------------------
  li TESTNUM, 5
  csrw mcycleh, x0
  csrw mcycle, x0
  csrr t1, mcycleh
  bnez t1, fail
  li t0, 0x40000000
  csrw mcycle, t0
  csrr t1, mcycle
  li t2, 0x40000000
  bltu t1, t2, fail
  li t0, 0xffffffff
  csrw mcycleh, t0
  csrw mcycle, t0
  nop                        # carry wraps the 64-bit counter to zero
  csrw mcycleh, x0
  csrw mcycle, x0
  li t0, 0xffffffff
  csrw minstreth, t0
  csrw minstret, x0
  csrw minstreth, x0

  # ---- test 6: csrs/csrc read-modify-write on mscratch ------------------
  li TESTNUM, 6
  li t0, 0xa5a5a5a5
  csrw mscratch, t0
  li t0, 0x5a5a5a5a
  csrs mscratch, t0
  csrr t1, mscratch
  li t2, 0xffffffff
  bne t1, t2, fail
  csrc mscratch, t2
  csrr t1, mscratch
  bnez t1, fail
  csrr t1, mip               # mip read (always 0)
  bnez t1, fail

  # ---- test 7: illegal encodings (each traps, handler skips 4 bytes) ----
  li TESTNUM, 7
  .word 0x00009067           # JALR with funct3=001
  .word 0x00002063           # BRANCH with funct3=010
  .word 0x00003003           # LOAD with funct3=011
  .word 0x00007023           # STORE with funct3=111
  .word 0x04000033           # OP with funct7=0000010
  .word 0x40001033           # OP with funct7=0100000, funct3=001
  .word 0x00004073           # SYSTEM with funct3=100
  .word 0x10200073           # SRET (S-mode absent)
  .word 0x2800202f           # AMO with illegal funct5=00101
  .word 0x1010202f           # LR.W with rs2!=x0
  .word 0x0000002f           # AMO with funct3=000
  csrw cycle, x0             # write to read-only CSR region
  li t2, 12
  bne s11, t2, fail

  # ---- test 8: AMO/LR/SC alignment exceptions ---------------------------
  li TESTNUM, 8
  li a0, 0x803ffffc          # top of simulated memory: toggles lr_addr bits up
  lr.w t0, (a0)
  la a0, data
  lr.w t0, (a0)              # low address: toggles lr_addr bits down
  addi a0, a0, 2             # misaligned
  lr.w t0, (a0)              # cause 4
  amoadd.w x0, x0, (a0)      # cause 6
  sc.w t0, t1, (a0)          # cause 6
  li t2, 15
  bne s11, t2, fail

  # ---- test 9: PMP register toggling ------------------------------------
  li TESTNUM, 9
  li t0, 0xffffffff
#define PMP_TOGGLE(csr_name) \
  csrw csr_name, t0; \
  csrr t1, csr_name; \
  csrw csr_name, x0
  PMP_TOGGLE(pmpcfg0)
  PMP_TOGGLE(pmpcfg1)
  PMP_TOGGLE(pmpcfg2)
  PMP_TOGGLE(pmpcfg3)
  PMP_TOGGLE(pmpaddr0)
  PMP_TOGGLE(pmpaddr1)
  PMP_TOGGLE(pmpaddr2)
  PMP_TOGGLE(pmpaddr3)
  PMP_TOGGLE(pmpaddr4)
  PMP_TOGGLE(pmpaddr5)
  PMP_TOGGLE(pmpaddr6)
  PMP_TOGGLE(pmpaddr7)
  PMP_TOGGLE(pmpaddr8)
  PMP_TOGGLE(pmpaddr9)
  PMP_TOGGLE(pmpaddr10)
  PMP_TOGGLE(pmpaddr11)
  PMP_TOGGLE(pmpaddr12)
  PMP_TOGGLE(pmpaddr13)
  PMP_TOGGLE(pmpaddr14)
  PMP_TOGGLE(pmpaddr15)
  # restore permissive PMP for the remainder
  li t0, -1
  csrw pmpaddr0, t0
  li t0, PMP_NAPOT | PMP_R | PMP_W | PMP_X
  csrw pmpcfg0, t0

  # ---- test 10: mtvec/mepc/mcause/mtval toggling ------------------------
  li TESTNUM, 10
  csrr s0, mtvec
  li t0, 0xfffffffc
  csrw mtvec, t0
  csrr t1, mtvec
  csrw mtvec, s0             # restore
  li t0, 0xffffffff
  csrw mtval, t0
  csrw mtval, x0
  csrw mcause, t0
  csrw mcause, x0
  csrw mepc, t0
  csrr t1, mepc
  li t2, 0xfffffffc
  bne t1, t2, fail

  # ---- test 11: mstatus MIE/MPIE toggling -------------------------------
  li TESTNUM, 11
  csrsi mstatus, MSTATUS_MIE
  csrr t1, mstatus
  andi t1, t1, MSTATUS_MIE
  beqz t1, fail
  csrci mstatus, MSTATUS_MIE

  TEST_PASSFAIL

  .align 2
  .global mtvec_handler
mtvec_handler:
  csrr t5, mcause
  li t6, 2
  beq t5, t6, 1f
  li t6, 4
  beq t5, t6, 1f
  li t6, 6
  beq t5, t6, 1f
  j fail
1:
  addi s11, s11, 1
  csrr t5, mepc
  addi t5, t5, 4
  csrw mepc, t5
  mret

RVTEST_CODE_END

  .data
RVTEST_DATA_BEGIN

data:
  .align 3
  .word 0x00000000
  .word 0x00000000

  TEST_DATA

RVTEST_DATA_END
