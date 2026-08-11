/* Q16.16 fixed point with a fixed-point sine.
 *
 * The core has no FPU and the userland has no libm, so everything is integer.
 * The 32x32->64 multiply is written as explicit mul/mulh so no libgcc helper
 * is needed, and every division is kept inside 32 bits for the same reason. */

#ifndef RV32IMA_VERYL_FIXED_H
#define RV32IMA_VERYL_FIXED_H

#define FBITS 16
#define FONE (1 << FBITS)

#define F_PI 205887    /* pi      * 65536 */
#define F_2PI 411775   /* 2*pi    * 65536 */
#define F_PI_2 102944  /* pi/2    * 65536 */

static inline int fmul(int a, int b) {
    int lo, hi;
    __asm__("mul %0, %1, %2" : "=r"(lo) : "r"(a), "r"(b));
    __asm__("mulh %0, %1, %2" : "=r"(hi) : "r"(a), "r"(b));
    return (int)(((unsigned int)lo >> FBITS) | ((unsigned int)hi << (32 - FBITS)));
}

/* 1/x in Q16 for x in roughly [0.5, 512]. Both operands are scaled down so
 * the division stays a single 32-bit divide. */
static inline int frecip(int x) {
    int d = x >> 8;
    if (d == 0) d = 1;
    return (FONE << 8) / d;
}

/* sin(x), x in Q16 radians. Range reduction to [0, pi/2] plus the 5th order
 * Taylor series, which is accurate to about 1e-5 over that interval. */
static inline int fsin(int x) {
    int sign = 0;
    int x2, x3, x5, r;

    x %= F_2PI;
    if (x < 0) x += F_2PI;
    if (x >= F_PI) {
        x -= F_PI;
        sign = 1;
    }
    if (x > F_PI_2) x = F_PI - x;

    x2 = fmul(x, x);
    x3 = fmul(x2, x);
    x5 = fmul(x3, x2);
    r = x - x3 / 6 + x5 / 120;
    return sign ? -r : r;
}

static inline int fcos(int x) { return fsin(x + F_PI_2); }

#endif /* RV32IMA_VERYL_FIXED_H */
