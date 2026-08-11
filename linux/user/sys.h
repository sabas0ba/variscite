/* Minimal freestanding syscall layer for the rv32 NOMMU demo userland.
 *
 * There is no libc: every binary is linked with linux/init.ld, contains no
 * relocations, and talks to the kernel through raw ecall. Only what the demo
 * programs need is declared here. */

#ifndef RV32IMA_VERYL_SYS_H
#define RV32IMA_VERYL_SYS_H

typedef unsigned int size_t_;
typedef int ssize_t_;

#define SYS_read 63
#define SYS_write 64
#define SYS_exit 93
#define SYS_wait4 260
#define SYS_execve 221
#define SYS_clone 220
#define SYS_reboot 142
#define SYS_nanosleep 101

#define REBOOT_MAGIC1 0xfee1dead
#define REBOOT_MAGIC2 0x28121969
#define RB_POWER_OFF 0x4321fedc
#define RB_AUTOBOOT 0x01234567

#define CLONE_VM 0x00000100
#define CLONE_VFORK 0x00004000
#define SIGCHLD 17

static inline long sys1(long n, long a) {
    register long a7 __asm__("a7") = n;
    register long a0 __asm__("a0") = a;
    __asm__ volatile("ecall" : "+r"(a0) : "r"(a7) : "memory");
    return a0;
}

static inline long sys3(long n, long a, long b, long c) {
    register long a7 __asm__("a7") = n;
    register long a0 __asm__("a0") = a;
    register long a1 __asm__("a1") = b;
    register long a2 __asm__("a2") = c;
    __asm__ volatile("ecall" : "+r"(a0) : "r"(a7), "r"(a1), "r"(a2) : "memory");
    return a0;
}

static inline long sys4(long n, long a, long b, long c, long d) {
    register long a7 __asm__("a7") = n;
    register long a0 __asm__("a0") = a;
    register long a1 __asm__("a1") = b;
    register long a2 __asm__("a2") = c;
    register long a3 __asm__("a3") = d;
    __asm__ volatile("ecall"
                     : "+r"(a0)
                     : "r"(a7), "r"(a1), "r"(a2), "r"(a3)
                     : "memory");
    return a0;
}

static inline ssize_t_ sys_write(int fd, const void *buf, size_t_ n) {
    return (ssize_t_)sys3(SYS_write, fd, (long)buf, (long)n);
}

static inline ssize_t_ sys_read(int fd, void *buf, size_t_ n) {
    return (ssize_t_)sys3(SYS_read, fd, (long)buf, (long)n);
}

static inline void sys_exit(int code) {
    sys1(SYS_exit, code);
    __builtin_unreachable();
}

static inline long sys_wait4(int pid, int *status, int options) {
    return sys4(SYS_wait4, pid, (long)status, options, 0);
}

static inline long sys_execve(const char *path, char *const argv[],
                              char *const envp[]) {
    return sys3(SYS_execve, (long)path, (long)argv, (long)envp);
}

static inline long sys_reboot(int cmd) {
    return sys4(SYS_reboot, (long)REBOOT_MAGIC1, (long)REBOOT_MAGIC2, cmd, 0);
}

/* Spawn `path` and wait for it. Implemented in spawn.S: on NOMMU there is no
 * fork(), so this uses clone(CLONE_VM|CLONE_VFORK|SIGCHLD) and the child does
 * nothing but execve, which is exactly what vfork() semantics allow. */
long spawn(const char *path, char *const argv[], char *const envp[]);

/* --- tiny formatting helpers (no libc) --- */

static inline size_t_ str_len(const char *s) {
    size_t_ n = 0;
    while (s[n]) n++;
    return n;
}

static inline void put_str(const char *s) { sys_write(1, s, str_len(s)); }

static inline void put_uint(unsigned int v) {
    char buf[12];
    int i = 12;
    if (v == 0) {
        sys_write(1, "0", 1);
        return;
    }
    while (v) {
        buf[--i] = (char)('0' + (v % 10));
        v /= 10;
    }
    sys_write(1, buf + i, (size_t_)(12 - i));
}

#endif /* RV32IMA_VERYL_SYS_H */
