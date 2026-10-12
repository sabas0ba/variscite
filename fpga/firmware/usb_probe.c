/* UART diagnostics for the Dock PHY before Linux/HID integration. */
#include "usb_host.h"
#ifdef USB_HID_PROBE
#include "usb_hid.h"
#endif
#define UART ((volatile uint32_t *)0x10000000u)
uint32_t usbh_now_us(void) { return *(volatile uint32_t *)0x1100bff8u; }
static void text(const char *s)
{
    while (*s) { while (!(UART[5]&0x20)) {} UART[0]=(unsigned char)*s++; }
}
static void hex(unsigned value)
{
    char output[9];
    for (unsigned n=0;n<8;n++) {
        unsigned digit=(value>>((7-n)*4))&15;
        output[n]=(char)(digit<10?'0'+digit:'a'+digit-10);
    }
    output[8]=0; text(output);
}
void boot_main(void)
{
    text("USB probe: identity="); hex(usbh_identity()); text("\n");
    usbh_delay(100000);
    for (unsigned address=0;address<4;address++) {
        unsigned value=0;
        int rc=usbh_phy_read(address,&value);
        text("PHY "); hex(address); text(" value="); hex(value); text(" rc="); hex((unsigned)rc); text("\n");
        volatile uint32_t *registers=(volatile uint32_t *)0x11300000u;
        text("MMIO status="); hex(registers[2]); text(" command="); hex(registers[3]);
        text(" phy_request="); hex(registers[4]); text("\n");
        unsigned count=registers[6];
        for (unsigned n=0;n<count && n<16;n++) {
            text("ULPI "); hex(n); text(" sample="); hex(registers[48+n]); text("\n");
        }
    }
    unsigned scratch=0;
    int rc=usbh_phy_write(0x16,0xa5);
    if (!rc) rc=usbh_phy_read(0x16,&scratch);
    text("PHY scratch="); hex(scratch); text(" rc="); hex((unsigned)rc); text("\n");
#ifdef USB_HID_PROBE
    struct usbh_hid host;
    for (;;) {
        rc=usbh_hid_init(&host);
        text("HID endpoints="); hex(host.count); text(" rc="); hex((unsigned)rc); text("\n");
        if(rc>0) break;
        usbh_delay(3000000);
    }
    for (;;) {
        struct usbh_input input;
        rc=usbh_hid_poll(&host,&input);
        if(rc>0) {
            text("HID protocol="); hex(input.protocol); text(" report:");
            for(unsigned n=0;n<8;n++) { text(" "); hex(input.report[n]); }
            text("\n");
        } else if(rc<0) { text("HID error="); hex((unsigned)rc); text("\n"); }
        usbh_delay(1000);
    }
#else
    for (;;) {
        unsigned speed=0;
        rc=usbh_root_reset(&speed);
        text("USB root: speed="); hex(speed); text(" rc="); hex((unsigned)rc); text("\n");
        if (!rc) {
            struct usbh_packet p;
            p.address=0; p.endpoint=0; p.speed=(uint8_t)speed; p.toggle=0; p.length=8;
            p.data[0]=0x80; p.data[1]=6; p.data[2]=0; p.data[3]=1;
            p.data[4]=0; p.data[5]=0; p.data[6]=8; p.data[7]=0;
            rc=usbh_transfer(USBH_SETUP,&p);
            text("SETUP rc="); hex((unsigned)rc); text("\n");
            if (!rc) {
                p.toggle=1;
                rc=usbh_transfer(USBH_IN,&p);
                text("IN rc="); hex((unsigned)rc); text(" length="); hex(p.length); text(" data:");
                if (!rc) for (unsigned n=0;n<p.length;n++) { text(" "); hex(p.data[n]); }
                text("\n");
                if (!rc) { p.length=0; p.toggle=1; rc=usbh_transfer(USBH_OUT,&p); }
                text("STATUS rc="); hex((unsigned)rc); text("\n");
            }
        }
        usbh_delay(3000000);
    }
#endif
}
