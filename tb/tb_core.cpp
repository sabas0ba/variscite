// Verilator testbench for rv32ima_Core.
//
// Memory model: single 32-bit port, registered one-cycle response.
// HTIF: a 32-bit store to the address given by +tohost=<hex> terminates the
// simulation. Value 1 means PASS; any other odd value encodes the failing
// test number as (n << 1) | 1.
//
// Plusargs:
//   +bin=<path>      flat binary loaded at 0x80000000 (required)
//   +tohost=<hex>    tohost address (required)
//   +timeout=<n>     max cycles (default 3,000,000)
//   +logfile=<path>  retire/trap trace log (optional)
//   +trace=<path>    VCD waveform output (optional)
//   +covfile=<path>  coverage output (default: coverage.dat next to cwd)

#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <string>
#include <vector>

#include <verilated.h>
#include <verilated_cov.h>
#include <verilated_vcd_c.h>

#include "Vrv32ima_Core.h"

namespace {

constexpr uint32_t kMemBase = 0x80000000u;
constexpr uint32_t kMemSize = 1u << 22; // 4 MiB

std::string plusarg_str(const char* name) {
    const char* v = Verilated::commandArgsPlusMatch(name);
    std::string s(v ? v : "");
    const std::string prefix = std::string("+") + name + "=";
    if (s.rfind(prefix, 0) == 0) {
        return s.substr(prefix.size());
    }
    return "";
}

} // namespace

int main(int argc, char** argv) {
    Verilated::commandArgs(argc, argv);

    const std::string bin_path = plusarg_str("bin");
    const std::string tohost_str = plusarg_str("tohost");
    const std::string log_path = plusarg_str("logfile");
    const std::string trace_path = plusarg_str("trace");
    const std::string cov_path = plusarg_str("covfile");
    const std::string timeout_str = plusarg_str("timeout");

    if (bin_path.empty() || tohost_str.empty()) {
        std::fprintf(stderr, "usage: +bin=<path> +tohost=<hex> [+timeout=<n>] "
                             "[+logfile=<path>] [+trace=<path>] [+covfile=<path>]\n");
        return 2;
    }

    const uint32_t tohost_addr =
        static_cast<uint32_t>(std::strtoul(tohost_str.c_str(), nullptr, 16));
    const uint64_t timeout =
        timeout_str.empty() ? 3000000ull : std::strtoull(timeout_str.c_str(), nullptr, 10);

    std::vector<uint32_t> mem(kMemSize / 4, 0);
    {
        std::FILE* f = std::fopen(bin_path.c_str(), "rb");
        if (!f) {
            std::fprintf(stderr, "error: cannot open %s\n", bin_path.c_str());
            return 2;
        }
        const size_t n = std::fread(mem.data(), 1, kMemSize, f);
        std::fclose(f);
        if (n == 0) {
            std::fprintf(stderr, "error: empty binary %s\n", bin_path.c_str());
            return 2;
        }
    }

    std::FILE* log = nullptr;
    if (!log_path.empty()) {
        log = std::fopen(log_path.c_str(), "w");
    }

    Vrv32ima_Core* top = new Vrv32ima_Core;
    VerilatedVcdC* tfp = nullptr;
    if (!trace_path.empty()) {
        Verilated::traceEverOn(true);
        tfp = new VerilatedVcdC;
        top->trace(tfp, 99);
        tfp->open(trace_path.c_str());
    }

    uint64_t t = 0;
    auto tick_edges = [&](int clk) {
        top->i_clk = clk;
        top->eval();
        if (tfp) tfp->dump(t);
        t++;
    };

    // Reset
    top->i_rst = 1;
    top->i_mem_ready = 0;
    top->i_mem_rdata = 0;
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

    while (!done && cycles < timeout) {
        // Falling edge.
        tick_edges(0);

        // Compute memory response for the coming rising edge.
        if (mem_ready_r) {
            mem_ready_r = false; // one-shot
        } else if (top->o_mem_valid) {
            const uint32_t addr = top->o_mem_addr;
            const uint32_t word = (addr - kMemBase) / 4;
            const bool in_range = addr >= kMemBase && (addr - kMemBase) < kMemSize;
            if (top->o_mem_wstrb != 0) {
                uint32_t cur = in_range ? mem[word] : 0;
                uint32_t val = top->o_mem_wdata;
                uint32_t nw = cur;
                for (int b = 0; b < 4; b++) {
                    if (top->o_mem_wstrb & (1u << b)) {
                        nw = (nw & ~(0xffu << (8 * b))) | (val & (0xffu << (8 * b)));
                    }
                }
                if (in_range) mem[word] = nw;
                if (addr == tohost_addr && top->o_mem_wstrb == 0xf && nw != 0) {
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
                mem_rdata_r = 0;
            } else {
                mem_rdata_r = in_range ? mem[word] : 0;
            }
            mem_ready_r = true;
        }
        top->i_mem_ready = mem_ready_r ? 1 : 0;
        top->i_mem_rdata = mem_rdata_r;

        // Rising edge.
        tick_edges(1);
        cycles++;

        if (top->o_retire) {
            retired++;
            if (log) {
                std::fprintf(log, "core   0: 0x%08x (0x%08x)\n",
                             top->o_retire_pc, top->o_retire_instr);
            }
        }
        if (top->o_trap && log) {
            std::fprintf(log, "core   0: trap at 0x%08x cause %u\n",
                         top->o_retire_pc, top->o_trap_cause);
        }
    }

    if (!done) {
        std::printf("TIMEOUT after %llu cycles\n", (unsigned long long)cycles);
        exit_code = 1;
    }

    if (tfp) {
        tfp->close();
        delete tfp;
    }
    if (log) std::fclose(log);

    VerilatedCov::write(cov_path.empty() ? "coverage.dat" : cov_path.c_str());

    top->final();
    delete top;
    return exit_code;
}
