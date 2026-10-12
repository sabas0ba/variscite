#ifndef VARISCITE_USB_HID_H
#define VARISCITE_USB_HID_H
#include "usb_host.h"
enum { USBH_HID_MAX=8 };
struct usbh_hid_endpoint {
    uint8_t address, endpoint, speed, protocol, toggle, interval;
    uint8_t previous[8];
    uint32_t last_poll;
};
struct usbh_hid {
    struct usbh_hid_endpoint endpoint[USBH_HID_MAX];
    unsigned count, next_address, root_speed;
};
struct usbh_input {
    unsigned protocol;
    uint8_t report[8];
};
int usbh_hid_init(struct usbh_hid *host);
/* 1: report, 0: no change/NAK/not due, negative: transport error. */
int usbh_hid_poll(struct usbh_hid *host, struct usbh_input *input);
#endif
