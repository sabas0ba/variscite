# Machine timer / software interrupt test against the testbench CLINT.
# Covers direct and vectored mtvec modes.

#include "riscv_test.h"
#include "test_macros.h"

#define MTIME_LO    0x1100bff8
#define MTIMECMP_LO 0x11004000
#define MTIMECMP_HI 0x11004004
#define MSIP        0x11000000

RVTEST_RV32M
RVTEST_CODE_BEGIN

  li s11, 0                  # timer irq count
  li s10, 0                  # software irq count

  # ---- test 2: machine timer interrupt (direct mode) --------------------
  li TESTNUM, 2
  li t0, MTIME_LO
  lw t1, 0(t0)
  addi t1, t1, 200
  li t0, MTIMECMP_LO
  sw t1, 0(t0)
  li t0, MTIMECMP_HI
  sw x0, 0(t0)
  li t0, 0x80                # mie.MTIE
  csrw mie, t0
  csrsi mstatus, MSTATUS_MIE
  li t2, 10000
1:
  addi t2, t2, -1
  beqz t2, fail
  beqz s11, 1b
  csrci mstatus, MSTATUS_MIE

  # ---- test 3: machine software interrupt --------------------------------
  li TESTNUM, 3
  li t0, 0x8                 # mie.MSIE
  csrw mie, t0
  li t0, MSIP
  li t1, 1
  sw t1, 0(t0)
  csrsi mstatus, MSTATUS_MIE
  li t2, 10000
1:
  addi t2, t2, -1
  beqz t2, fail
  beqz s10, 1b
  csrci mstatus, MSTATUS_MIE

  # ---- test 4: vectored mode timer interrupt -----------------------------
  li TESTNUM, 4
  csrr s0, mtvec
  la t0, vec_table
  ori t0, t0, 1
  csrw mtvec, t0
  li s11, 0
  li t0, MTIME_LO
  lw t1, 0(t0)
  addi t1, t1, 200
  li t0, MTIMECMP_HI
  sw x0, 0(t0)
  li t0, MTIMECMP_LO
  sw t1, 0(t0)
  li t0, 0x80
  csrw mie, t0
  csrsi mstatus, MSTATUS_MIE
  li t2, 10000
1:
  addi t2, t2, -1
  beqz t2, fail
  beqz s11, 1b
  csrci mstatus, MSTATUS_MIE
  csrw mtvec, s0
  csrw mie, x0

  TEST_PASSFAIL

  .align 2
  .global mtvec_handler
mtvec_handler:
  csrr t5, mcause
  li t6, 0x80000007
  beq t5, t6, timer_h
  li t6, 0x80000003
  beq t5, t6, soft_h
  j fail
timer_h:
  li t5, MTIMECMP_LO
  li t6, -1
  sw t6, 0(t5)
  li t5, MTIMECMP_HI
  sw t6, 0(t5)
  addi s11, s11, 1
  mret
soft_h:
  li t5, MSIP
  sw x0, 0(t5)
  addi s10, s10, 1
  mret

  .align 7
vec_table:
  j fail                     # 0: exceptions
  j fail                     # 1
  j fail                     # 2
  j fail                     # 3: MSI (not enabled in vectored test)
  j fail                     # 4
  j fail                     # 5
  j fail                     # 6
  j timer_h                  # 7: MTI

RVTEST_CODE_END

  .data
RVTEST_DATA_BEGIN

  TEST_DATA

RVTEST_DATA_END
