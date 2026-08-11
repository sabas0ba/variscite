# U-mode / privilege tests beyond what riscv-tests exercises:
# mcounteren gating of the user counters, privileged instruction and CSR
# access from U-mode, and the WARL behaviour of mstatus.MPP.
#
# Convention inside this test: ebreak from U-mode is the "return to M-mode"
# call. The handler resumes at the address held in s10; illegal instruction
# traps are counted in s11 and the trapping instruction is skipped.

#include "riscv_test.h"
#include "test_macros.h"

RVTEST_RV32M
RVTEST_CODE_BEGIN

  # ---- test 2: mcounteren is WARL (CY/TM/IR only) -----------------------
  li TESTNUM, 2
  li t0, -1
  csrw mcounteren, t0
  csrr t1, mcounteren
  li t2, 0x7
  bne t1, t2, fail
  csrw mcounteren, x0
  csrr t1, mcounteren
  bnez t1, fail

  # ---- test 3: U-mode privileged accesses trap --------------------------
  li TESTNUM, 3
  li s11, 0
  la s10, m_resume1
  la t0, u_block1
  csrw mepc, t0
  li t0, MSTATUS_MPP
  csrc mstatus, t0
  mret
u_block1:
  csrr t0, cycle             # mcounteren.CY = 0 -> illegal
  csrr t0, instret           # mcounteren.IR = 0 -> illegal
  csrr t0, mstatus           # M-mode CSR from U-mode -> illegal
  mret                       # privileged instruction from U-mode -> illegal
  ebreak
m_resume1:
  li t2, 4
  bne s11, t2, fail

  # ---- test 4: mcounteren enables the user counters ---------------------
  li TESTNUM, 4
  li t0, 0x5                 # CY | IR
  csrw mcounteren, t0
  li s11, 0
  la s10, m_resume2
  la t0, u_block2
  csrw mepc, t0
  li t0, MSTATUS_MPP
  csrc mstatus, t0
  mret
u_block2:
  csrr t0, cycle
  csrr t0, cycleh
  csrr t0, instret
  csrr t0, instreth
  ebreak
m_resume2:
  bnez s11, fail
  csrw mcounteren, x0

  # ---- test 5: mstatus.MPP is WARL, S mode is not implemented -----------
  li TESTNUM, 5
  li t0, MSTATUS_MPP
  csrc mstatus, t0
  csrr t2, mstatus
  and t2, t2, t0
  bnez t2, fail              # cleared MPP must read as U
  li t1, 0x800               # MPP = S
  csrs mstatus, t1
  csrr t2, mstatus
  and t2, t2, t0
  bnez t2, fail              # S must not be accepted
  csrs mstatus, t0           # restore MPP = M
  csrr t2, mstatus
  and t2, t2, t0
  bne t2, t0, fail

  TEST_PASSFAIL

  .align 2
  .global mtvec_handler
mtvec_handler:
  csrr t5, mcause
  li t6, 3
  beq t5, t6, back_to_m
  li t6, 2
  bne t5, t6, fail
  addi s11, s11, 1
  csrr t5, mepc
  addi t5, t5, 4
  csrw mepc, t5
  mret
back_to_m:
  csrw mepc, s10
  li t5, MSTATUS_MPP
  csrs mstatus, t5
  mret

RVTEST_CODE_END

  .data
RVTEST_DATA_BEGIN

  TEST_DATA

RVTEST_DATA_END
