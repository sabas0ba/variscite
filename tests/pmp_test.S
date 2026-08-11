# PMP enforcement tests.
#
# Layout: entry 0 is a NAPOT region over `prot` with read permission only,
# entry 1 is a NAPOT match-all region with RWX. Entry priority is by index,
# so accesses inside `prot` are governed by entry 0 and everything else by
# entry 1.
#
# Convention: ebreak from U-mode returns to the M-mode address in s10;
# access faults are counted in s11 and the faulting instruction is skipped.

#include "riscv_test.h"
#include "test_macros.h"

#define PROT_SIZE 64
#define CFG_R    (PMP_NAPOT | PMP_R)
#define CFG_RWX  (PMP_NAPOT | PMP_R | PMP_W | PMP_X)

RVTEST_RV32M
RVTEST_CODE_BEGIN

  # ---- install the protected region -------------------------------------
  li TESTNUM, 2
  csrw pmpcfg0, x0            # disable while the addresses change
  la t0, prot
  srli t0, t0, 2
  ori t0, t0, (PROT_SIZE / 8) - 1   # NAPOT: trailing ones encode the size
  csrw pmpaddr0, t0
  li t0, -1
  csrw pmpaddr1, t0           # match-all
  li t0, CFG_R | (CFG_RWX << 8)
  csrw pmpcfg0, t0
  csrr t1, pmpcfg0
  bne t0, t1, fail

  # ---- test 2: unlocked entries do not constrain M-mode ------------------
  la t0, prot
  li t1, 0x5a5a5a5a
  sw t1, 0(t0)                # write must succeed despite the R-only entry
  lw t2, 0(t0)
  bne t1, t2, fail

  # ---- test 3: U-mode may read the region but not write it ---------------
  li TESTNUM, 3
  li s11, 0
  la s10, m_resume1
  la t0, u_read_write
  csrw mepc, t0
  li t0, MSTATUS_MPP
  csrc mstatus, t0
  mret
u_read_write:
  la t0, prot
  lw t1, 0(t0)                # permitted
  li t2, 0x5a5a5a5a
  bne t1, t2, u_fail
  sw x0, 0(t0)                # store access fault
  lw t1, 0(t0)                # value must be unchanged
  bne t1, t2, u_fail
  ebreak
u_fail:
  li s11, -1                  # force the M-mode check below to fail
  ebreak
m_resume1:
  li t2, 1
  bne s11, t2, fail

  # ---- test 4: U-mode cannot execute from a region without X -------------
  li TESTNUM, 4
  li s11, 0
  la s10, m_resume2
  la t0, u_exec
  csrw mepc, t0
  li t0, MSTATUS_MPP
  csrc mstatus, t0
  mret
u_exec:
  la t0, prot
  jr t0                       # instruction access fault at `prot`
m_resume2:
  li t2, 1
  bne s11, t2, fail

  # ---- test 5: NA4 region without read permission ------------------------
  # A four byte region marked execute-only, so a U-mode load must fault.
  li TESTNUM, 5
  li s11, 0
  csrw pmpcfg0, x0
  la t0, prot
  srli t0, t0, 2
  csrw pmpaddr0, t0           # NA4: exactly one word
  li t0, (PMP_NA4 | PMP_X) | (CFG_RWX << 8)
  csrw pmpcfg0, t0
  la s10, m_resume3
  la t0, u_load
  csrw mepc, t0
  li t0, MSTATUS_MPP
  csrc mstatus, t0
  mret
u_load:
  la t0, prot
  lw t1, 0(t0)                # load access fault
  ebreak
m_resume3:
  li t2, 1
  bne s11, t2, fail

  # ---- test 6: TOR region ------------------------------------------------
  # Entry 1 spans [prot, prot + PROT_SIZE) using entry 0's address as its
  # lower bound, and grants read but not write.
  li TESTNUM, 6
  li s11, 0
  csrw pmpcfg0, x0
  la t0, prot
  srli t0, t0, 2
  csrw pmpaddr0, t0
  la t0, prot
  addi t0, t0, PROT_SIZE
  srli t0, t0, 2
  csrw pmpaddr1, t0
  li t0, -1
  csrw pmpaddr2, t0
  li t0, (PMP_TOR | PMP_R) << 8
  li t1, CFG_RWX
  slli t1, t1, 16
  or t0, t0, t1
  csrw pmpcfg0, t0
  la s10, m_resume4
  la t0, u_tor
  csrw mepc, t0
  li t0, MSTATUS_MPP
  csrc mstatus, t0
  mret
u_tor:
  la t0, prot
  lw t1, 0(t0)                # permitted by the TOR entry
  sw x0, 0(t0)                # store access fault
  ebreak
m_resume4:
  li t2, 1
  bne s11, t2, fail

  # ---- test 7: a locked entry constrains M-mode too ----------------------
  li TESTNUM, 7
  csrw pmpcfg0, x0
  la t0, prot
  srli t0, t0, 2
  ori t0, t0, (PROT_SIZE / 8) - 1
  csrw pmpaddr0, t0
  li t0, -1
  csrw pmpaddr1, t0
  li t0, CFG_R | (CFG_RWX << 8)
  csrw pmpcfg0, t0
  li s11, 0
  li t0, CFG_R | PMP_L | (CFG_RWX << 8)
  csrw pmpcfg0, t0
  la t0, prot
  li t1, 0x12345678
  sw t1, 0(t0)                # now faults: entry 0 is locked and read-only
  li t2, 1
  bne s11, t2, fail
  lw t1, 0(t0)                # reads are still permitted
  li t2, 0x5a5a5a5a
  bne t1, t2, fail

  # ---- test 8: a locked entry ignores further writes ---------------------
  # Only entry 0 is locked, so only its cfg byte survives the write.
  li TESTNUM, 8
  csrr s0, pmpcfg0
  andi s0, s0, 0xff
  csrw pmpcfg0, x0
  csrr t1, pmpcfg0
  andi t1, t1, 0xff
  bne t1, s0, fail            # cfg byte 0 is frozen
  csrr s1, pmpaddr0
  csrw pmpaddr0, x0
  csrr t1, pmpaddr0
  bne t1, s1, fail            # its address is frozen as well

  TEST_PASSFAIL

  .align 2
  .global mtvec_handler
mtvec_handler:
  csrr t5, mcause
  li t6, 3
  beq t5, t6, back_to_m
  li t6, 7                    # store/AMO access fault
  beq t5, t6, count_fault
  li t6, 1                    # instruction access fault
  beq t5, t6, fetch_fault
  li t6, 5                    # load access fault
  beq t5, t6, count_fault
  j fail
count_fault:
  addi s11, s11, 1
  csrr t5, mepc
  addi t5, t5, 4
  csrw mepc, t5
  mret
fetch_fault:
  # mepc holds the unfetchable address; resume in M-mode instead.
  addi s11, s11, 1
  csrw mepc, s10
  li t5, MSTATUS_MPP
  csrs mstatus, t5
  mret
back_to_m:
  csrw mepc, s10
  li t5, MSTATUS_MPP
  csrs mstatus, t5
  mret

RVTEST_CODE_END

  .data
RVTEST_DATA_BEGIN

  .align 6
prot:
  .fill PROT_SIZE, 1, 0

  TEST_DATA

RVTEST_DATA_END
