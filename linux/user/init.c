/* PID 1 for the rv32 NOMMU demo: a minimal shell.
 *
 * No libc. Commands are dispatched by spawning separate FDPIC binaries with
 * clone(CLONE_VM|CLONE_VFORK)+execve, which exercises the kernel's process
 * and exec paths rather than just this one address space. */

#include "sys.h"

static char buf[128];

static char *const donut_argv[] = {"/bin/donut", 0};
static char *const mandel_argv[] = {"/bin/mandelbrot", 0};
static char *const empty_envp[] = {0};

static int eq(const char *a, const char *b) {
    while (*a && *b && *a == *b) {
        a++;
        b++;
    }
    return *a == 0 && *b == 0;
}

void _start(void) {
    put_str("\n=== rv32ima_veryl: userspace is alive (FDPIC, NOMMU) ===\n"
            "commands: donut  mandel  help  poweroff  reboot\n");

    for (;;) {
        put_str("veryl$ ");
        ssize_t_ n = sys_read(0, buf, sizeof(buf) - 1);
        if (n <= 0) continue;
        while (n > 0 && (buf[n - 1] == '\n' || buf[n - 1] == '\r')) n--;
        buf[n] = 0;
        if (n == 0) continue;

        if (eq(buf, "donut")) {
            spawn(donut_argv[0], donut_argv, empty_envp);
        } else if (eq(buf, "mandel") || eq(buf, "mandelbrot")) {
            spawn(mandel_argv[0], mandel_argv, empty_envp);
        } else if (eq(buf, "help")) {
            put_str("donut     spinning torus, fixed point\n"
                    "mandel    Mandelbrot set, fixed point\n"
                    "poweroff  shut the machine down\n"
                    "reboot    restart the machine\n");
        } else if (eq(buf, "poweroff") || eq(buf, "p")) {
            sys_reboot(RB_POWER_OFF);
        } else if (eq(buf, "reboot") || eq(buf, "r")) {
            sys_reboot(RB_AUTOBOOT);
        } else {
            put_str("unknown command: ");
            put_str(buf);
            put_str("\n");
        }
    }
}
