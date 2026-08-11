# Register-level tests for the RTL CLINT and PLIC (src/clint.veryl,
# src/plic.veryl).
#
# Interrupts stay masked in mie throughout: this checks the device registers
# themselves, not the delivery path. irq_test.S covers delivery.

#include "riscv_test.h"
#include "test_macros.h"

#define MSIP        0x11000000
#define MTIMECMP_LO 0x11004000
#define MTIMECMP_HI 0x11004004
#define MTIME_LO    0x1100bff8
#define MTIME_HI    0x1100bffc

#define UART_IER    0x10000004
#define PLIC_PRIO0  0x0c000000
#define PLIC_PRIO1  0x0c000004
#define PLIC_PEND   0x0c001000
#define PLIC_ENABLE 0x0c002000
#define PLIC_THRES  0x0c200000
#define PLIC_CLAIM  0x0c200004

RVTEST_RV32M
RVTEST_CODE_BEGIN

  csrw mie, x0                 # no interrupt is to be delivered here

  # ---- test 2: mtimecmp is readable back in both halves ------------------
  li TESTNUM, 2
  li t0, MTIMECMP_LO
  li t1, 0x12345678
  sw t1, 0(t0)
  lw t2, 0(t0)
  bne t1, t2, fail
  li t0, MTIMECMP_HI
  li t1, 0x0000abcd
  sw t1, 0(t0)
  lw t2, 0(t0)
  bne t1, t2, fail
  li t1, -1                    # park it out of reach again
  sw t1, 0(t0)
  li t0, MTIMECMP_LO
  sw t1, 0(t0)

  # ---- test 3: mtime counts up and is read-only --------------------------
  li TESTNUM, 3
  li t0, MTIME_HI
  lw t3, 0(t0)                 # high half: no interrupt source, must be 0
  bnez t3, fail
  li t0, MTIME_LO
  lw t1, 0(t0)
  sw x0, 0(t0)                 # writes to mtime are ignored
  lw t2, 0(t0)
  bgeu t1, t2, fail            # must still be counting up from t1

  # ---- test 4: msip is one bit wide --------------------------------------
  li TESTNUM, 4
  li t0, MSIP
  li t1, -1
  sw t1, 0(t0)
  lw t2, 0(t0)
  li t1, 1
  bne t1, t2, fail
  sw x0, 0(t0)

  # ---- test 5: PLIC priority and threshold are 3-bit WARL ----------------
  li TESTNUM, 5
  li t0, PLIC_PRIO1
  li t1, -1
  sw t1, 0(t0)
  lw t2, 0(t0)
  li t1, 7
  bne t1, t2, fail
  li t0, PLIC_THRES
  li t1, -1
  sw t1, 0(t0)
  lw t2, 0(t0)
  li t1, 7
  bne t1, t2, fail

  # ---- test 6: only implemented sources can be enabled -------------------
  li TESTNUM, 6
  li t0, PLIC_ENABLE
  li t1, -1
  sw t1, 0(t0)
  lw t2, 0(t0)
  li t1, 2                     # source 1 is the only one this SoC has
  bne t1, t2, fail

  # ---- test 7: a source below the threshold cannot be claimed ------------
  # The UART asserts its line as soon as the transmit-holding interrupt is
  # enabled, which needs no console input and is therefore deterministic.
  li TESTNUM, 7
  li t0, UART_IER
  li t1, 2                     # IER.THRI -> device asserts its line
  sw t1, 0(t0)
  li t0, PLIC_PEND
  lw t2, 0(t0)
  li t1, 2
  bne t1, t2, fail             # pending regardless of priority
  li t0, PLIC_CLAIM
  lw t2, 0(t0)                 # priority 7 is not *above* a threshold of 7
  bnez t2, fail

  # ---- test 8: claim hands the source over, completion gives it back -----
  li TESTNUM, 8
  li t0, PLIC_THRES
  sw x0, 0(t0)
  li t0, PLIC_CLAIM
  lw t2, 0(t0)
  li t1, 1
  bne t1, t2, fail
  li t0, PLIC_PEND
  lw t2, 0(t0)
  bnez t2, fail                # the gateway holds the source while claimed
  li t0, PLIC_CLAIM
  lw t2, 0(t0)
  bnez t2, fail                # and it cannot be claimed twice

  li t0, PLIC_CLAIM
  li t1, 5
  sw t1, 0(t0)                 # completion of a source that is not enabled
  li t0, PLIC_PEND
  lw t2, 0(t0)
  bnez t2, fail                # is discarded, so the claim still stands

  li t0, PLIC_CLAIM
  li t1, 1
  sw t1, 0(t0)                 # the real completion
  li t0, PLIC_PEND
  lw t2, 0(t0)
  li t1, 2
  bne t1, t2, fail

  # ---- test 9: dropping the device line clears the pending bit -----------
  li TESTNUM, 9
  li t0, UART_IER
  sw x0, 0(t0)
  li t0, PLIC_PEND
  lw t2, 0(t0)
  bnez t2, fail

  # ---- test 10: writes that must not stick ------------------------------
  li TESTNUM, 10
  li t0, PLIC_PRIO0
  li t1, 7
  sw t1, 0(t0)                 # source 0 does not exist
  lw t2, 0(t0)
  bnez t2, fail
  li t0, PLIC_PEND
  li t1, -1
  sw t1, 0(t0)                 # the pending register is read-only
  lw t2, 0(t0)
  bnez t2, fail

  # ---- test 11: disabling a source does not release its claim ------------
  # The completion is matched against the enable bits, so a context that
  # disables a source mid-handler still has to complete it before the source
  # can interrupt again.
  li TESTNUM, 11
  li t0, PLIC_PRIO1
  li t1, 1
  sw t1, 0(t0)
  li t0, UART_IER
  li t1, 2
  sw t1, 0(t0)                 # raise the device line again
  li t0, PLIC_CLAIM
  lw t2, 0(t0)
  li t1, 1
  bne t1, t2, fail

  li t0, PLIC_ENABLE
  sw x0, 0(t0)                 # disable source 1 while it is claimed
  li t0, PLIC_CLAIM
  li t1, 1
  sw t1, 0(t0)                 # completion is discarded: not enabled
  li t0, PLIC_ENABLE
  li t1, 2
  sw t1, 0(t0)
  li t0, PLIC_PEND
  lw t2, 0(t0)
  bnez t2, fail                # still claimed

  li t0, PLIC_CLAIM
  li t1, 1
  sw t1, 0(t0)                 # now it takes
  li t0, PLIC_PEND
  lw t2, 0(t0)
  li t1, 2
  bne t1, t2, fail

  li t0, UART_IER
  sw x0, 0(t0)
  li t0, PLIC_PRIO1
  sw x0, 0(t0)

  TEST_PASSFAIL

RVTEST_CODE_END

  .data
RVTEST_DATA_BEGIN

  TEST_DATA

RVTEST_DATA_END
