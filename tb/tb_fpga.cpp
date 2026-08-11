// Verilator testbench for rv32ima_FpgaSoc.
//
// This is the board-independent check of the FPGA platform: it drives nothing
// but the clock, the reset and the UART's two wires, exactly as a board does.
// Everything else - boot stub, RAM, UART, CLINT, PLIC - comes from the RTL.
//
// The console is decoded off o_uart_tx at the configured bit rate rather than
// tapped from inside the design, so a broken baud generator shows up as
// garbled output instead of passing silently.
//
// Plusargs:
//   +cycles=<n>    stop after n cycles (default 8,000,000)
//   +bitcycles=<n> UART bit period in clocks; must match 16 * UART_DIV
//   +send=<text>   inject text on the receive line once the banner is out
//   +expect=<text> exit 0 only if this appears in the console output

#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <string>

#include <verilated.h>

#include "Vrv32ima_FpgaSoc.h"

namespace {

std::string plusarg_str(const char* name) {
    const char* v = Verilated::commandArgsPlusMatch(name);
    std::string s(v ? v : "");
    const std::string prefix = std::string("+") + name + "=";
    if (s.rfind(prefix, 0) == 0) return s.substr(prefix.size());
    return "";
}

uint64_t plusarg_u64(const char* name, uint64_t def) {
    const std::string s = plusarg_str(name);
    return s.empty() ? def : std::strtoull(s.c_str(), nullptr, 10);
}

// Samples the transmit line in the middle of each bit and reassembles bytes.
class UartRx {
public:
    explicit UartRx(uint64_t bit_cycles) : bit_cycles_(bit_cycles) {}

    // Returns -1 unless a byte completed on this cycle.
    int step(bool tx) {
        switch (state_) {
        case Idle:
            if (!tx) { // start bit
                state_ = Start;
                count_ = bit_cycles_ / 2;
            }
            break;
        case Start:
            if (--count_ == 0) {
                if (tx) { // not a real start bit after all
                    state_ = Idle;
                } else {
                    state_ = Data;
                    count_ = bit_cycles_;
                    bits_ = 0;
                    shift_ = 0;
                }
            }
            break;
        case Data:
            if (--count_ == 0) {
                shift_ = static_cast<uint8_t>((shift_ >> 1) | (tx ? 0x80u : 0u));
                count_ = bit_cycles_;
                if (++bits_ == 8) state_ = Stop;
            }
            break;
        case Stop:
            if (--count_ == 0) {
                state_ = Idle;
                return shift_; // framing is not checked; the DUT drives it
            }
            break;
        }
        return -1;
    }

private:
    enum State { Idle, Start, Data, Stop };
    uint64_t bit_cycles_;
    State state_ = Idle;
    uint64_t count_ = 0;
    unsigned bits_ = 0;
    uint8_t shift_ = 0;
};

// Shifts bytes out onto the receive line at the same rate.
class UartTx {
public:
    explicit UartTx(uint64_t bit_cycles) : bit_cycles_(bit_cycles) {}

    void send(const std::string& s) { pending_ = s; }
    bool busy() const { return !pending_.empty() || bits_ > 0; }

    bool step() {
        if (bits_ == 0) {
            if (pending_.empty()) return true; // line idles high
            const uint8_t c = static_cast<uint8_t>(pending_[0]);
            pending_.erase(0, 1);
            frame_ = static_cast<uint16_t>((0x100u | c) << 1); // start, data, stop
            bits_ = 10;
            count_ = bit_cycles_;
        }
        const bool level = (frame_ & 1u) != 0;
        if (--count_ == 0) {
            frame_ >>= 1;
            bits_--;
            count_ = bit_cycles_;
        }
        return level;
    }

private:
    uint64_t bit_cycles_;
    std::string pending_;
    uint16_t frame_ = 0;
    unsigned bits_ = 0;
    uint64_t count_ = 1;
};

} // namespace

int main(int argc, char** argv) {
    Verilated::commandArgs(argc, argv);

    const uint64_t max_cycles = plusarg_u64("cycles", 8000000ull);
    const uint64_t bit_cycles = plusarg_u64("bitcycles", 32);
    const std::string send = plusarg_str("send");
    const std::string expect = plusarg_str("expect");

    Vrv32ima_FpgaSoc* top = new Vrv32ima_FpgaSoc;
    UartRx console(bit_cycles);
    UartTx injector(bit_cycles);

    std::string out;
    uint64_t retired = 0;

    top->i_rst = 1;
    top->i_uart_rx = 1;
    for (int i = 0; i < 8; i++) {
        top->i_clk = 0;
        top->eval();
        top->i_clk = 1;
        top->eval();
    }
    top->i_rst = 0;

    bool sent = false;
    for (uint64_t c = 0; c < max_cycles; c++) {
        top->i_uart_rx = injector.step() ? 1 : 0;

        top->i_clk = 0;
        top->eval();
        top->i_clk = 1;
        top->eval();

        if (top->o_retire) retired++;

        const int byte = console.step(top->o_uart_tx != 0);
        if (byte >= 0) {
            std::fputc(byte, stdout);
            std::fflush(stdout);
            out.push_back(static_cast<char>(byte));
        }

        // Inject once the firmware has armed its interrupts, so the character
        // exercises the PLIC path rather than being dropped before setup.
        if (!sent && !send.empty() && out.find("armed") != std::string::npos) {
            injector.send(send);
            sent = true;
        }
    }

    std::printf("\n[tb] %llu cycles, %llu instructions retired\n",
                (unsigned long long)max_cycles, (unsigned long long)retired);

    int rc = 0;
    if (retired == 0) {
        std::printf("[tb] FAIL: the core never retired an instruction\n");
        rc = 1;
    }
    if (!expect.empty() && out.find(expect) == std::string::npos) {
        std::printf("[tb] FAIL: console never showed \"%s\"\n", expect.c_str());
        rc = 1;
    }
    if (!send.empty() && !sent) {
        std::printf("[tb] FAIL: never reached the point of injecting input\n");
        rc = 1;
    }
    if (rc == 0) std::printf("[tb] PASS\n");

    top->final();
    delete top;
    return rc;
}
