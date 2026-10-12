/* Small interactive RGB565 framebuffer application for the Tang LCD build.
 * All drawing goes through /dev/fb0. USB input is enabled on the standalone build. */
#include "sys.h"
#include <stdint.h>
#ifdef WITH_USB
#include "usb_hid.h"
static struct usbh_hid usb;
static int pointer_x = 400, pointer_y = 240;
uint32_t usbh_now_us(void) { return *(volatile uint32_t *)0x1100bff8u; }
#endif

enum { SYS_ioctl = 29, SYS_openat = 56, SYS_close = 57 };
enum { FBIOGET_VSCREENINFO = 0x4600, FBIOGET_FSCREENINFO = 0x4602 };
static unsigned short row[800];
static unsigned info[64], fixed[64];
static int position_x = 360, position_y = 220;
static unsigned selection;
static const unsigned short colors[3] = {0xf800, 0x07e0, 0x001f};
static int clip_left, clip_right;

static int open_fb(void) {
    return (int)sys4(SYS_openat, -100, (long)"/dev/fb0", 2, 0);
}

static void fail(const char *message) {
    put_str(message);
    sys_exit(1);
}

static void span(int left, int width, unsigned short color) {
    int right = left + width;
    if (left < clip_left) left = clip_left;
    if (right > clip_right) right = clip_right;
    for (int x = left; x < right; ++x) row[x] = color;
}

/* RV32 __NR_llseek=62: fd, high, low, result pointer, whence. */
static long seek(int fd, unsigned offset) {
    uint64_t result;
    register long a7 __asm__("a7") = 62;
    register long a0 __asm__("a0") = fd;
    register long a1 __asm__("a1") = 0;
    register long a2 __asm__("a2") = offset;
    register long a3 __asm__("a3") = (long)&result;
    register long a4 __asm__("a4") = 0;
    __asm__ volatile("ecall" : "+r"(a0) : "r"(a7), "r"(a1), "r"(a2), "r"(a3), "r"(a4) : "memory");
    return a0;
}

static void draw(int left, int top, int right, int bottom) {
    if (left < 0) left = 0;
    if (top < 0) top = 0;
    if (right > 800) right = 800;
    if (bottom > 480) bottom = 480;
    if (left >= right || top >= bottom) return;
    clip_left = left; clip_right = right;
    int fd = open_fb();
    if (fd < 0) fail("fbui: cannot open framebuffer\n");
    for (int y = top; y < bottom; ++y) {
        /* Decide intersections once per row, not once per pixel. The soft
         * CPU shares DDR with scanout and benefits from short fill loops. */
        span(0, 800, y < 48 ? 0x2128 : 0x1083);
        if (y >= 72 && y < 456) span(176, 600, 0x3186);
        for (unsigned button = 0; button < 3; ++button) {
            int top = 88 + (int)button * 112;
            if (y >= top && y < top + 88)
                span(24, 128, selection == button ? 0xffff : 0x630c);
            if (y >= top + 6 && y < top + 82) span(30, 116, colors[button]);
        }
        if (y >= position_y - 3 && y < position_y + 51) span(position_x - 3, 54, 0xffff);
        if (y >= position_y && y < position_y + 48) span(position_x, 48, colors[selection]);
#ifdef WITH_USB
        if (y >= pointer_y && y < pointer_y + 10) {
            span(pointer_x, (y - pointer_y) / 2 + 1, 0xffff);
            span(pointer_x, 1, 0);
        }
#endif
        if (seek(fd, (unsigned)(y * 1600 + left * 2)) < 0) fail("fbui: framebuffer seek failed\n");
        unsigned offset = (unsigned)left * 2, end = (unsigned)right * 2;
        while (offset < end) {
            long n = sys_write(fd, (char *)row + offset, end - offset);
            if (n == -4) continue;
            if (n <= 0) fail("fbui: framebuffer write failed\n");
            offset += (unsigned)n;
        }
    }
    sys1(SYS_close, fd);
}

