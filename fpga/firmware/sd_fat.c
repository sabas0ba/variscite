/* Bounded, read-only FAT16/FAT32/exFAT traversal for one ASCII boot filename.
 * Format reference: learn.microsoft.com/windows/win32/fileio/exfat-specification
 * No allocation bitmap updates, writes, or general Unicode name lookup. */
#include "sd_boot.h"
static unsigned le16(const uint8_t *p) { return p[0]|((unsigned)p[1]<<8); }
static uint32_t le32(const uint8_t *p) { return le16(p)|((uint32_t)le16(p+2)<<16); }
static int read_sector(struct sd_file *f,uint32_t sector)
{
    if(sector>=f->volume_end) return -1;
    return sd_read_sector(&f->card,sector,f->sector);
}
static int next_cluster(struct sd_file *f,uint32_t *cluster)
{
    unsigned entries=f->fat32?128:256;
    uint32_t page=*cluster/entries;
    unsigned offset=(*cluster%entries)*(f->fat32?4:2);
    if(page>=f->fat_sectors || read_sector(f,f->fat_start+page)<0) return -1;
    uint32_t next=f->fat32?le32(f->sector+offset):le16(f->sector+offset);
    if(f->fat32==1) next&=0x0fffffff;
    if(next>=(f->fat32==2?0xffffffffu:f->fat32?0x0ffffff8u:0xfff8u)) return 1;
    if(next<2 || next-2>=f->clusters) return -1;
    *cluster=next;
    return 0;
}
static int find_entry(struct sd_file *f)
{
    static const char name[11]={'T','A','N','G','B','O','O','T','V','B','L'};
    for(unsigned offset=0;offset<512;offset+=32) {
        const uint8_t *entry=f->sector+offset;
        if(!entry[0]) return -1;
        if(entry[0]==0xe5 || (entry[11]&0x18) || entry[11]==0x0f) continue;
        unsigned n;
        for(n=0;n<11;n++) if(entry[n]!=(uint8_t)name[n]) break;
        if(n!=11) continue;
        f->cluster=le16(entry+26)|(f->fat32?(uint32_t)le16(entry+20)<<16:0);
        f->remaining=le32(entry+28);
        if(f->cluster<2 || f->cluster-2>=f->clusters || f->remaining<20 || f->remaining>36u*1024*1024) return -1;
        f->sector_in_cluster=0; f->position=512; f->traversed=1;
        return 1;
    }
    return 0;
}
static int exfat_signature(const uint8_t *p)
{
    static const char signature[]="EXFAT   ";
    for(unsigned n=0;n<8;n++) if(p[n+3]!=(uint8_t)signature[n]) return 0;
    return 1;
}
static unsigned entry_sum(unsigned sum,const uint8_t *entry,unsigned primary)
{
    for(unsigned n=0;n<32;n++) {
        if(primary && (n==2 || n==3)) continue;
        sum=(((sum>>1)|(sum<<15))+entry[n])&65535;
    }
    return sum;
}
static int directory_entry(struct sd_file *f,uint8_t *entry)
{
    for(unsigned n=0;n<32;n++) {
        int value=sd_file_byte(f);
        if(value<0) return -1;
        entry[n]=(uint8_t)value;
    }
    return 0;
}
static int open_exfat(struct sd_file *f,uint32_t base,uint32_t partition_size)
{
    const uint8_t *b=f->sector;
    uint32_t total=le32(b+72), fat=le32(b+80), fat_length=le32(b+84);
    uint32_t heap=le32(b+88), clusters=le32(b+92), root=le32(b+96);
    unsigned fats=b[110], active=le16(b+106)&1, shift=b[109];
    if(!exfat_signature(b) || b[510]!=0x55 || b[511]!=0xaa || b[108]!=9 || shift>16 || b[105]!=1 ||
       le32(b+76) || !total || base>0xffffffffu-total ||
       (partition_size && total>partition_size) || (fats!=1 && fats!=2) || active>=fats ||
       fat<24 || !fat_length || fat>=heap || heap>=total || fat_length>(heap-fat)/fats ||
       !clusters || clusters>0xfffffff5u || clusters>(total-heap)/(1u<<shift) ||
       fat_length<(clusters+1u)/128u+1u || root<2 || root-2>=clusters) return -1;
    for(unsigned n=11;n<64;n++) if(b[n]) return -1;
    f->volume_end=base+total; f->fat_start=base+fat+active*fat_length;
    f->fat_sectors=fat_length; f->data_start=base+heap; f->clusters=clusters;
    f->sectors_per_cluster=1u<<shift; f->fat32=2;
    uint32_t checksum=0;
    for(unsigned sector=0;sector<11;sector++) {
        if(read_sector(f,base+sector)<0) return -1;
        for(unsigned n=0;n<512;n++) {
            if(!sector && (n==106 || n==107 || n==112)) continue;
            checksum=((checksum>>1)|(checksum<<31))+f->sector[n];
        }
    }
    if(read_sector(f,base+11)<0) return -1;
    for(unsigned n=0;n<512;n+=4) if(le32(f->sector+n)!=checksum) return -1;
    f->cluster=root; f->remaining=2u*1024*1024; f->traversed=1;
    f->position=512; f->sector_in_cluster=0; f->contiguous=0;
    uint8_t entry[32];
    static const char filename[]="TANGBOOT.VBL";
    while(directory_entry(f,entry)==0 && entry[0]) {
        if(entry[0]!=0x85) continue;
        unsigned secondaries=entry[1], expected=le16(entry+2);
        unsigned sum=entry_sum(0,entry,1), match=secondaries>=2 && !(le16(entry+4)&0x10);
        uint32_t first=0, length=0;
        unsigned contiguous=0;
        for(unsigned n=0;n<secondaries;n++) {
            if(directory_entry(f,entry)<0) return -1;
            sum=entry_sum(sum,entry,0);
            if(n==0) {
                if(entry[0]!=0xc0 || !(entry[1]&1) || entry[3]!=12 ||
                   le32(entry+12) || le32(entry+28) || le32(entry+8)!=le32(entry+24)) match=0;
                first=le32(entry+20); length=le32(entry+24); contiguous=(entry[1]>>1)&1;
            } else if(n==1) {
                if(entry[0]!=0xc1) match=0;
                for(unsigned i=0;i<12;i++) {
                    unsigned c=le16(entry+2+i*2);
                    if(c>='a' && c<='z') c-=32;
                    if(c!=(unsigned char)filename[i]) match=0;
                }
            } else if((entry[0]&0xe0)!=0xe0) match=0;
        }
        if(!match) continue;
        if(sum!=expected || first<2 || first-2>=clusters || length<20 || length>36u*1024*1024) return -1;
        uint32_t needed=(length+511u)/512u;
        needed=(needed+f->sectors_per_cluster-1)/f->sectors_per_cluster;
        if(contiguous && needed>clusters-(first-2)) return -1;
        f->cluster=first; f->remaining=length; f->contiguous=contiguous;
        f->position=512; f->sector_in_cluster=0; f->traversed=1;
        return 0;
    }
    return -1;
}
int sd_file_open(struct sd_file *f)
{
    f->contiguous=0;
    if(sd_read_sector(&f->card,0,f->sector)<0) return -1;
    if(f->sector[510]!=0x55 || f->sector[511]!=0xaa) return -1;
    uint32_t base=0, partition_size=0;
    // A valid 512-byte BPB identifies a superfloppy. Otherwise use the first
    // supported primary partition; GPT and extended partitions are unsupported.
    if(le16(f->sector+11)!=512 && !exfat_signature(f->sector)) {
        unsigned found=0;
        for(unsigned n=0;n<4;n++) {
            const uint8_t *p=f->sector+446+n*16;
            unsigned type=p[4];
            if(type!=4 && type!=6 && type!=7 && type!=0x0b && type!=0x0c && type!=0x0e) continue;
            base=le32(p+8); partition_size=le32(p+12); found=1; break;
        }
        if(!found || !base || !partition_size || base>0xffffffffu-partition_size || sd_read_sector(&f->card,base,f->sector)<0) return -1;
    }
    if(exfat_signature(f->sector)) return open_exfat(f,base,partition_size);
    if(f->sector[510]!=0x55 || f->sector[511]!=0xaa || le16(f->sector+11)!=512) return -1;
    unsigned spc=f->sector[13], reserved=le16(f->sector+14), fats=f->sector[16];
    unsigned roots=le16(f->sector+17);
    uint32_t total=le16(f->sector+19); if(!total) total=le32(f->sector+32);
    uint32_t fat_size=le16(f->sector+22); if(!fat_size) fat_size=le32(f->sector+36);
    if(!spc || spc>128 || (spc&(spc-1)) || !reserved || (fats!=1 && fats!=2) ||
        !fat_size || !total || fat_size>total/fats || base>0xffffffffu-total ||
        (partition_size && total>partition_size)) return -1;
    uint32_t root_sectors=(roots+15u)/16;
    uint32_t used=fat_size*fats;
    if(used>total || reserved>total-used || root_sectors>total-used-reserved) return -1;
    used+=reserved+root_sectors;
    f->clusters=(total-used)/spc;
    if(f->clusters<4085 || f->clusters>0x0ffffff5u) return -1;
    f->fat32=f->clusters>=65525;
    if((f->fat32 && (roots || le16(f->sector+22))) || (!f->fat32 && !roots)) return -1;
    unsigned entries=f->fat32?128:256;
    if(fat_size<(f->clusters+2+entries-1)/entries) return -1;
    f->volume_end=base+total; f->fat_start=base+reserved; f->fat_sectors=fat_size;
    f->data_start=base+used; f->sectors_per_cluster=spc;
    uint32_t root_cluster=f->fat32?(le32(f->sector+44)&0x0fffffff):0;
    if(f->fat32) {
        unsigned flags=le16(f->sector+40);
        if(le16(f->sector+42)) return -1; // FAT32 version 0 only.
        if(flags&0x80) {
            if((flags&15)>=fats) return -1;
            f->fat_start+=(flags&15)*fat_size;
        }
        // Bound startup time even if a corrupt FAT links the directory cyclically.
        for(uint32_t visited=0;visited<f->clusters && visited<4096u/spc;visited++) {
            if(root_cluster<2 || root_cluster-2>=f->clusters) return -1;
            for(unsigned n=0;n<spc;n++) {
                if(read_sector(f,f->data_start+(root_cluster-2)*spc+n)<0) return -1;
                int rc=find_entry(f); if(rc) return rc==1?0:-1;
            }
            if(next_cluster(f,&root_cluster)!=0) return -1;
        }
    } else {
        uint32_t root_start=base+reserved+fats*fat_size;
        for(uint32_t n=0;n<root_sectors;n++) {
            if(read_sector(f,root_start+n)<0) return -1;
            int rc=find_entry(f); if(rc) return rc==1?0:-1;
        }
    }
    return -1;
}
int sd_file_byte(struct sd_file *f)
{
    if(!f->remaining) return -1;
    if(f->position==512) {
        if(f->sector_in_cluster==f->sectors_per_cluster) {
            if(f->traversed++>=f->clusters) return -1;
            if(f->contiguous) {
                if(++f->cluster-2>=f->clusters) return -1;
            } else if(next_cluster(f,&f->cluster)!=0) return -1;
            f->sector_in_cluster=0;
        }
        uint32_t sector=f->data_start+(f->cluster-2)*f->sectors_per_cluster+f->sector_in_cluster++;
        if(read_sector(f,sector)<0) return -1;
        f->position=0;
    }
    f->remaining--;
    return f->sector[f->position++];
}
