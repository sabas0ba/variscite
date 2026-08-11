// Verilator testbench for rv32ima_Core.
//
// Memory map:
//   0x0000_1000 .. 0x0000_ffff  boot ROM (stub: a0=0, a1=0x2000, jump to RAM)
//   0x0000_2000                 DTB (loaded from +dtb=..., inside ROM window)
//   0x1000_0000 .. 0x1000_0007  UART (8250 subset: off0 data, off5 LSR)
//   0x1100_0000                 CLINT msip (bit0 -> machine software irq)
//   0x1100_4000 / 0x1100_4004   CLINT mtimecmp lo/hi
//   0x1100_bff8 / 0x1100_bffc   CLINT mtime lo/hi (read only)
//   0x1110_0000                 SYSCON (write 0x5555: poweroff, 0x7777: reboot)
//   0x8000_0000 ..              RAM (+ramsize_mb, default 4)
//
// Machine timer interrupt: i_irq_timer = (mtime >= mtimecmp).
// mtime increments once per +mtimediv cycles (default 1).
//
// Plusargs:
//   +bin=<path>       flat binary loaded at 0x80000000 (riscv-tests mode)
//   +tohost=<hex>     tohost address; a 32-bit store there ends the simulation
//   +kernel=<path>    alias of +bin (Linux mode)
//   +dtb=<path>       DTB loaded at 0x2000
//   +timeout=<n>      max cycles (default 3,000,000)
//   +ramsize_mb=<n>   RAM size in MiB (default 4)
//   +mtimediv=<n>     cycles per mtime tick (default 1)
//   +logfile=<path>   retire/trap trace log (optional)
//   +logstart=<n>     start tracing at cycle n (default 0)
//   +logstop=<n>      stop tracing at cycle n (default: no limit)
//   +conlog=<path>    console (UART TX) log copy (optional)
//   +trace=<path>     VCD waveform output (optional)
//   +covfile=<path>   coverage output (default: coverage.dat)
//   +progress=<n>     print progress to stderr every n cycles (0: off)

#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <deque>
#include <string>
#include <vector>

#include <fcntl.h>
#include <unistd.h>

#include <verilated.h>
#if VM_COVERAGE
#include <verilated_cov.h>
#endif
#if VM_TRACE
#include <verilated_vcd_c.h>
#endif

#include "Vrv32ima_Core.h"

namespace {

constexpr uint32_t kRomBase = 0x00001000u;
constexpr uint32_t kRomSize = 0x0000f000u; // 60 KiB
constexpr uint32_t kDtbAddr = 0x00002000u;
constexpr uint32_t kUartBase = 0x10000000u;
constexpr uint32_t kClintMsip = 0x11000000u;
constexpr uint32_t kClintCmpLo = 0x11004000u;
constexpr uint32_t kClintCmpHi = 0x11004004u;
constexpr uint32_t kClintTimeLo = 0x1100bff8u;
constexpr uint32_t kClintTimeHi = 0x1100bffcu;
constexpr uint32_t kSyscon = 0x11100000u;
constexpr uint32_t kMemBase = 0x80000000u;

std::string plusarg_str(const char* name) {
    const char* v = Verilated::commandArgsPlusMatch(name);
    std::string s(v ? v : "");
    const std::string prefix = std::string("+") + name + "=";
    if (s.rfind(prefix, 0) == 0) {
        return s.substr(prefix.size());
    }
    return "";
}

uint64_t plusarg_u64(const char* name, uint64_t def, int base = 10) {
    const std::string s = plusarg_str(name);
    return s.empty() ? def : std::strtoull(s.c_str(), nullptr, base);
}

bool load_file(const std::string& path, void* dst, size_t cap, size_t* size_out) {
    std::FILE* f = std::fopen(path.c_str(), "rb");
    if (!f) return false;
    const size_t n = std::fread(dst, 1, cap, f);
    std::fclose(f);
    if (size_out) *size_out = n;
    return n > 0;
}

} // namespace

