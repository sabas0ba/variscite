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

#ifdef LCD_SYSTEM
#include "Vrv32ima_TangLcdSystem.h"
using FpgaTop = Vrv32ima_TangLcdSystem;
#else
#include "Vrv32ima_FpgaSoc.h"
using FpgaTop = Vrv32ima_FpgaSoc;
#endif

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

    FpgaTop* top = new FpgaTop;
    UartRx console(bit_cycles);
    UartTx injector(bit_cycles);

    std::string out;
    uint64_t retired = 0;

    top->i_rst = 1;
#ifndef LCD_SYSTEM
    top->i_ext_rdata = 0;
#else
    top->i_pixel_rst = 1;
    top->i_lcd_ready = 0;
    uint64_t subcycle = 0;
    bool last_pixel_clk = false, last_vs = false;
    unsigned pixels = 0, yellow = 0, magenta = 0, dark = 0;
    bool saw_yellow = false, saw_magenta = false;
    unsigned frames = 0;
    unsigned red = 0, green = 0, blue = 0;
    bool saw_red = false, saw_green = false, saw_blue = false;
    bool saw_command_bars = false, saw_return_rectangle = false, saw_motion = false;
    unsigned command_stage = 0;
    int rect_x = -1, previous_rect_x = -1;
    bool rectangle_valid = true, bars_valid = true;
    const uint16_t bar_colors[] = {0xffff,0xffe0,0x07ff,0x07e0,0xf81f,0xf800,0x001f,0};
#endif
    auto clock_cycle = [&]() {
#ifdef LCD_SYSTEM
        // Independent 11:9 clock periods preserve the board's 27:33 ratio.
        for (unsigned phase = 0; phase < 22; ++phase, ++subcycle) {
            top->i_clk = phase >= 11;
            const bool pixel_clk = ((subcycle / 9) & 1) != 0;
            top->i_pixel_clk = pixel_clk;
            top->eval();
            if (!top->i_rst && pixel_clk && !last_pixel_clk) {
                if (last_vs && !top->lcd_vs) {
                    if(pixels != 0 && pixels != 800*480) {
                        std::fprintf(stderr,"[tb] FAIL: active frame size=%u\n",pixels);
                        return false;
                    }
                    if (pixels == 800 * 480) {
                        frames++;
                        saw_yellow |= yellow == 120*120 && dark == 800*480-120*120;
                        saw_magenta |= magenta == 120*120 && dark == 800*480-120*120;
                        const bool rectangle = dark == 800*480-120*120;
                        const bool single_color = yellow == 120*120 || magenta == 120*120 ||
                            red == 120*120 || green == 120*120 || blue == 120*120;
                        if(!bars_valid && !(rectangle && single_color)) {
                            std::fprintf(stderr,"[tb] FAIL: torn or invalid LCD frame\n");
                            return false;
                        }
                        if(rectangle && (!rectangle_valid || rect_x < 40 || rect_x > 540 || (rect_x-40)%100 != 0)) {
                            std::fprintf(stderr,"[tb] FAIL: rectangle geometry x=%d\n",rect_x);
                            return false;
                        }
                        if(rectangle) {
                            saw_motion |= previous_rect_x >= 0 && previous_rect_x != rect_x;
                            previous_rect_x = rect_x;
                        }
                        saw_red |= rectangle && red == 120*120;
                        saw_green |= rectangle && green == 120*120;
                        saw_blue |= rectangle && blue == 120*120;
                        saw_command_bars |= command_stage >= 4 && bars_valid;
                        saw_return_rectangle |= command_stage >= 5 && rectangle && blue == 120*120;
                    }
                    pixels = yellow = magenta = dark = 0;
                    red = green = blue = 0;
                    rect_x = -1;
                    rectangle_valid = bars_valid = true;
                }
                if (top->lcd_de) {
                    const unsigned x = pixels % 800, y = pixels / 800;
                    bars_valid &= top->lcd_rgb == bar_colors[x/100];
                    if(top->lcd_rgb != 0x0010 && rect_x < 0) rect_x = static_cast<int>(x);
                    if(rect_x >= 0) {
                        const bool inside = x >= static_cast<unsigned>(rect_x) && x < static_cast<unsigned>(rect_x+120) && y >= 180 && y < 300;
                        rectangle_valid &= inside == (top->lcd_rgb != 0x0010);
                    }
                    pixels++;
                    yellow += top->lcd_rgb == 0xffe0;
                    magenta += top->lcd_rgb == 0xf81f;
                    dark += top->lcd_rgb == 0x0010;
                    red += top->lcd_rgb == 0xf800;
                    green += top->lcd_rgb == 0x07e0;
                    blue += top->lcd_rgb == 0x001f;
                }
                if(!top->lcd_de && top->lcd_rgb != 0) {
                    std::fprintf(stderr,"[tb] FAIL: nonzero RGB during blanking\n");
                    return false;
                }
                last_vs = top->lcd_vs;
            }
            last_pixel_clk = pixel_clk;
        }
#else
        top->i_clk = 0;
        top->eval();
        top->i_clk = 1;
        top->eval();
#endif
        return true;
    };
    top->i_uart_rx = 1;
    for (int i = 0; i < 8; i++) {
        if(!clock_cycle()) return 1;
    }
    top->i_rst = 0;
#ifdef LCD_SYSTEM
    top->i_pixel_rst = 0;
    top->i_lcd_ready = 1;
#endif

    bool sent = false;
    for (uint64_t c = 0; c < max_cycles; c++) {
        top->i_uart_rx = injector.step() ? 1 : 0;

        if(!clock_cycle()) return 1;

        if (top->o_retire) retired++;

        const int byte = console.step(top->o_uart_tx != 0);
        if (byte >= 0) {
            std::fputc(byte, stdout);
            std::fflush(stdout);
            out.push_back(static_cast<char>(byte));
        }

        // Inject once the firmware has armed its interrupts, so the character
        // exercises the PLIC path rather than being dropped before setup.
        if (!sent && !send.empty() && out.find("armed") != std::string::npos
#ifdef LCD_SYSTEM
            && out.find("[lcd] applied") != std::string::npos
#endif
        ) {
            injector.send(send);
            sent = true;
        }
#ifdef LCD_SYSTEM
        // Advance only after a complete frame confirms the previous command.
        if(sent && !injector.busy()) {
            if(command_stage == 0 && saw_magenta) { injector.send("r"); command_stage=1; }
            else if(command_stage == 1 && saw_red) { injector.send("g"); command_stage=2; }
            else if(command_stage == 2 && saw_green) { injector.send("b"); command_stage=3; }
            else if(command_stage == 3 && saw_blue) { injector.send("c"); command_stage=4; }
            else if(command_stage == 4 && saw_command_bars) { injector.send("m"); command_stage=5; }
        }
#endif
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
#ifdef LCD_SYSTEM
    if (!saw_yellow || !saw_magenta || !saw_red || !saw_green || !saw_blue ||
        !saw_command_bars || !saw_return_rectangle || !saw_motion || frames < 9 ||
        out.find("[lcd] timeout") != std::string::npos || out.find("[trap]") != std::string::npos) {
        std::printf("[tb] FAIL: LCD frames=%u yellow=%d magenta=%d\n", frames, saw_yellow, saw_magenta);
        rc = 1;
    } else {
        std::printf("[tb] LCD: %u frames; yellow/Z/r/g/b colors, c/m mode switch, rectangle geometry and timer motion verified\n", frames);
    }
#endif
    if (rc == 0) std::printf("[tb] PASS\n");

    top->final();
    delete top;
    return rc;
}
