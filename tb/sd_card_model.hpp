// Byte-accurate, read-only SDHC SPI model. Rejects unexpected/write commands.
#pragma once
#include <array>
#include <cstdint>
#include <deque>
#include <stdexcept>
#include <vector>

class SdCardModel {
public:
    std::vector<uint8_t> file;
    unsigned reads=0;
    bool corrupt_sector_crc=false;
    bool step(bool cs, bool clk, bool mosi) {
        if(cs) {
            bits=0; input=0; output=255; command.clear(); response.clear();
            previous_clk=clk; return true;
        }
        if(clk && !previous_clk) {
            input=uint8_t((input<<1)|mosi);
            if(++bits==8) consume(input);
        }
        if(!clk && previous_clk && bits==8) {
            bits=0; input=0;
            output=response.empty()?255:response.front();
            if(!response.empty()) response.pop_front();
        }
        previous_clk=clk;
        return ((output>>(7-(bits%8)))&1)!=0;
    }
private:
    bool previous_clk=false, idle=true, application=false;
    unsigned bits=0;
    uint8_t input=0, output=255;
    std::vector<uint8_t> command;
    std::deque<uint8_t> response;
    static void put16(uint8_t *p,unsigned v) { p[0]=v; p[1]=v>>8; }
    static void put32(uint8_t *p,uint32_t v) { put16(p,v); put16(p+2,v>>16); }
    std::array<uint8_t,512> sector(uint32_t address) {
        std::array<uint8_t,512> data{};
        unsigned clusters=(file.size()+511)/512;
        if(address==0) {
            put16(data.data()+11,512); data[13]=1; put16(data.data()+14,1);
            data[16]=1; put16(data.data()+17,16); put16(data.data()+19,5000);
            put16(data.data()+22,20); data[510]=0x55; data[511]=0xaa;
        } else if(address==1) {
            put16(data.data(),0xfff8); put16(data.data()+2,0xffff);
            for(unsigned n=0;n<clusters;n++) put16(data.data()+(n+2)*2,n+1==clusters?0xffff:n+3);
        } else if(address==21) {
            const char name[]="TANGBOOTVBL";
            for(unsigned n=0;n<11;n++) data[n]=name[n];
            data[11]=0x20; put16(data.data()+26,2); put32(data.data()+28,file.size());
        } else if(address>=22 && address<22+clusters) {
            for(unsigned n=0;n<512 && (address-22)*512+n<file.size();n++) data[n]=file[(address-22)*512+n];
        } else throw std::runtime_error("SD model unexpected sector");
        return data;
    }
    void consume(uint8_t byte) {
        if(command.empty() && (byte&0xc0)!=0x40) return;
        command.push_back(byte);
        if(command.size()!=6) return;
        unsigned crc=0;
        for(unsigned n=0;n<5;n++) for(int bit=7;bit>=0;bit--) {
            bool feedback=((crc>>6)^((command[n]>>bit)&1))&1;
            crc=(crc<<1)&127;
            if(feedback) crc^=9;
        }
        if(command[5]!=((crc<<1)|1)) throw std::runtime_error("SD command CRC7");
        uint32_t argument=0;
        for(unsigned n=1;n<5;n++) argument=(argument<<8)|command[n];
        unsigned op=command[0]&63;
        command.clear(); response.push_back(255);
        switch(op) {
        case 0: idle=true; response.push_back(1); break;
        case 8: response.insert(response.end(),{1,0,0,1,0xaa}); break;
        case 55: application=true; response.push_back(idle?1:0); break;
        case 41:
            if(!application || !(argument&0x40000000)) throw std::runtime_error("SD ACMD41");
            application=false; idle=false; response.push_back(0); break;
        case 58: response.insert(response.end(),{0,0xc0,0xff,0x80,0}); break;
        case 17: {
            if(idle) throw std::runtime_error("SD read before initialization");
            ++reads;
            auto data=sector(argument);
            response.insert(response.end(),{0,255,255,0xfe});
            uint16_t crc16=0;
            for(uint8_t value:data) {
                response.push_back(value); crc16^=uint16_t(value)<<8;
                for(unsigned bit=0;bit<8;bit++) crc16=uint16_t((crc16<<1)^((crc16&0x8000)?0x1021:0));
            }
            response.push_back(crc16>>8); response.push_back(uint8_t(crc16)^corrupt_sector_crc);
            break;
        }
        default: throw std::runtime_error("SD unexpected or write command");
        }
    }
};
