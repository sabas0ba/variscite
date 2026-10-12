// Standalone top for ROM/clock parameters and a sparse, delayed DDR backend.
// Runs the real CPU and bit-level UART; no memory-port or ROM instruction bypass.
#ifdef CACHED_BOOT
#include "Vtb_tang_cached_boot.h"
using BootDut = Vtb_tang_cached_boot;
#else
#include "Vrv32ima_DdrLinuxSoc.h"
using BootDut = Vrv32ima_DdrLinuxSoc;
#endif
#include "verilated.h"
#include <algorithm>
#include <array>
#include <cstdint>
#include <deque>
#include <fstream>
#include <iostream>
#include <iterator>
#include <stdexcept>
#include <unordered_map>
#include <vector>

using Bytes = std::vector<uint8_t>;
static void check(bool ok, const char *message) { if (!ok) throw std::runtime_error(message); }
static uint32_t crc32(const Bytes &data) {
    uint32_t crc = ~0u;
    for (uint8_t c : data) {
        crc ^= c;
        for (int i=0; i<8; ++i) crc = (crc>>1) ^ (0xedb88320u & (0u-(crc&1)));
    }
    return ~crc;
}
static void word(Bytes &out, uint32_t value) {
    for (int i=0; i<4; ++i) out.push_back(value>>(8*i));
}
static Bytes packet(char command, uint32_t address, const Bytes &data) {
    Bytes header;
    word(header, 0x314c4256); word(header, command); word(header, address); word(header, data.size());
    Bytes checked=header;
    checked.insert(checked.end(), data.begin(), data.end());
    word(header, crc32(checked));
    header.insert(header.end(), data.begin(), data.end());
    return header;
}

class Bench {
public:
    BootDut dut;
    std::unordered_map<uint32_t, std::array<uint8_t,16>> memory;
    std::deque<uint8_t> received;
    uint64_t ticks=0, transactions=0;
    bool inject_error=false;
    static constexpr unsigned bit_cycles=240;
    unsigned host_bit_cycles=240;
    unsigned response_budget=3000000;
    void step() {
        bool mem_rise=!(ticks&1), cpu_rise=ticks%4==0;
        bool req=mem_rise && dut.o_req_valid && dut.i_req_ready;
        bool rsp=mem_rise && dut.i_rsp_valid && dut.o_rsp_ready;
        uint32_t address=dut.o_req_addr;
        uint16_t strobes=dut.o_req_wstrb;
        std::array<uint32_t,4> data{};
        for (int i=0;i<4;++i) data[i]=dut.o_req_wdata[i];
        dut.i_mem_clk=mem_rise;
        dut.i_cpu_clk=ticks%4<2;
        dut.eval();
        if (cpu_rise && !dut.i_reset) sample_tx();
        if (mem_rise) {
            if (dut.i_reset) {
                pending=0; dut.i_rsp_valid=0; dut.i_rsp_error=0; dut.i_req_ready=0;
            } else {
                if (rsp) dut.i_rsp_valid=0;
                if (pending && --pending==0) dut.i_rsp_valid=1;
                if (req) {
                    check(!pending && !dut.i_rsp_valid, "overlapping DDR request");
                    check(!(address&15), "unaligned burst");
                    ++transactions;
                    auto &bytes=memory[address];
                    for (int i=0;i<16;++i)
                        if (strobes&(1u<<i)) bytes[i]=data[i/4]>>(8*(i%4));
                    for (int i=0;i<4;++i) {
                        uint32_t value=0;
                        for (int b=0;b<4;++b) value|=uint32_t(bytes[4*i+b])<<(8*b);
                        dut.i_rsp_data[i]=value;
                    }
                    dut.i_rsp_error=inject_error;
                    pending=3+transactions%7;
                }
                dut.i_req_ready=!pending && !dut.i_rsp_valid && ticks%7==0;
            }
        }
        dut.eval(); ++ticks;
        check(ticks<600000000, "simulation timeout");
    }
    void cycles(unsigned n) { for (unsigned i=0;i<n*4;++i) step(); }
    void reset() {
        dut.i_reset=1; dut.i_enable=0; dut.i_uart_rx=1; dut.i_display_error=0;
        cycles(12); dut.i_reset=0;
        check(!dut.o_display_enable, "display enable survived reset");
        received.clear(); tx_state=0; previous_tx=1;
    }
    void send(const Bytes &data) {
        for (uint8_t c : data) {
            dut.i_uart_rx=0; cycles(host_bit_cycles);
            for (int i=0;i<8;++i) { dut.i_uart_rx=(c>>i)&1; cycles(host_bit_cycles); }
            dut.i_uart_rx=1; cycles(host_bit_cycles);
        }
    }
    uint8_t get() {
        for (unsigned i=0; received.empty() && i<response_budget; ++i) step();
        if (received.empty()) {
            std::cerr << "ticks=" << ticks << " requests=" << transactions
                      << " shutdown=" << unsigned(dut.o_shutdown) << " code=" << std::hex << dut.o_exit_code << '\n';
            throw std::runtime_error("UART response timeout");
        }
        uint8_t c=received.front(); received.pop_front(); return c;
    }
    void expect(const char *text) { while (*text) check(get()==uint8_t(*text++), "unexpected UART response"); }
private:
    unsigned pending=0, tx_state=0, tx_count=0, tx_bit=0;
    uint8_t tx_byte=0;
    bool previous_tx=1;
    void sample_tx() {
        bool level=dut.o_uart_tx;
        if (!tx_state && previous_tx && !level) {
            tx_state=1; tx_count=bit_cycles+bit_cycles/2; tx_bit=0; tx_byte=0;
        } else if (tx_state && --tx_count==0) {
            if (tx_bit<8) { tx_byte|=uint8_t(level)<<tx_bit++; tx_count=bit_cycles; }
            else { check(level, "UART stop bit"); received.push_back(tx_byte); tx_state=0; }
        }
        previous_tx=level;
    }
};

