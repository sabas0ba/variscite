/* Polled interface to the Veryl USB transaction engine. No libc or allocation. */
#include "usb_host.h"
#define REG ((volatile uint32_t *)0x11300000u)

void usbh_delay(unsigned microseconds)
{
    uint32_t start=usbh_now_us();
    while ((uint32_t)(usbh_now_us()-start)<microseconds) {}
}

unsigned usbh_identity(void) { return REG[0]; }

void usbh_sof(unsigned enable, unsigned root_speed)
{
    REG[1]=(enable!=0) | ((root_speed==USBH_LOW)<<1);
}

static int command(uint32_t value, uint32_t *status)
{
    uint32_t start=usbh_now_us();
    if (REG[2]&1) return -USBH_LINK;
    __asm__ volatile ("fence iorw,iorw" ::: "memory");
    REG[3]=value|0x80000000u;
    do {
        *status=REG[2];
        if ((*status&3)==2) {
            __asm__ volatile ("fence iorw,iorw" ::: "memory");
            unsigned result=(*status>>4)&15;
            return result==USBH_OK ? 0 : result ? -(int)result : -USBH_LINK;
        }
    } while ((uint32_t)(usbh_now_us()-start)<100000);
    return -USBH_TIMEOUT;
}

int usbh_phy_read(unsigned address, unsigned *value)
{
    uint32_t status;
    if (address>=0x2f) return -USBH_SIZE; /* Extended accesses are unsupported. */
    REG[4]=address;
    int rc=command(USBH_PHY_READ,&status);
    if (!rc) *value=(status>>16)&255;
    return rc;
}

int usbh_phy_write(unsigned address, unsigned value)
{
    uint32_t status;
    if (address>=0x2f || value>255) return -USBH_SIZE;
    REG[4]=address|(value<<8);
    return command(USBH_PHY_WRITE,&status);
}

int usbh_transfer(unsigned operation, struct usbh_packet *packet)
{
    uint32_t status;
    if (operation>USBH_SETUP || packet->address>127 || packet->endpoint>15 ||
        packet->speed<USBH_FULL || packet->speed>USBH_LOW_HUB || packet->toggle>1 ||
        packet->length>64 || (packet->speed!=USBH_FULL && packet->length>8)) return -USBH_SIZE;
    if (REG[2]&1) return -USBH_LINK;
    if (operation!=USBH_IN) {
        for (unsigned i=0;i<packet->length;i+=4) {
            uint32_t word=0;
            for (unsigned lane=0;lane<4 && i+lane<packet->length;lane++)
                word|=(uint32_t)packet->data[i+lane]<<(lane*8);
            REG[16+i/4]=word;
        }
    }
    int rc=command(operation|((unsigned)packet->toggle<<3)|((unsigned)packet->speed<<4)|
        ((operation==USBH_IN?0u:packet->length)<<8)|
        ((unsigned)packet->address<<16)|((unsigned)packet->endpoint<<23),&status);
    if (!rc && operation==USBH_IN) {
        unsigned size=(status>>8)&127;
        if (size>64 || (packet->speed!=USBH_FULL && size>8)) return -USBH_SIZE;
        packet->length=(uint8_t)size;
        packet->toggle=(status>>15)&1;
        for (unsigned i=0;i<size;i+=4) {
            uint32_t word=REG[32+i/4];
            for (unsigned lane=0;lane<4 && i+lane<size;lane++) packet->data[i+lane]=word>>(lane*8);
        }
    }
    return rc;
}

int usbh_root_reset(unsigned *speed)
{
    unsigned line;
    usbh_sof(0,USBH_FULL);
    // Pull-downs on both lines, full-speed receiver, no device pull-up.
    if (usbh_phy_write(0x0a,0x06) || usbh_phy_write(0x04,0x45)) return -USBH_LINK;
    usbh_delay(100000); /* Attachment debounce. */
    if (usbh_phy_read(0x15,&line)) return -USBH_LINK;
    line&=3;
    if (line!=1 && line!=2) return -USBH_TIMEOUT;
    *speed=line==2 ? USBH_LOW : USBH_FULL;
    // HS transceiver's terminations force SE0 for a USB bus reset. No chirp is
    // transmitted, so high-speed capable hubs remain in full-speed mode.
    if (usbh_phy_write(0x04,0x40)) return -USBH_LINK;
    usbh_delay(60000);
    if (usbh_phy_write(0x04,0x44|*speed)) return -USBH_LINK;
    usbh_sof(1,*speed);
    usbh_delay(20000);
    return 0;
}