int main(int argc, char** argv) {
    Verilated::commandArgs(argc, argv);

    std::string bin_path = plusarg_str("bin");
    if (bin_path.empty()) bin_path = plusarg_str("kernel");
    const std::string dtb_path = plusarg_str("dtb");
    const std::string tohost_str = plusarg_str("tohost");
    const std::string log_path = plusarg_str("logfile");
    const std::string conlog_path = plusarg_str("conlog");
    const std::string trace_path = plusarg_str("trace");
    const std::string cov_path = plusarg_str("covfile");

    if (bin_path.empty()) {
        std::fprintf(stderr, "usage: +bin=<path>|+kernel=<path> [+tohost=<hex>] "
                             "[+dtb=<path>] [+timeout=<n>] [+ramsize_mb=<n>] "
                             "[+mtimediv=<n>] [+logfile=..] [+conlog=..] "
                             "[+trace=..] [+covfile=..] [+progress=<n>]\n");
        return 2;
    }

    const uint32_t tohost_addr =
        tohost_str.empty() ? 0 : static_cast<uint32_t>(std::strtoul(tohost_str.c_str(), nullptr, 16));
    const uint64_t timeout = plusarg_u64("timeout", 3000000ull);
    const uint64_t mtimediv = plusarg_u64("mtimediv", 1);
    const uint64_t progress = plusarg_u64("progress", 0);
    const uint64_t logstart = plusarg_u64("logstart", 0);
    const uint64_t logstop = plusarg_u64("logstop", ~0ull);
    const uint32_t mem_size = static_cast<uint32_t>(plusarg_u64("ramsize_mb", 4)) << 20;

    std::vector<uint32_t> mem(mem_size / 4, 0);
    std::vector<uint32_t> rom(kRomSize / 4, 0);

    if (!load_file(bin_path, mem.data(), mem_size, nullptr)) {
        std::fprintf(stderr, "error: cannot load %s\n", bin_path.c_str());
        return 2;
    }
    if (!dtb_path.empty()) {
        if (!load_file(dtb_path, rom.data() + (kDtbAddr - kRomBase) / 4,
                       kRomSize - (kDtbAddr - kRomBase), nullptr)) {
            std::fprintf(stderr, "error: cannot load %s\n", dtb_path.c_str());
            return 2;
        }
    }
    // Boot stub at 0x1000: a0 = 0 (hartid), a1 = DTB, jump to RAM base.
    rom[0] = 0x00000513; // addi a0, x0, 0
    rom[1] = 0x000025b7; // lui  a1, 0x2      (a1 = 0x2000)
    rom[2] = 0x800002b7; // lui  t0, 0x80000
    rom[3] = 0x00028067; // jalr x0, 0(t0)

    std::FILE* log = log_path.empty() ? nullptr : std::fopen(log_path.c_str(), "w");
    std::FILE* conlog = conlog_path.empty() ? nullptr : std::fopen(conlog_path.c_str(), "w");

    // Non-blocking stdin for UART RX.
    fcntl(STDIN_FILENO, F_SETFL, fcntl(STDIN_FILENO, F_GETFL, 0) | O_NONBLOCK);
    std::deque<uint8_t> rx_fifo;

    Vrv32ima_Core* top = new Vrv32ima_Core;
#if VM_TRACE
    VerilatedVcdC* tfp = nullptr;
    if (!trace_path.empty()) {
        Verilated::traceEverOn(true);
        tfp = new VerilatedVcdC;
        top->trace(tfp, 99);
        tfp->open(trace_path.c_str());
    }
#else
    void* tfp = nullptr;
#endif

    uint64_t t = 0;
    auto tick_edges = [&](int clk) {
        top->i_clk = clk;
        top->eval();
#if VM_TRACE
        if (tfp) tfp->dump(t);
#endif
        t++;
    };

    // CLINT state
    uint64_t mtime = 0;
    uint64_t mtimecmp = ~0ull;
    uint32_t msip = 0;

    top->i_rst = 1;
    top->i_mem_ready = 0;
    top->i_mem_rdata = 0;
    top->i_irq_timer = 0;
    top->i_irq_soft = 0;
    for (int i = 0; i < 4; i++) {
        tick_edges(0);
        tick_edges(1);
    }
    top->i_rst = 0;

    bool mem_ready_r = false;
    uint32_t mem_rdata_r = 0;
    int exit_code = 1;
    uint64_t cycles = 0;
    uint64_t retired = 0;
    bool done = false;

    // 16550A model, reg-shift = 2 / reg-io-width = 4: register n at base + 4n.
    // Only what the 8250 driver needs: DLAB-switched divisor latches, IER,
    // a derived IIR, LCR/MCR/SCR storage, LSR and a wired-on MSR.
    uint8_t u_ier = 0, u_lcr = 0, u_mcr = 0, u_scr = 0;
    uint8_t u_fcr = 0;
    (void)u_fcr;
    uint8_t u_dll = 1, u_dlm = 0;
    const bool uart_dbg = !plusarg_str("uartdbg").empty();

    auto uart_iir = [&]() -> uint32_t {
        uint32_t code;
        if ((u_ier & 0x01u) && !rx_fifo.empty()) {
            code = 0x04u; // received data available
        } else if (u_ier & 0x02u) {
            code = 0x02u; // transmit holding register empty (always)
        } else {
            code = 0x01u; // no interrupt pending
        }
        return 0xc0u | code; // FIFOs enabled
    };

    auto mmio_read = [&](uint32_t addr) -> uint32_t {
        if (addr >= kUartBase && addr < kUartBase + 0x20) {
            const uint32_t idx = (addr - kUartBase) >> 2;
            uint32_t v = 0;
            switch (idx) {
            case 0:
                if (u_lcr & 0x80u) {
                    v = u_dll;
                } else if (!rx_fifo.empty()) {
                    v = rx_fifo.front();
                    rx_fifo.pop_front();
                }
                break;
            case 1: v = (u_lcr & 0x80u) ? u_dlm : u_ier; break;
            case 2: v = uart_iir(); break;
            case 3: v = u_lcr; break;
            case 4: v = u_mcr; break;
            case 5: v = 0x60u | (rx_fifo.empty() ? 0u : 1u); break; // LSR
            case 6: v = 0xb0u; break;                               // MSR: CTS/DSR/DCD
            default: v = u_scr; break;
            }
            if (uart_dbg) std::fprintf(stderr, "[uart] R idx=%u -> %02x\n", idx, v);
            return v;
        }
        if (addr == kClintMsip) return msip;
        if (addr == kClintCmpLo) return static_cast<uint32_t>(mtimecmp);
        if (addr == kClintCmpHi) return static_cast<uint32_t>(mtimecmp >> 32);
        if (addr == kClintTimeLo) return static_cast<uint32_t>(mtime);
        if (addr == kClintTimeHi) return static_cast<uint32_t>(mtime >> 32);
        return 0;
    };

    auto mmio_write = [&](uint32_t addr, uint32_t val, uint32_t wstrb) {
        (void)wstrb;
        if (addr >= kUartBase && addr < kUartBase + 0x20) {
            const uint32_t idx = (addr - kUartBase) >> 2;
            const uint8_t v = static_cast<uint8_t>(val & 0xffu);
            if (uart_dbg) std::fprintf(stderr, "[uart] W idx=%u <- %02x\n", idx, v);
            switch (idx) {
            case 0:
                if (u_lcr & 0x80u) {
                    u_dll = v; // divisor latch low, not a character
                } else {
                    std::fputc(static_cast<char>(v), stdout);
                    std::fflush(stdout);
                    if (conlog) std::fputc(static_cast<char>(v), conlog);
                }
                break;
            case 1:
                if (u_lcr & 0x80u) {
                    u_dlm = v;
                } else {
                    u_ier = v;
                }
                break;
            case 2: u_fcr = v; break; // FCR (write-only alias of IIR)
            case 3: u_lcr = v; break;
            case 4: u_mcr = v; break;
            case 5:
            case 6: break;            // LSR / MSR are read-only
            default: u_scr = v; break;
            }
            return;
        }
        if (addr == kClintMsip) {
            msip = val & 1u;
            return;
        }
        if (addr == kClintCmpLo) {
            mtimecmp = (mtimecmp & 0xffffffff00000000ull) | val;
            return;
        }
        if (addr == kClintCmpHi) {
            mtimecmp = (mtimecmp & 0xffffffffull) | (static_cast<uint64_t>(val) << 32);
            return;
        }
        if (addr == kSyscon) {
            const uint32_t v = val & 0xffffu;
            if (v == 0x5555u) {
                std::printf("\n[tb] SYSCON poweroff (cycles=%llu, retired=%llu)\n",
                            (unsigned long long)cycles, (unsigned long long)retired);
                exit_code = 0;
                done = true;
            } else if (v == 0x7777u) {
                std::printf("\n[tb] SYSCON reboot request (cycles=%llu)\n",
                            (unsigned long long)cycles);
                exit_code = 0;
                done = true;
            }
            return;
        }
    };

    while (!done && cycles < timeout) {
        tick_edges(0);

        // Memory / MMIO response for the coming rising edge.
        if (mem_ready_r) {
            mem_ready_r = false; // one-shot
        } else if (top->o_mem_valid) {
            const uint32_t addr = top->o_mem_addr;
            const bool in_ram = addr >= kMemBase && (addr - kMemBase) < mem_size;
            const bool in_rom = addr >= kRomBase && (addr - kRomBase) < kRomSize;
            if (top->o_mem_wstrb != 0) {
                if (in_ram) {
                    const uint32_t word = (addr - kMemBase) / 4;
                    uint32_t nw = mem[word];
                    const uint32_t val = top->o_mem_wdata;
                    for (int b = 0; b < 4; b++) {
                        if (top->o_mem_wstrb & (1u << b)) {
                            nw = (nw & ~(0xffu << (8 * b))) | (val & (0xffu << (8 * b)));
                        }
                    }
                    mem[word] = nw;
                    if (tohost_addr != 0 && addr == tohost_addr &&
                        top->o_mem_wstrb == 0xf && nw != 0) {
                        const uint32_t code = nw;
                        if (code == 1) {
                            std::printf("PASS (cycles=%llu, retired=%llu)\n",
                                        (unsigned long long)cycles, (unsigned long long)retired);
                            exit_code = 0;
                        } else if (code & 1) {
                            std::printf("FAIL test %u (tohost=0x%08x, cycles=%llu)\n",
                                        code >> 1, code, (unsigned long long)cycles);
                            exit_code = 1;
                        } else {
                            std::printf("DONE tohost=0x%08x (cycles=%llu)\n", code,
                                        (unsigned long long)cycles);
                            exit_code = 1;
                        }
                        done = true;
                    }
                } else if (!in_rom) {
                    mmio_write(addr, top->o_mem_wdata, top->o_mem_wstrb);
                }
                mem_rdata_r = 0;
            } else {
                if (in_ram) {
                    mem_rdata_r = mem[(addr - kMemBase) / 4];
                } else if (in_rom) {
                    mem_rdata_r = rom[(addr - kRomBase) / 4];
                } else {
                    mem_rdata_r = mmio_read(addr);
                }
            }
            mem_ready_r = true;
        }
        top->i_mem_ready = mem_ready_r ? 1 : 0;
        top->i_mem_rdata = mem_rdata_r;

        // CLINT timer / interrupts.
        if (mtimediv <= 1 || (cycles % mtimediv) == 0) mtime++;
        top->i_irq_timer = (mtime >= mtimecmp) ? 1 : 0;
        top->i_irq_soft = msip & 1u;

        // Poll stdin for UART RX occasionally.
        if ((cycles & 0xfff) == 0) {
            uint8_t buf[64];
            const ssize_t n = read(STDIN_FILENO, buf, sizeof(buf));
            for (ssize_t i = 0; i < n; i++) rx_fifo.push_back(buf[i]);
        }

        tick_edges(1);
        cycles++;

        const bool log_win = log && cycles >= logstart && cycles < logstop;
        if (top->o_retire) {
            retired++;
            if (log_win) {
                std::fprintf(log, "core   0: 0x%08x (0x%08x)\n",
                             top->o_retire_pc, top->o_retire_instr);
            }
        }
        if (top->o_trap && log_win) {
            std::fprintf(log, "core   0: trap at 0x%08x cause 0x%08x\n",
                         top->o_retire_pc, top->o_trap_cause);
        }
        if (progress != 0 && (cycles % progress) == 0) {
            std::fprintf(stderr, "[tb] cycles=%llu retired=%llu mtime=%llu\n",
                         (unsigned long long)cycles, (unsigned long long)retired,
                         (unsigned long long)mtime);
        }
    }

    if (!done) {
        std::printf("\nTIMEOUT after %llu cycles (retired=%llu)\n",
                    (unsigned long long)cycles, (unsigned long long)retired);
        exit_code = 1;
    }

#if VM_TRACE
    if (tfp) {
        tfp->close();
        delete tfp;
    }
#else
    (void)tfp;
#endif
    if (log) std::fclose(log);
    if (conlog) std::fclose(conlog);

#if VM_COVERAGE
    VerilatedCov::write(cov_path.empty() ? "coverage.dat" : cov_path.c_str());
#else
    (void)cov_path;
#endif

    top->final();
    delete top;
    return exit_code;
}
