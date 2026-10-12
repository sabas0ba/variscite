#include <assert.h>
#include <stdio.h>
#include <string.h>
#include "sd_boot.h"
static uint8_t mbr[512],boot[512],fat[512],root[512];
static uint8_t extended[10][512],checksums[512],root_tail[512];
static unsigned exfat;
static uint32_t base,fat_sector,root_sector,first_sector,next_sector;
static void put16(uint8_t *p,unsigned v) { p[0]=(uint8_t)v;p[1]=(uint8_t)(v>>8); }
static void put32(uint8_t *p,uint32_t v) { put16(p,v&65535);put16(p+2,v>>16); }
int sd_read_sector(struct sd_card *card,uint32_t sector,uint8_t *data)
{
    (void)card;
    if(exfat && sector>base && sector<base+11) { memcpy(data,extended[sector-base-1],512); return 0; }
    if(exfat && sector==base+11) { memcpy(data,checksums,512); return 0; }
    if(exfat && sector==root_sector+4) { memcpy(data,root_tail,512); return 0; }
    if(sector==0 && base) memcpy(data,mbr,512);
    else if(sector==base) memcpy(data,boot,512);
    else if(sector==fat_sector) memcpy(data,fat,512);
    else if(sector==root_sector) memcpy(data,root,512);
    else if(sector==first_sector) memset(data,0x5a,512);
    else if(sector==next_sector) memset(data,0xa5,512);
    else return -1;
    return 0;
}
static void setup(unsigned fat32)
{
    exfat=0;
    memset(mbr,0,512);memset(boot,0,512);memset(fat,0,512);memset(root,0,512);
    base=fat32?2048:0;
    mbr[510]=boot[510]=0x55;mbr[511]=boot[511]=0xaa;
    mbr[450]=0x0c;put32(mbr+454,base);put32(mbr+458,70000);
    put16(boot+11,512);boot[13]=1;boot[16]=1;
    put16(boot+14,fat32?32:1);
    put16(boot+17,fat32?0:16);
    if(fat32) { put32(boot+32,70000);put32(boot+36,600);put32(boot+44,2); }
    else { put16(boot+19,5000);put16(boot+22,20); }
    fat_sector=base+(fat32?32:1);
    root_sector=fat_sector+(fat32?600:20);
    first_sector=root_sector+1;next_sector=first_sector+2;
    memcpy(root,"TANGBOOTVBL",11);root[11]=0x20;
    put16(root+26,fat32?3:2);put32(root+28,600);
    if(fat32) { put32(fat+8,0x0fffffff);put32(fat+12,5);put32(fat+20,0x0fffffff); }
    else { put16(fat+4,4);put16(fat+8,0xffff); }
}
static void exfat_checksum(void)
{
    uint32_t sum=0;
    for(unsigned s=0;s<11;s++) for(unsigned n=0;n<512;n++) {
        if(!s && (n==106 || n==107 || n==112)) continue;
        sum=((sum>>1)|(sum<<31))+(s?extended[s-1][n]:boot[n]);
    }
    for(unsigned n=0;n<512;n+=4) put32(checksums+n,sum);
}
static void exfat_entry_checksum(void)
{
    unsigned sum=0;
    for(unsigned n=0;n<96;n++) {
        if(n==2 || n==3) continue;
        unsigned byte=n<32?root[480+n]:root_tail[n-32];
        sum=(((sum>>1)|(sum<<15))+byte)&65535;
    }
    put16(root+482,sum);
}
static void setup_exfat(unsigned contiguous)
{
    setup(0); exfat=1; base=2048;
    memset(boot,0,512); memset(extended,0,sizeof(extended));
    memset(fat,0,512); memset(root,0,512); memset(root_tail,0,512);
    mbr[450]=7; put32(mbr+454,base); put32(mbr+458,5000);
    memcpy(boot+3,"EXFAT   ",8); put32(boot+64,base); put32(boot+72,5000);
    put32(boot+80,24); put32(boot+84,40); put32(boot+88,80);
    put32(boot+92,4920); put32(boot+96,2); boot[105]=1; boot[108]=9; boot[110]=1;
    boot[510]=0x55; boot[511]=0xaa;
    for(unsigned n=0;n<8;n++) put32(extended[n]+508,0xaa550000);
    fat_sector=base+24; root_sector=base+80;
    first_sector=root_sector+1; next_sector=first_sector+(contiguous?1:2);
    put32(fat+8,6); put32(fat+24,0xffffffff); put32(fat+12,5); put32(fat+20,0xffffffff);
    // Entry set straddles both a sector boundary and a fragmented directory chain.
    for(unsigned n=0;n<480;n+=32) root[n]=0x05;
    root[480]=0x85; root[481]=2; put16(root+484,0x20);
    root_tail[0]=0xc0; root_tail[1]=(uint8_t)(1|(contiguous<<1)); root_tail[3]=12;
    put32(root_tail+8,600); put32(root_tail+20,3); put32(root_tail+24,600);
    root_tail[32]=0xc1;
    for(unsigned n=0;n<12;n++) put16(root_tail+34+n*2,(unsigned char)"TangBoot.vbl"[n]);
    exfat_entry_checksum(); exfat_checksum();
}
static void read_exfat(unsigned contiguous)
{
    struct sd_file f;
    setup_exfat(contiguous); assert(sd_file_open(&f)==0);
    for(unsigned n=0;n<600;n++) assert(sd_file_byte(&f)==(n<512?0x5a:0xa5));
    assert(sd_file_byte(&f)<0);
}
static void read_file(unsigned fat32)
{
    struct sd_file f;
    setup(fat32);assert(sd_file_open(&f)==0);
    for(unsigned n=0;n<600;n++) assert(sd_file_byte(&f)==(n<512?0x5a:0xa5));
    assert(sd_file_byte(&f)<0);
}
int main(void)
{
    struct sd_file f;
    read_file(0);read_file(1);
    setup(0);boot[13]=3;assert(sd_file_open(&f)<0);
    setup(0);root[0]=0;assert(sd_file_open(&f)<0);
    setup(0);put32(root+28,0xffffffff);assert(sd_file_open(&f)<0);
    setup(0);put16(fat+4,0xffff);assert(sd_file_open(&f)==0);
    for(unsigned n=0;n<512;n++) assert(sd_file_byte(&f)==0x5a);
    assert(sd_file_byte(&f)<0);
    setup(1);put32(mbr+454,0xfffffff0);assert(sd_file_open(&f)<0);
    setup(1);put16(boot+40,0x81);assert(sd_file_open(&f)<0); // nonexistent active FAT
    setup(1);boot[510]=0;assert(sd_file_open(&f)<0);
    read_exfat(0); read_exfat(1);
    setup_exfat(1); checksums[0]^=1; assert(sd_file_open(&f)<0);
    setup_exfat(1); root[482]^=1; assert(sd_file_open(&f)<0);
    setup_exfat(1); put32(root_tail+8,599); exfat_entry_checksum(); assert(sd_file_open(&f)<0);
    setup_exfat(1); boot[108]=12; exfat_checksum(); assert(sd_file_open(&f)<0);
    setup_exfat(1); put32(boot+76,1); exfat_checksum(); assert(sd_file_open(&f)<0);
    setup_exfat(0); put32(fat+12,0xffffffff); assert(sd_file_open(&f)==0);
    for(unsigned n=0;n<512;n++) assert(sd_file_byte(&f)==0x5a);
    assert(sd_file_byte(&f)<0);
    puts("PASS: FAT16/FAT32/exFAT, fragmented/contiguous files, directory boundaries, checksums, geometry, truncation");
    return 0;
}
