/* Native tests for the freestanding HID stack, using a control-transfer model. */
#include <assert.h>
#include <stdio.h>
#include <string.h>
#include "usb_hid.h"
static unsigned now, request, requested, value, offset, data_toggle;
static unsigned mode, duplicate, protocol_requests, idle_requests, poll_toggle;
static unsigned char device[18]={18,1,0,2,0,0,0,8,0x34,0x12,0x78,0x56,0,1,0,0,0,1};
static unsigned char config[]={
    9,2,59,0,2,1,0,0x80,50,
    9,4,0,0,1,3,1,1,0, 9,0x21,0x11,1,0,1,0x22,63,0, 7,5,0x81,3,8,0,10,
    9,4,1,0,1,3,1,2,0, 9,0x21,0x11,1,0,1,0x22,63,0, 7,5,0x82,3,8,0,10
};
uint32_t usbh_now_us(void) { return now++; }
void usbh_delay(unsigned delay) { now+=delay; }
unsigned usbh_identity(void) { return 0x55484231; }
int usbh_root_reset(unsigned *speed) { *speed=USBH_FULL; return 0; }
int usbh_transfer(unsigned op, struct usbh_packet *p)
{
    if(p->endpoint) {
        if(p->endpoint==2) return -USBH_NAK;
        p->toggle=(uint8_t)(poll_toggle++&1); p->length=8;
        for(unsigned i=0;i<8;i++) p->data[i]=0;
        p->data[2]=4; /* key A */
        return 0;
    }
    if(op==USBH_SETUP) {
        assert(p->length==8 && p->toggle==0);
        request=p->data[1]; value=p->data[2]|((unsigned)p->data[3]<<8);
        requested=p->data[6]|((unsigned)p->data[7]<<8); offset=0; data_toggle=1;
        if(request==11) { assert(value==0); protocol_requests++; }
        if(request==10) idle_requests++;
        if(mode==3 && request==11) return -USBH_STALL;
        return 0;
    }
    if(op==USBH_OUT) { assert(p->toggle==1 && p->length==0); return 0; }
    assert(op==USBH_IN);
    if(requested==0) { p->length=0; p->toggle=1; return 0; }
    assert(request==6);
    unsigned char *source=value==0x100?device:config;
    unsigned available=value==0x100?sizeof(device):sizeof(config);
    unsigned size=requested-offset;
    if(size>8) size=8;
    if(size>available-offset) size=available-offset;
    p->length=(uint8_t)size;
    for(unsigned i=0;i<size;i++) p->data[i]=source[offset+i];
    if(duplicate) { duplicate=0; p->toggle=0; return 0; }
    p->toggle=(uint8_t)data_toggle; data_toggle^=1; offset+=size;
    return 0;
}
static void reset_model(void)
{
    now=0; mode=0; duplicate=0; protocol_requests=0; idle_requests=0; poll_toggle=0;
    config[2]=59; config[3]=0; config[9]=9; device[7]=8;
}
int main(void)
{
    struct usbh_hid host;
    struct usbh_input input;
    reset_model(); duplicate=1;
    assert(usbh_hid_init(&host)==2);
    assert(host.endpoint[0].protocol==1 && host.endpoint[1].protocol==2);
    assert(protocol_requests==2 && idle_requests==2);
    usbh_delay(20000); assert(usbh_hid_poll(&host,&input)==1);
    assert(input.protocol==1 && input.report[2]==4);
    usbh_delay(20000); assert(usbh_hid_poll(&host,&input)==0); /* unchanged keyboard */
    reset_model(); config[9]=0; assert(usbh_hid_init(&host)==-USBH_SIZE && host.count==0);
    reset_model(); config[2]=0; config[3]=3; assert(usbh_hid_init(&host)==-USBH_SIZE);
    reset_model(); device[7]=7; assert(usbh_hid_init(&host)==-USBH_SIZE);
    reset_model(); mode=3; assert(usbh_hid_init(&host)==-USBH_STALL && host.count==0);
    puts("PASS: HID composite enumeration, boot protocol, duplicate toggle, poll, malformed descriptors, STALL");
    return 0;
}