void _start(void) {
    int fd = open_fb();
    if (fd < 0) fail("fbui: framebuffer unavailable\n");
    if (sys3(SYS_ioctl, fd, FBIOGET_VSCREENINFO, (long)info) < 0 ||
        sys3(SYS_ioctl, fd, FBIOGET_FSCREENINFO, (long)fixed) < 0)
        fail("fbui: framebuffer query failed\n");
    /* Linux v6.12 RV32 fb_var_screeninfo/fb_fix_screeninfo ABI word offsets.
     * The 256-byte buffers cover both complete structures, including padding. */
    if (info[0] != 800 || info[1] != 480 || info[2] != 800 || info[3] != 480 ||
        info[4] || info[5] || info[6] != 16 || info[7] ||
        info[8] != 11 || info[9] != 5 || info[10] ||
        info[11] != 5 || info[12] != 6 || info[13] ||
        info[14] || info[15] != 5 || info[16] || info[18] ||
        fixed[5] < 768000 || fixed[6] || fixed[8] != 2 || fixed[11] != 1600)
        fail("fbui: expected 800x480 RGB565 packed framebuffer\n");
    sys1(SYS_close, fd);
    put_str("fbui: drawing; commands w/a/s/d, r/g/b, q, followed by Enter\n");
#ifdef WITH_USB
    int devices = usbh_hid_init(&usb);
    put_str("fbui: USB HID endpoints "); put_uint(devices > 0 ? (unsigned)devices : 0); put_str("\n");
    int console = (int)sys4(SYS_openat, -100, (long)"/dev/console", 0x800, 0);
    if (console < 0) fail("fbui: cannot open console\n");
#endif
    draw(0, 0, 800, 480);
    put_str("fbui: ready\n");
    for (;;) {
        char command[32];
        int old_x = position_x, old_y = position_y;
        unsigned old_selection = selection;
#ifdef WITH_USB
        int old_pointer_x = pointer_x, old_pointer_y = pointer_y;
        command[0] = 0;
        struct usbh_input input;
        int event = usbh_hid_poll(&usb, &input);
        if (event > 0 && input.protocol == 1) {
            /* HID boot keyboard usages: arrows/WASD, RGB, Escape. */
            switch (input.report[2]) {
            case 0x1a: case 0x52: command[0] = 'w'; break;
            case 0x04: case 0x50: command[0] = 'a'; break;
            case 0x16: case 0x51: command[0] = 's'; break;
            case 0x07: case 0x4f: command[0] = 'd'; break;
            case 0x15: command[0] = 'r'; break;
            case 0x0a: command[0] = 'g'; break;
            case 0x05: command[0] = 'b'; break;
            case 0x29: command[0] = 'q'; break;
            default: break;
            }
        } else if (event > 0 && input.protocol == 2) {
            pointer_x += (int8_t)input.report[1]; pointer_y += (int8_t)input.report[2];
            if (pointer_x < 0) pointer_x = 0;
            if (pointer_x > 794) pointer_x = 794;
            if (pointer_y < 0) pointer_y = 0;
            if (pointer_y > 470) pointer_y = 470;
            if (input.report[0] & 1) {
                for (unsigned button = 0; button < 3; ++button)
                    if (pointer_x >= 24 && pointer_x < 152 && pointer_y >= 88 + (int)button * 112 &&
                        pointer_y < 176 + (int)button * 112) selection = button;
                if (pointer_x >= 176) {
                    position_x = pointer_x - 24; position_y = pointer_y - 24;
                    if (position_x < 184) position_x = 184;
                    if (position_x > 720) position_x = 720;
                    if (position_y < 80) position_y = 80;
                    if (position_y > 400) position_y = 400;
                }
            }
        }
        if (!command[0]) {
            long n = sys_read(console, command, sizeof(command));
            if (n <= 0) command[0] = 0;
        }
#else
        long n = sys_read(0, command, sizeof(command));
        if (n == -4) continue;
        if (n <= 0) fail("fbui: input ended\n");
#endif
        switch (command[0]) {
        case 'q': put_str("fbui: done\n"); sys_exit(0);
        case 'w': if (position_y >= 96) position_y -= 16; break;
        case 's': if (position_y <= 384) position_y += 16; break;
        case 'a': if (position_x >= 200) position_x -= 16; break;
        case 'd': if (position_x <= 704) position_x += 16; break;
        case 'r': selection = 0; break;
        case 'g': selection = 1; break;
        case 'b': selection = 2; break;
        default: break;
        }
        if (old_x != position_x || old_y != position_y || old_selection != selection) {
            draw(old_x - 3, old_y - 3, old_x + 51, old_y + 51);
            draw(position_x - 3, position_y - 3, position_x + 51, position_y + 51);
            if (old_selection != selection) draw(24, 88, 152, 400);
            put_str("fbui: updated\n");
        }
#ifdef WITH_USB
        if (old_pointer_x != pointer_x || old_pointer_y != pointer_y) {
            draw(old_pointer_x, old_pointer_y, old_pointer_x + 6, old_pointer_y + 10);
            draw(pointer_x, pointer_y, pointer_x + 6, pointer_y + 10);
        }
        /* SOF is maintained by hardware while the process sleeps or draws. */
        long delay[2] = {0, 1000000};
        sys3(SYS_nanosleep, (long)delay, 0, 0);
#endif
    }
}
