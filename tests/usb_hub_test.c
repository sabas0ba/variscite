/* Full-speed hub with one low-speed keyboard and one full-speed mouse. */
#include <assert.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include "usb_hid.h"
static uint32_t clock_us;
static unsigned active, address_to_device[128], powered, reset_ports, stuck_reset;
static unsigned type, request, value, index_, length, offset, toggle;
static unsigned packet_toggle[3], preamble_packets, status_packets;
static uint8_t reply[64];
static const uint8_t hub_config[]={9,2,25,0,1,1,0,0x80,0,9,4,0,0,1,9,0,0,0,7,5,0x81,3,1,0,12};
static const uint8_t hid_config[]={9,2,25,0,1,1,0,0x80,50,9,4,0,0,1,3,1,1,0,7,5,0x81,3,8,0,10};
uint32_t usbh_now_us(void) { return clock_us++; }
void usbh_delay(unsigned us) { clock_us+=us; }
unsigned usbh_identity(void) { return 0x55484231; }
int usbh_root_reset(unsigned *speed) { *speed=USBH_FULL; active=0; return 0; }
int usbh_transfer(unsigned operation,struct usbh_packet *p)
{
    unsigned device=p->address?address_to_device[p->address]:active;
    assert(device<3);
    assert(p->speed==(device==1?USBH_LOW_HUB:USBH_FULL));
    if(p->speed==USBH_LOW_HUB) preamble_packets++;
    if(p->endpoint) {
        assert(operation==USBH_IN && device && p->endpoint==1);
        if(device==1) return -USBH_NAK;
        memset(p->data,0,8); p->data[1]=5; p->data[2]=0xfe;
        p->length=3; p->toggle=(uint8_t)(packet_toggle[device]++&1);
        return 0;
    }
    if(operation==USBH_SETUP) {
        assert(p->length==8 && p->toggle==0);
        type=p->data[0]; request=p->data[1]; value=p->data[2]|((unsigned)p->data[3]<<8);
        index_=p->data[4]|((unsigned)p->data[5]<<8); length=p->data[6]|((unsigned)p->data[7]<<8);
        offset=0; toggle=1; memset(reply,0,sizeof(reply));
        if(request==5) address_to_device[value]=device;
        else if(type==0xa0 && request==6) {
            assert(device==0 && value==0x2900);
            reply[0]=9; reply[1]=0x29; reply[2]=2; reply[5]=1;
        } else if(type==0x80 && request==6 && value==0x100) {
            reply[0]=18; reply[1]=1; reply[3]=2; reply[4]=device?0:9; reply[7]=8; reply[17]=1;
        } else if(type==0x80 && request==6 && value==0x200) {
            memcpy(reply,device?hid_config:hub_config,25);
            if(device==2) reply[16]=2;
        } else if(type==0xa3 && request==0) {
            assert(!device && index_>=1 && index_<=2);
            status_packets++;
            reply[0]=(uint8_t)(1+((reset_ports&(1u<<index_)) && !stuck_reset?2:0));
            reply[1]=(uint8_t)(index_==1?2:0);
            reply[2]=(uint8_t)((reset_ports&(1u<<index_))?16:1);
        } else if(type==0x23 && request==3) {
            assert(!device && index_>=1 && index_<=2);
            if(value==8) powered|=1u<<index_;
            else { assert(value==4 && (powered&(1u<<index_))); reset_ports|=1u<<index_; active=index_; }
        } else if(type==0x23 && request==1) assert(value>=16 && value<=20);
        else if(request==11 || request==10) assert(device && type==0x21 && value==0);
        else assert(request==9 && value==1);
        return 0;
    }
    if(!length) { assert(operation==USBH_IN); p->length=0; p->toggle=1; return 0; }
    if(operation==USBH_OUT) { assert(p->length==0 && p->toggle==1); return 0; }
    assert(operation==USBH_IN);
    unsigned n=length-offset;
    if(n>8) n=8;
    memcpy(p->data,reply+offset,n); offset+=n; p->length=(uint8_t)n;
    p->toggle=(uint8_t)toggle; toggle^=1;
    return 0;
}
static void reset(void)
{
    clock_us=active=powered=reset_ports=stuck_reset=0;
    preamble_packets=status_packets=0;
    memset(address_to_device,0,sizeof(address_to_device));
    memset(packet_toggle,0,sizeof(packet_toggle));
}
int main(void)
{
    struct usbh_hid host;
    struct usbh_input input;
    reset();
    assert(usbh_hid_init(&host)==2 && host.count==2 && host.next_address==4);
    assert(powered==6 && reset_ports==6 && status_packets>=4 && preamble_packets>0);
    assert(host.endpoint[0].address==2 && host.endpoint[0].speed==USBH_LOW_HUB && host.endpoint[0].protocol==1);
    assert(host.endpoint[1].address==3 && host.endpoint[1].speed==USBH_FULL && host.endpoint[1].protocol==2);
    usbh_delay(20000); assert(usbh_hid_poll(&host,&input)==1 && input.protocol==2 && input.report[1]==5);
    usbh_delay(20000); assert(usbh_hid_poll(&host,&input)==1); /* repeated relative motion */
    reset(); stuck_reset=1;
    assert(usbh_hid_init(&host)==-USBH_TIMEOUT && host.count==0);
    puts("PASS: hub power/reset/status, device addresses, LS preambles, FS mouse, repeated motion, reset timeout");
    return 0;
}
