// Compile the actual upstream method against a deterministic JTAG transport.
#include <cassert>
#include <cstdint>
#include <cstdio>
#include <cstring>
#include <vector>

struct FsParser {
    static uint8_t reverseByte(uint8_t value) {
        uint8_t result = 0;
        for (int bit = 0; bit < 8; ++bit) {
            result = (result << 1) | (value & 1);
            value >>= 1;
        }
        return result;
    }
};

struct Jtag {
    enum { EXIT2_DR };
    std::vector<uint8_t> sent;
    void set_state(int) {}
    void flush() {}
    static uint8_t received(size_t index) { return (index * 73 + 19) & 255; }
    void shiftDR(const uint8_t *tx, uint8_t *rx, uint32_t bits) {
        assert(bits % 8 == 0);
        sent.assign(tx, tx + bits / 8);
        if (rx) {
            for (uint32_t i = 0; i < bits / 8; ++i) rx[i] = received(i);
        }
    }
};

struct Gowin {
    bool is_gw5a = false, is_gw2a = true, command_ok = true;
    uint8_t _spi_msk = 0, _spi_do = 0, _spi_cs = 0, _spi_di = 0, _spi_sck = 0;
    Jtag *_jtag;
    explicit Gowin(Jtag &jtag) : _jtag(&jtag) {}
    bool send_command(uint8_t command) { assert(command == 0x16); return command_ok; }
    int spi_put(const uint8_t *, uint8_t *, uint32_t);
    int spi_put_gw5a(uint8_t, const uint8_t *, uint8_t *, uint32_t) { assert(false); return -1; }
    void spi_gowin_write(const uint8_t *, uint8_t *, int) { assert(false); }
};

#include "gw2a-spi.inc"

int main() {
    Jtag jtag;
    Gowin device(jtag);
    for (uint32_t length : {1u, 2u, 4u, 128u, 256u, 260u}) {
        std::vector<uint8_t> tx(length), rx(length);
        for (uint32_t i = 0; i < length; ++i) tx[i] = (i * 31 + 7) & 255;
        assert(device.spi_put(tx.data(), rx.data(), length) == 0);
        assert(jtag.sent.size() == length + 1);
        for (uint32_t i = 0; i < length; ++i) {
            assert(jtag.sent[i] == FsParser::reverseByte(tx[i]));
            assert(rx[i] == (FsParser::reverseByte(Jtag::received(i) >> 1) |
                (Jtag::received(i + 1) & 1)));
        }
        assert(jtag.sent.back() == 0);
        assert(device.spi_put(tx.data(), nullptr, length) == 0);
        assert(jtag.sent.size() == length);
        assert(device.spi_put(nullptr, rx.data(), length) == 0);
        for (uint8_t byte : jtag.sent) assert(byte == 0);
    }
    device.command_ok = false;
    uint8_t tx = 0, rx = 0;
    assert(device.spi_put(&tx, &rx, 1) == -1);
    puts("GW2A SPI transfer bounds and one-bit read alignment: PASS");
}