int main(int argc, char **argv) {
    Verilated::commandArgs(argc,argv);
    try {
        check(crc32(Bytes{'1','2','3','4','5','6','7','8','9'})==0xcbf43926u, "CRC reference");
        Bench b;
        if (argc>=2) b.host_bit_cycles=std::stoul(argv[1]);
        bool lcd=argc>=3 && std::string(argv[2])=="lcd";
        if(lcd) b.response_budget=200000000;
        b.reset(); b.cycles(1000);
        check(b.transactions==0 && b.received.empty(), "CPU ran before training");
        b.dut.i_enable=1;
        b.expect("VBL1\n");
        if(lcd) {
            check(b.dut.o_display_enable, "LCD ROM did not enable scanout");
            const uint16_t colors[8]={0xffff,0xffe0,0x07ff,0x07e0,0xf81f,0xf800,0x001f,0};
            for(unsigned pixel=0;pixel<800*480;++pixel) {
                uint32_t address=0x07c00000+pixel*2;
                const auto &bytes=b.memory.at(address&~15u);
                unsigned lane=address&15;
                check((bytes[lane]|(uint16_t(bytes[lane+1])<<8))==colors[(pixel%800)/100], "ROM framebuffer pattern");
            }
            b.dut.i_display_error=3;
        }
        std::cout << "Boot banner received\n";
        Bytes data{0xaa,0x55,0xcc,0x33};
        auto damaged=packet('W',0x80000000,data); damaged.back()^=1;
        b.send(damaged); b.expect("E");
        check(b.memory.find(0)==b.memory.end(), "CRC failure modified image");
        b.send(packet('W',0x1000,data)); b.expect("E");
        b.send(packet('W',0x81ffffff,data)); b.expect("E");
        b.send(packet('W',0x87e0ffff,data)); b.expect("E");
        b.send(packet('W',0xfffffffcu,data)); b.expect("E");
        b.send(packet('?',0x80000000,data)); b.expect("E");
        std::ifstream stream(lcd ? "sim/tang_boot_lcd_payload.bin" : "sim/tang_boot_payload.bin",std::ios::binary);
        check(bool(stream), "missing payload");
        Bytes image((std::istreambuf_iterator<char>(stream)),{});
        Bytes dtb(40,0); dtb[0]=0xd0; dtb[1]=0x0d; dtb[2]=0xfe; dtb[3]=0xed;
        for (size_t i=0;i<image.size();i+=256) {
            Bytes chunk(image.begin()+i,image.begin()+std::min(i+256,image.size()));
            b.send(packet('W',0x80000000+i,chunk)); b.expect("K");
        }
        b.send(packet('W',0x87e00000,dtb)); b.expect("K");
        Bytes manifest;
        word(manifest,image.size()); word(manifest,dtb.size()); word(manifest,crc32(image)^1); word(manifest,crc32(dtb));
        b.send(packet('B',0x80000000,manifest)); b.expect("E");
        manifest[8]^=1;
        b.send(packet('B',0x80000000,manifest)); b.expect("K");
        for (unsigned i=0;!b.dut.o_shutdown && i<1000000;++i) b.step();
        check(b.dut.o_shutdown && b.dut.o_exit_code==0x5555, "payload ABI/timer/PLIC/DDR failure");
        b.reset(); b.inject_error=true; b.dut.i_enable=1;
        for (unsigned i=0;!b.dut.o_shutdown && i<100000;++i) b.step();
        check(b.dut.o_shutdown && b.dut.o_exit_code==0xbad, "DDR error did not trap");
        if(lcd) std::cout << "LCD boot PASS: complete RGB565 initialization, enable/status, masks, sticky enable, reset\n";
        std::cout << "Tang boot PASS: UART upload, CRC/range rejection, entry ABI, DDR, timer, PLIC, reset/error\n";
    } catch (const std::exception &error) {
        std::cerr << error.what() << '\n'; return 1;
    }
}
