/* Small interactive RGB565 framebuffer application for the Tang LCD build.
 * All drawing goes through /dev/fb0; UART supplies line-oriented commands. */
#include "sys.h"

enum { SYS_ioctl = 29, SYS_openat = 56, SYS_close = 57 };
enum { FBIOGET_VSCREENINFO = 0x4600, FBIOGET_FSCREENINFO = 0x4602 };
static unsigned short row[800];
static unsigned info[64], fixed[64];
static int position_x = 360, position_y = 220;
static unsigned selection;
static const unsigned short colors[3] = {0xf800, 0x07e0, 0x001f};

static int open_fb(void) {
    return (int)sys4(SYS_openat, -100, (long)"/dev/fb0", 2, 0);
}

static void fail(const char *message) {
    put_str(message);
    sys_exit(1);
}

static void span(int left, int width, unsigned short color) {
    for (int x = left; x < left + width; ++x) row[x] = color;
}

static void draw(void) {
    /* Reopening starts at offset zero without depending on RV32 llseek ABI. */
    int fd = open_fb();
    if (fd < 0) fail("fbui: cannot open framebuffer\n");
    for (int y = 0; y < 480; ++y) {
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
        unsigned offset = 0;
        while (offset < sizeof(row)) {
            long n = sys_write(fd, (char *)row + offset, sizeof(row) - offset);
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
    draw();
    put_str("fbui: ready\n");
    for (;;) {
        char command[32];
        long n = sys_read(0, command, sizeof(command));
        if (n == -4) continue;
        if (n <= 0) fail("fbui: input ended\n");
        switch (command[0]) {
        case 'q': put_str("fbui: done\n"); sys_exit(0);
        case 'w': if (position_y >= 96) position_y -= 16; break;
        case 's': if (position_y <= 384) position_y += 16; break;
        case 'a': if (position_x >= 200) position_x -= 16; break;
        case 'd': if (position_x <= 704) position_x += 16; break;
        case 'r': selection = 0; break;
        case 'g': selection = 1; break;
        case 'b': selection = 2; break;
        default: put_str("fbui: use w/a/s/d, r/g/b or q\n"); continue;
        }
        draw();
        put_str("fbui: updated\n");
    }
}
