# long spawn(const char *path, char *const argv[], char *const envp[])
#
# NOMMU has no fork(). clone(CLONE_VM|CLONE_VFORK|SIGCHLD) gives vfork
# semantics: the child shares this stack and the parent is suspended until the
# child execs or exits, so the child must do nothing but execve. Registers are
# copied to the child, which is why path/argv/envp are still valid there.
#
# riscv selects CLONE_BACKWARDS, so the syscall takes
# (flags, newsp, parent_tid, tls, child_tid).

#define SYS_clone   220
#define SYS_execve  221
#define SYS_exit     93
#define SYS_waitid   95

#define CLONE_VM     0x00000100
#define CLONE_VFORK  0x00004000
#define SIGCHLD      17

    .section .text
    .globl spawn
spawn:
    mv   t0, a0                # path
    mv   t1, a1                # argv
    mv   t2, a2                # envp

    li   a0, CLONE_VM | CLONE_VFORK | SIGCHLD
    li   a1, 0                 # share the caller's stack
    li   a2, 0
    li   a3, 0
    li   a4, 0
    li   a7, SYS_clone
    ecall

    bltz a0, 2f                # clone failed
    bnez a0, 1f                # parent: a0 = child pid

    # child: exec, and if that fails leave immediately so the parent resumes
    mv   a0, t0
    mv   a1, t1
    mv   a2, t2
    li   a7, SYS_execve
    ecall
    li   a0, 127
    li   a7, SYS_exit
    ecall

1:  # RV32 without time32 syscalls has waitid, but no wait4.
    mv   t3, a0                # preserve child pid across an interrupted wait
3:
    li   a0, 1                 # P_PID
    mv   a1, t3
    li   a2, 0                 # Linux permits a null siginfo pointer
    li   a3, 4                 # WEXITED
    li   a4, 0                 # no rusage
    li   a7, SYS_waitid
    ecall
    li   t4, -4                # EINTR
    beq  a0, t4, 3b
    ret

2:  ret
