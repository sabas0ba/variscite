/* Boot-protocol HID enumeration, including full-speed hubs and LS preambles.
 * This small exclusive host stack uses no kernel HCD, allocation or libraries. */
#include "usb_hid.h"

static unsigned le16(const uint8_t *p) { return p[0]|((unsigned)p[1]<<8); }

static int retry(unsigned operation, struct usbh_packet *p, uint32_t deadline)
{
    int rc;
    unsigned failures=0;
    do {
        rc=usbh_transfer(operation,p);
        if (!rc || rc==-USBH_STALL || rc==-USBH_SIZE || rc==-USBH_PID) return rc;
        if (rc!=-USBH_NAK && ++failures==3) return rc;
        usbh_delay(1000);
    } while ((int32_t)(usbh_now_us()-deadline)<0);
    return rc;
}

static int control(unsigned address, unsigned speed, unsigned max_packet,
    unsigned type, unsigned request, unsigned value, unsigned index,
    uint8_t *data, unsigned length)
{
    struct usbh_packet p;
    p.address=(uint8_t)address; p.endpoint=0; p.speed=(uint8_t)speed;
    p.toggle=0; p.length=8;
    p.data[0]=(uint8_t)type; p.data[1]=(uint8_t)request;
    p.data[2]=(uint8_t)value; p.data[3]=(uint8_t)(value>>8);
    p.data[4]=(uint8_t)index; p.data[5]=(uint8_t)(index>>8);
    p.data[6]=(uint8_t)length; p.data[7]=(uint8_t)(length>>8);
    uint32_t deadline=usbh_now_us()+500000;
    int rc=retry(USBH_SETUP,&p,deadline);
    if (rc) return rc;
    unsigned transferred=0, toggle=1;
    while (transferred<length) {
        p.toggle=(uint8_t)toggle;
        if (type&0x80) {
            p.length=0;
            rc=retry(USBH_IN,&p,deadline);
            if (rc) return rc;
            if (p.toggle!=toggle) {
                if ((int32_t)(usbh_now_us()-deadline)>=0) return -USBH_TIMEOUT;
                continue; /* ACKed duplicate; keep the expected toggle. */
            }
            if (p.length>max_packet || p.length>length-transferred) return -USBH_SIZE;
            for (unsigned n=0;n<p.length;n++) data[transferred+n]=p.data[n];
        } else {
            unsigned count=length-transferred;
            if(count>max_packet) count=max_packet;
            p.length=(uint8_t)count;
            for(unsigned n=0;n<count;n++) p.data[n]=data[transferred+n];
            rc=retry(USBH_OUT,&p,deadline);
            if(rc) return rc;
        }
        transferred+=p.length; toggle^=1;
        if(p.length<max_packet) break;
    }
    p.toggle=1; p.length=0;
    rc=retry((type&0x80)?USBH_OUT:USBH_IN,&p,deadline);
    if(rc) return rc;
    if(!(type&0x80) && (p.length || p.toggle!=1)) return -USBH_PID;
    return (int)transferred;
}

static int port_status(unsigned address, unsigned speed, unsigned max_packet, unsigned port, uint8_t *status)
{
    int rc=control(address,speed,max_packet,0xa3,0,0,port,status,4);
    return rc==4?0:(rc<0?rc:-USBH_SIZE);
}

