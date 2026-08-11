/* ASCII Mandelbrot set, Q16.16 fixed point, no libc. */

#include "fixed.h"
#include "sys.h"

#define W 78
#define H 30
#define MAXIT 48

static const char palette[] = " .:-=+*#%@";

static char line[W + 2];

void _start(void) {
    /* view: real in [-2.2, 0.8], imaginary in [-1.25, 1.25] */
    const int x0 = -2.2 * FONE, x1 = 0.8 * FONE;
    const int y0 = -1.25 * FONE, y1 = 1.25 * FONE;
    const int dx = (x1 - x0) / W;
    const int dy = (y1 - y0) / H;
    const int four = 4 * FONE;

    put_str("\nMandelbrot set (Q16.16 fixed point, rv32ima)\n\n");

    for (int py = 0; py < H; py++) {
        const int ci = y0 + dy * py;
        for (int px = 0; px < W; px++) {
            const int cr = x0 + dx * px;
            int zr = 0, zi = 0, it = 0;
            for (; it < MAXIT; it++) {
                const int zr2 = fmul(zr, zr);
                const int zi2 = fmul(zi, zi);
                if (zr2 + zi2 > four) break;
                zi = fmul(zr, zi) * 2 + ci;
                zr = zr2 - zi2 + cr;
            }
            line[px] = (it == MAXIT) ? '@' : palette[(it * 9) / MAXIT];
        }
        line[W] = '\n';
        sys_write(1, line, W + 1);
    }

    put_str("\n");
    sys_exit(0);
}
