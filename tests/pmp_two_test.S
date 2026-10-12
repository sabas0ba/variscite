# Run only with PMP_ENTRIES=2. The last config word has two unused bytes.
# Verify those bytes and absent CSRs, then permissions and entry locking.
#include "riscv_test.h"
#include "test_macros.h"

RVTEST_RV32M
RVTEST_CODE_BEGIN
  li TESTNUM, 2
  csrw pmpcfg0, x0
  la t0, prot
  srli t0, t0, 2
  csrw pmpaddr0, t0
  li t0, -1
  csrw pmpaddr1, t0
  csrw pmpaddr2, t0
  csrw pmpaddr3, t0
  csrw pmpcfg1, t0
  csrr t1, pmpaddr2
  bnez t1, fail
  csrr t1, pmpaddr3
  bnez t1, fail
  csrr t1, pmpcfg1
  bnez t1, fail
  # Entry 0: NA4 read-only. Entry 1: NAPOT match-all RWX.
  li t0, 0xffff1f11
  csrw pmpcfg0, t0
  csrr t1, pmpcfg0
  li t2, 0x1f11
  bne t1, t2, fail

  li TESTNUM, 3
  la t0, prot
  li t1, 0x12345678
  sw t1, 0(t0)             # unlocked entry allows M-mode stores
  li s0, 0
  la t2, user_test
  csrw mepc, t2
  li t2, MSTATUS_MPP
  csrc mstatus, t2
  mret
user_test:
  lw t2, 0(t0)
  bne t1, t2, user_fail
  sw x0, 0(t0)             # U-mode store must fault and leave data intact
  lw t2, 0(t0)
  bne t1, t2, user_fail
  li t3, 1
  bne s0, t3, user_fail
  ebreak
user_fail:
  li s0, -1
  ebreak
  .global mtvec_handler
mtvec_handler:
  csrr t3, mcause
  li t4, 7
  beq t3, t4, store_fault
  li t4, 3
  bne t3, t4, fail
  li t4, 1
  bne s0, t4, fail

  li TESTNUM, 4
  li t0, 0x9f00           # lock match-all entry 1; disable entry 0
  csrw pmpcfg0, t0
  csrw pmpcfg0, x0
  csrr t1, pmpcfg0
  bne t0, t1, fail
  csrw pmpaddr1, x0
  csrr t1, pmpaddr1
  li t2, -1
  bne t1, t2, fail
  TEST_PASSFAIL
store_fault:
  addi s0, s0, 1
  csrr t3, mepc
  addi t3, t3, 4
  csrw mepc, t3
  mret
RVTEST_CODE_END

  .data
RVTEST_DATA_BEGIN
  .align 2
prot:
  .word 0
  TEST_DATA
RVTEST_DATA_END