static int enumerate(struct usbh_hid *host, unsigned speed, unsigned depth)
{
    uint8_t descriptor[512];
    int rc=control(0,speed,8,0x80,6,0x0100,0,descriptor,8);
    if(rc!=8 || descriptor[0]!=18 || descriptor[1]!=1) return rc<0?rc:-USBH_SIZE;
    unsigned max_packet=descriptor[7];
    if((max_packet!=8 && max_packet!=16 && max_packet!=32 && max_packet!=64) ||
        (speed!=USBH_FULL && max_packet!=8) || host->next_address>127) return -USBH_SIZE;
    unsigned address=host->next_address++;
    rc=control(0,speed,max_packet,0,5,address,0,descriptor,0);
    if(rc<0) return rc;
    usbh_delay(10000);
    rc=control(address,speed,max_packet,0x80,6,0x0100,0,descriptor,18);
    if(rc!=18) return rc<0?rc:-USBH_SIZE;
    unsigned hub=descriptor[4]==9;
    rc=control(address,speed,max_packet,0x80,6,0x0200,0,descriptor,9);
    if(rc!=9 || descriptor[0]!=9 || descriptor[1]!=2) return rc<0?rc:-USBH_SIZE;
    unsigned total=le16(descriptor+2), configuration=descriptor[5];
    if(total<9 || total>sizeof(descriptor) || !configuration) return -USBH_SIZE;
    rc=control(address,speed,max_packet,0x80,6,0x0200,0,descriptor,total);
    if(rc!=(int)total) return rc<0?rc:-USBH_SIZE;
    rc=control(address,speed,max_packet,0,9,configuration,0,descriptor,0);
    if(rc<0) return rc;
    unsigned protocol=0, interface=0;
    for(unsigned offset=0;offset<total;) {
        unsigned size=descriptor[offset];
        if(size<2 || size>total-offset) return -USBH_SIZE;
        unsigned type=descriptor[offset+1];
        if(type==4) {
            if(size<9) return -USBH_SIZE;
            interface=descriptor[offset+2];
            protocol=0;
            if(descriptor[offset+3]==0 && descriptor[offset+5]==3 && descriptor[offset+6]==1 &&
                (descriptor[offset+7]==1 || descriptor[offset+7]==2)) protocol=descriptor[offset+7];
            if(descriptor[offset+5]==9) hub=1;
        } else if(type==5 && protocol) {
            if(size<7) return -USBH_SIZE;
            unsigned endpoint=descriptor[offset+2], maximum=le16(descriptor+offset+4);
            unsigned interval=descriptor[offset+6];
            if((endpoint&0x80) && (descriptor[offset+3]&3)==3 && (endpoint&15) &&
                !(endpoint&0x70) && maximum>=(protocol==1?8u:3u) &&
                maximum<=(speed==USBH_FULL?64u:8u) && interval) {
                if(host->count==USBH_HID_MAX) return -USBH_SIZE;
                // SET_PROTOCOL(boot) is mandatory for a boot-subclass HID.
                rc=control(address,speed,max_packet,0x21,11,0,interface,descriptor,0);
                if(rc<0) return rc;
                // SET_IDLE(0): report on change. Some mice stall this request.
                rc=control(address,speed,max_packet,0x21,10,0,interface,descriptor,0);
                if(rc<0 && rc!=-USBH_STALL) return rc;
                struct usbh_hid_endpoint *ep=&host->endpoint[host->count++];
                ep->address=(uint8_t)address; ep->endpoint=(uint8_t)(endpoint&15);
                ep->speed=(uint8_t)speed; ep->protocol=(uint8_t)protocol;
                ep->toggle=0; ep->interval=(uint8_t)interval; ep->last_poll=0;
                for(unsigned n=0;n<8;n++) ep->previous[n]=0;
                protocol=0;
            }
        }
        offset+=size;
    }
    if(hub) {
        if(depth>=3 || speed!=USBH_FULL) return -USBH_SIZE;
        rc=control(address,speed,max_packet,0xa0,6,0x2900,0,descriptor,9);
        if(rc<7 || descriptor[1]!=0x29 || descriptor[2]==0 || descriptor[2]>15) return rc<0?rc:-USBH_SIZE;
        unsigned ports=descriptor[2], power_delay=(unsigned)descriptor[5]*2000+20000;
        for(unsigned port=1;port<=ports;port++) {
            rc=control(address,speed,max_packet,0x23,3,8,port,descriptor,0);
            if(rc<0) return rc;
        }
        usbh_delay(power_delay);
        for(unsigned port=1;port<=ports;port++) {
            rc=port_status(address,speed,max_packet,port,descriptor);
            if(rc<0) return rc;
            if(!(descriptor[0]&1)) continue;
            usbh_delay(100000);
            rc=control(address,speed,max_packet,0x23,3,4,port,descriptor,0);
            if(rc<0) return rc;
            unsigned attempts;
            for(attempts=0;attempts<20;attempts++) {
                usbh_delay(10000);
                rc=port_status(address,speed,max_packet,port,descriptor);
                if(rc<0) return rc;
                if(!(descriptor[0]&0x10) && (descriptor[0]&2)) break;
            }
            if(attempts==20) return -USBH_TIMEOUT;
            unsigned child_speed=(descriptor[1]&2)?USBH_LOW_HUB:USBH_FULL;
            unsigned changes=le16(descriptor+2);
            for(unsigned bit=0;bit<5;bit++) if(changes&(1u<<bit)) {
                rc=control(address,speed,max_packet,0x23,1,16+bit,port,descriptor,0);
                if(rc<0) return rc;
            }
            usbh_delay(10000);
            rc=enumerate(host,child_speed,depth+1);
            if(rc<0) return rc;
        }
    }
    return 0;
}

int usbh_hid_init(struct usbh_hid *host)
{
    host->count=0; host->next_address=1; host->root_speed=0;
    host->init_attempts=0; host->last_init_error=0;
    if(usbh_identity()!=0x55484231) return host->last_init_error=-USBH_LINK;
    for(unsigned attempt=0;attempt<3;attempt++) {
        host->count=0; host->next_address=1; host->root_speed=0;
        host->init_attempts=attempt+1;
        int rc=usbh_root_reset(&host->root_speed);
        if(!rc) rc=enumerate(host,host->root_speed,0);
        if(!rc) return (int)host->count;
        host->count=0; host->last_init_error=rc;
        if(attempt==2 || (rc!=-USBH_LINK && rc!=-USBH_TIMEOUT &&
                         rc!=-USBH_CRC && rc!=-USBH_NAK)) return rc;
        /* A transient startup failure requires a fresh bus reset/address map.
         * Descriptor/protocol errors stay fatal; absent devices stay bounded. */
        usbh_delay(100000);
    }
    return host->last_init_error;
}

int usbh_hid_poll(struct usbh_hid *host, struct usbh_input *input)
{
    uint32_t now=usbh_now_us();
    for(unsigned n=0;n<host->count;n++) {
        struct usbh_hid_endpoint *ep=&host->endpoint[n];
        if((uint32_t)(now-ep->last_poll)<(unsigned)ep->interval*1000) continue;
        ep->last_poll=now;
        struct usbh_packet p;
        p.address=ep->address; p.endpoint=ep->endpoint; p.speed=ep->speed; p.toggle=ep->toggle; p.length=0;
        int rc=usbh_transfer(USBH_IN,&p);
        if(rc==-USBH_NAK) continue;
        if(rc<0) return rc;
        if(p.toggle!=ep->toggle) continue;
        ep->toggle^=1;
        if(p.length<(ep->protocol==1?8u:3u)) return -USBH_SIZE;
        input->protocol=ep->protocol;
        for(unsigned i=0;i<8;i++) input->report[i]=i<p.length?p.data[i]:0;
        // Relative mouse motion must not be suppressed when reports repeat.
        unsigned changed=ep->protocol==2;
        for(unsigned i=0;i<8;i++) {
            if(ep->previous[i]!=input->report[i]) changed=1;
            ep->previous[i]=input->report[i];
        }
        if(changed) return 1;
    }
    return 0;
}
