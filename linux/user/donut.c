/* Spinning ASCII torus (the classic "donut"), Q16.16 fixed point, no libc.
 *
 * Same geometry as Andy Sloane's donut.c: a torus of radius R2 with tube
 * radius R1, rotated by A about x and B about z, projected onto an 80x22
 * character grid with a z-buffer and a 12-level luminance ramp. */

#include "fixed.h"
#include "sys.h"

#define W 80
#define H 22
#define FRAMES 24

#define R1 FONE          /* tube radius   = 1.0 */
#define R2 (2 * FONE)    /* torus radius  = 2.0 */
#define K2 (5 * FONE)    /* viewer distance */
#define K1 2457600       /* projection scale = 37.5 in Q16 */

#define THETA_STEP 6554  /* 0.10 rad */
#define PHI_STEP 1966    /* 0.03 rad */

static const char ramp[] = ".,-~:;=!*#$@";

static char screen[H * (W + 1)];
static int zbuf[H * W];

void _start(void) {
    int A = 0, B = 0;

    put_str("\x1b[2J"); /* clear once; frames redraw from the home position */

    for (int frame = 0; frame < FRAMES; frame++) {
        const int cosA = fcos(A), sinA = fsin(A);
        const int cosB = fcos(B), sinB = fsin(B);

        for (int i = 0; i < H; i++) {
            for (int j = 0; j < W; j++) screen[i * (W + 1) + j] = ' ';
            screen[i * (W + 1) + W] = '\n';
        }
        for (int i = 0; i < H * W; i++) zbuf[i] = 0;

        for (int theta = 0; theta < F_2PI; theta += THETA_STEP) {
            const int ct = fcos(theta), st = fsin(theta);
            /* distance from the axis of revolution to this ring point */
            const int h = fmul(R1, ct) + R2;

            for (int phi = 0; phi < F_2PI; phi += PHI_STEP) {
                const int cp = fcos(phi), sp = fsin(phi);

                /* 1 / (z + K2) */
                const int denom = fmul(fmul(sp, h), sinA) + fmul(fmul(R1, st), cosA) + K2;
                if (denom <= 0) continue;
                const int D = frecip(denom);

                const int t = fmul(fmul(sp, h), cosA) - fmul(fmul(R1, st), sinA);

                const int xq = fmul(fmul(K1, D), fmul(cp, fmul(h, cosB)) - fmul(t, sinB));
                const int yq = fmul(fmul(K1 / 2, D), fmul(cp, fmul(h, sinB)) + fmul(t, cosB));
                const int x = W / 2 + (xq >> FBITS);
                const int y = H / 2 - (yq >> FBITS);

                if (x < 0 || x >= W || y < 0 || y >= H) continue;

                const int o = y * W + x;
                if (D <= zbuf[o]) continue;

                /* surface normal dotted with the light direction (0, 1, -1) */
                int lum = fmul(fmul(R1, st), fmul(sinA, cosB)) - fmul(fmul(sp, ct), fmul(cosA, cosB)) - fmul(fmul(sp, ct), sinA) - fmul(fmul(R1, st), cosA) - fmul(cp, fmul(ct, sinB));
                int n = fmul(8 * FONE, lum) >> FBITS;
                if (n < 0) n = 0;
                if (n > 11) n = 11;

                zbuf[o] = D;
                screen[y * (W + 1) + x] = ramp[n];
            }
        }

        put_str("\x1b[H");
        sys_write(1, screen, sizeof(screen));

        A += 5243; /* 0.08 rad */
        B += 1966; /* 0.03 rad */
    }

    put_str("\ndonut: ");
    put_uint(FRAMES);
    put_str(" frames rendered\n");
    sys_exit(0);
}
