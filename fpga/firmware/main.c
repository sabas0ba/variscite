// Bare-metal demo for the FPGA ports.
//
// It exists to show that the RTL platform works on real hardware, so it drives
// each piece the SoC provides rather than only printing a banner:
//
//   - the 16550 UART, for the console
//   - the CLINT, for a periodic machine timer interrupt
//   - the PLIC, for the UART receive interrupt (external interrupt path)
//
// Freestanding: no libc and no libgcc, so nothing here may need a 64-bit
// divide or a helper routine the linker would have to supply.

#include <stdint.h>

#define UART_BASE 0x10000000u
#define UART_RBR  0 // /THR
#define UART_IER  1
#define UART_FCR  2 // /IIR
#define UART_LCR  3
#define UART_MCR  4
#define UART_LSR  5

#define CLINT_BASE     0x11000000u
#define CLINT_MTIMECMP (CLINT_BASE + 0x4000)
#define CLINT_MTIME    (CLINT_BASE + 0xbff8)

#define PLIC_BASE      0x0c000000u
#define PLIC_PRIORITY  (PLIC_BASE + 0x000000)
#define PLIC_ENABLE    (PLIC_BASE + 0x002000)
#define PLIC_THRESHOLD (PLIC_BASE + 0x200000)
#define PLIC_CLAIM     (PLIC_BASE + 0x200004)

#define UART_IRQ 1u

// mtime counts at 1 MHz (FpgaSoc divides the system clock down to match the
// timebase-frequency the device tree advertises).
#define MTIME_HZ 1000000u

#define MSTATUS_MIE 0x8u
#define MIE_MTIE    0x80u
#define MIE_MEIE    0x800u

#define READ_CSR(name)                                        \
    static inline uint32_t read_csr_##name(void) {            \
        uint32_t v;                                           \
        asm volatile("csrr %0, " #name : "=r"(v));            \
        return v;                                             \
    }

READ_CSR(misa)
READ_CSR(mvendorid)
READ_CSR(mhartid)
READ_CSR(minstret)

static inline void mmio_w(uint32_t a, uint32_t v) {
    *(volatile uint32_t *)a = v;
}

static inline uint32_t mmio_r(uint32_t a) {
    return *(volatile uint32_t *)a;
}

static inline void uart_w(uint32_t reg, uint32_t v) {
    mmio_w(UART_BASE + 4 * reg, v);
}

static inline uint32_t uart_r(uint32_t reg) {
    return mmio_r(UART_BASE + 4 * reg);
}

static void putc_(char c) {
    if (c == '\n') putc_('\r');
    while ((uart_r(UART_LSR) & 0x20u) == 0) {
    }
    uart_w(UART_RBR, (uint8_t)c);
}

static void puts_(const char *s) {
    while (*s) putc_(*s++);
}

static void put_hex(uint32_t v) {
    puts_("0x");
    for (int i = 28; i >= 0; i -= 4) {
        const uint32_t d = (v >> i) & 0xfu;
        putc_((char)(d < 10 ? '0' + d : 'a' + d - 10));
    }
}

static void put_dec(uint32_t v) {
    char buf[10];
    int n = 0;
    if (v == 0) {
        putc_('0');
        return;
    }
    while (v > 0) {
        buf[n++] = (char)('0' + (v % 10u));
        v /= 10u;
    }
    while (n > 0) putc_(buf[--n]);
}

// mtime is 64 bits across two registers; re-read the high half to rule out a
// carry landing between the two loads.
static uint64_t read_mtime(void) {
    uint32_t hi, lo, hi2;
    do {
        hi = mmio_r(CLINT_MTIME + 4);
        lo = mmio_r(CLINT_MTIME);
        hi2 = mmio_r(CLINT_MTIME + 4);
    } while (hi != hi2);
    return ((uint64_t)hi << 32) | lo;
}

static void set_mtimecmp(uint64_t v) {
    // Park the low half out of reach first so the pair is never briefly a
    // value in the past.
    mmio_w(CLINT_MTIMECMP, 0xffffffffu);
    mmio_w(CLINT_MTIMECMP + 4, (uint32_t)(v >> 32));
    mmio_w(CLINT_MTIMECMP, (uint32_t)v);
}

static volatile uint32_t ticks;
static volatile uint32_t rx_count;

void trap_handler(uint32_t mcause, uint32_t mepc) {
    if ((mcause & 0x80000000u) == 0) {
        puts_("\n[trap] cause=");
        put_hex(mcause);
        puts_(" epc=");
        put_hex(mepc);
        puts_("\nhalted\n");
        for (;;) {
        }
    }

    switch (mcause & 0xffu) {
    case 7: // machine timer
        ticks++;
        set_mtimecmp(read_mtime() + MTIME_HZ);
        puts_("[tick] ");
        put_dec(ticks);
        puts_("s  retired=");
        put_hex(read_csr_minstret());
        putc_('\n');
        break;

    case 11: { // machine external, through the PLIC
        const uint32_t src = mmio_r(PLIC_CLAIM);
        if (src == UART_IRQ) {
            while (uart_r(UART_LSR) & 0x01u) {
                const char c = (char)(uart_r(UART_RBR) & 0xffu);
                rx_count++;
                puts_("[rx] ");
                putc_(c);
                puts_(" (");
                put_hex((uint8_t)c);
                puts_(")\n");
            }
        }
        mmio_w(PLIC_CLAIM, src); // completion
        break;
    }

    default:
        break;
    }
}

int main(void) {
    // 8N1, and leave the reset divisor alone: FpgaSoc parameterises it for the
    // board's clock so the console is already at the right rate.
    uart_w(UART_LCR, 0x03);
    uart_w(UART_FCR, 0x07);

    puts_("\n\n");
    puts_("rv32ima_veryl on FPGA\n");
    puts_("  misa      = ");
    put_hex(read_csr_misa());
    putc_('\n');
    puts_("  mvendorid = ");
    put_hex(read_csr_mvendorid());
    putc_('\n');
    puts_("  mhartid   = ");
    put_hex(read_csr_mhartid());
    putc_('\n');

    // PLIC: let the UART through to this context.
    mmio_w(PLIC_PRIORITY + 4 * UART_IRQ, 1);
    mmio_w(PLIC_THRESHOLD, 0);
    mmio_w(PLIC_ENABLE, 1u << UART_IRQ);
    uart_w(UART_IER, 0x01); // receive data available

    set_mtimecmp(read_mtime() + MTIME_HZ);

    asm volatile("csrs mie, %0" ::"r"(MIE_MTIE | MIE_MEIE));
    asm volatile("csrs mstatus, %0" ::"r"(MSTATUS_MIE));

    puts_("\ntimer and UART interrupts armed; type to echo\n\n");

    for (;;) {
        asm volatile("wfi");
    }
}
