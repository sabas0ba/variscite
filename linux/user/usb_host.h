#ifndef VARISCITE_USB_HOST_H
#define VARISCITE_USB_HOST_H
#include <stdint.h>

enum { USBH_IN, USBH_OUT, USBH_SETUP, USBH_SOF, USBH_PHY_READ, USBH_PHY_WRITE };
enum { USBH_OK=1, USBH_NAK, USBH_STALL, USBH_CRC, USBH_TIMEOUT, USBH_PID, USBH_SIZE, USBH_LINK };
enum { USBH_FULL=1, USBH_LOW=2, USBH_LOW_HUB=3 };
struct usbh_packet {
    uint8_t address, endpoint, speed, toggle, length;
    uint8_t data[64];
};
/* Platform supplies a wrapping monotonic microsecond counter. */
uint32_t usbh_now_us(void);
void usbh_delay(unsigned microseconds);
unsigned usbh_identity(void);
void usbh_sof(unsigned enable, unsigned root_speed);
int usbh_phy_read(unsigned address, unsigned *value);
int usbh_phy_write(unsigned address, unsigned value);
int usbh_transfer(unsigned operation, struct usbh_packet *packet);
int usbh_root_reset(unsigned *speed);
#endif
