/* SD SPI initialization and single-sector reads. Never issues a write command. */
#include "sd_boot.h"
#define SD ((volatile uint32_t *)0x11400000u)
static uint32_t now(void) { return *(volatile uint32_t *)0x1100bff8u; }
static int byte(unsigned value)
{
    uint32_t start=now();
    SD[3]=value;
    while(SD[2]&1) if((uint32_t)(now()-start)>10000) return -1;
    return (int)((SD[2]>>8)&255);
}
static void deselect(struct sd_card *card) { SD[1]=card->clock_mode|1; (void)byte(255); }
static int command(struct sd_card *card, unsigned cmd, uint32_t argument)
{
    deselect(card); SD[1]=card->clock_mode;
    if(byte(255)<0) return -1;
    uint8_t bytes[5];
    bytes[0]=(uint8_t)(0x40|cmd);
    bytes[1]=(uint8_t)(argument>>24); bytes[2]=(uint8_t)(argument>>16);
    bytes[3]=(uint8_t)(argument>>8); bytes[4]=(uint8_t)argument;
    unsigned crc=0;
    for(unsigned n=0;n<5;n++) {
        unsigned d=bytes[n];
        for(unsigned bit=0;bit<8;bit++) {
            crc<<=1;
            if((d^crc)&0x80) crc^=9;
            d<<=1;
        }
        if(byte(bytes[n])<0) return -1;
    }
    if(byte(((crc&127)<<1)|1)<0) return -1;
    for(unsigned n=0;n<16;n++) {
        int response=byte(255);
        if(response<0 || !(response&128)) return response;
    }
    return -1;
}
static int word(uint32_t *value)
{
    uint32_t result=0;
    for(unsigned n=0;n<4;n++) {
        int data=byte(255);
        if(data<0) return -1;
        result=(result<<8)|(unsigned)data;
    }
    *value=result;
    return 0;
}
int sd_card_init(struct sd_card *card)
{
    if(SD[0]!=0x53445031) return -1;
    card->clock_mode=2; card->block_addressing=0;
    SD[1]=3;
    uint32_t start=now();
    while((uint32_t)(now()-start)<2000) {}
    for(unsigned n=0;n<10;n++) if(byte(255)<0) return -1;
    if(command(card,0,0)!=1) { deselect(card); return -1; }
    int response=command(card,8,0x1aa);
    unsigned modern=response==1;
    uint32_t answer=0;
    if(modern) {
        if(word(&answer)<0 || answer!=0x1aa) { deselect(card); return -1; }
    } else if(response!=5) { deselect(card); return -1; }
    start=now();
    do {
        response=command(card,55,0);
        if(response!=1 && response!=0) break;
        response=command(card,41,modern?0x40000000:0);
        if(response==0) break;
        if(response!=1) break;
    } while((uint32_t)(now()-start)<2000000);
    if(response!=0 || command(card,58,0)!=0 || word(&answer)<0 || !(answer&0x80000000) ||
        !(answer&0x00300000)) { deselect(card); return -1; }
    card->block_addressing=modern && (answer&0x40000000);
    if(!card->block_addressing && command(card,16,512)!=0) { deselect(card); return -1; }
    deselect(card); card->clock_mode=0; SD[1]=1;
    return 0;
}
int sd_read_sector(struct sd_card *card, uint32_t sector, uint8_t *data)
{
    if(!card->block_addressing && sector>0x7fffff) return -1;
    if(command(card,17,card->block_addressing?sector:sector*512)!=0) { deselect(card); return -1; }
    uint32_t start=now();
    int token;
    do {
        token=byte(255);
        if(token!=255) break;
    } while((uint32_t)(now()-start)<200000);
    if(token!=0xfe) { deselect(card); return -1; }
    unsigned crc=0;
    for(unsigned n=0;n<512;n++) {
        int value=byte(255);
        if(value<0) { deselect(card); return -1; }
        data[n]=(uint8_t)value;
        crc^=(unsigned)value<<8;
        for(unsigned bit=0;bit<8;bit++) crc=((crc<<1)^((crc&0x8000)?0x1021:0))&0xffff;
    }
    int hi=byte(255), lo=byte(255);
    deselect(card);
    return hi>=0 && lo>=0 && crc==((unsigned)hi<<8 | (unsigned)lo)?0:-1;
}
