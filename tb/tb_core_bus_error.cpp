// Fault injection uses the same top and hierarchy as the ISA coverage model.
// Internal architectural state is read for assertions, never modified.
#include "Vrv32ima_Soc.h"
#include "Vrv32ima_Soc___024root.h"
#include "verilated.h"
#include "verilated_cov.h"
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <initializer_list>

class Test {
    VerilatedContext context;
    Vrv32ima_Soc top{&context};
    unsigned cycles=0;
#define CORE(field) top.rootp->rv32ima_Soc__DOT__u_core__DOT__##field
    void check(bool ok, const char* message) {
        if (!ok) {
            std::fprintf(stderr,"cycle %u: %s (addr=%08x cause=%08x)\n",
                         cycles,message,top.o_mem_addr,top.o_trap_cause);
            std::exit(1);
        }
    }
    void tick() {
        top.i_clk=0; top.eval(); context.timeInc(5);
        top.i_clk=1; top.eval(); context.timeInc(5);
        top.i_clk=0; top.eval(); ++cycles;
    }
    void reset() {
        top.i_rst=1; top.i_mem_ready=0; top.i_mem_error=0;
        top.i_mtime_tick=0; top.i_irq_src=0; top.i_mem_rdata=0;
        tick(); top.i_rst=0; top.eval();
    }
    void instruction(uint32_t insn) {
        check(top.o_mem_valid && top.o_mem_wstrb==0,"expected fetch");
        top.i_mem_ready=1; top.i_mem_rdata=insn; top.i_mem_error=0;
        tick(); top.i_mem_ready=0; tick();
    }
    void setup() {
        reset();
        instruction(0x10000093); // x1 = 0x100
        instruction(0x05a00293); // x5 = sentinel
        instruction(0x03300113); // x2 = 0x33
        instruction(0x30509073); // mtvec = x1
    }
    void response(bool failed, uint32_t value=0x12345678) {
        check(top.o_mem_valid,"missing request");
        top.i_mem_error=1; top.i_mem_ready=0;
        for (int n=0; n<3; ++n) {
            tick();
            check(!top.o_trap && !top.o_retire && CORE(rf)[5]==0x5a,
                  "side effect before response");
        }
        top.i_mem_ready=1; top.i_mem_error=failed; top.i_mem_rdata=value;
        tick(); top.i_mem_ready=0; top.i_mem_error=0; top.eval();
    }
    void fault(uint32_t cause, uint32_t pc, uint32_t tval, uint64_t retired) {
        check(top.o_trap && !top.o_retire && top.o_trap_cause==cause &&
              top.o_retire_pc==pc && CORE(csr_mcause)==cause &&
              CORE(csr_mepc)==pc && CORE(csr_mtval)==tval &&
              CORE(rf)[5]==0x5a && CORE(csr_minstret)==retired &&
              !CORE(lr_valid) && top.o_mem_addr==0x100,"fault architectural state");
        instruction(0x00100313);
        check(top.o_retire && CORE(rf)[6]==1,"handler recovery");
    }
public:
    void run() {
        setup();
        uint32_t pc=top.o_mem_addr;
        uint64_t retired=CORE(csr_minstret);
        response(true,0x00100293); fault(1,pc,pc,retired);
        for (bool store: {false,true}) {
            for (int split=0; split<2; ++split) {
                for (int second=0; second<=split; ++second) {
                    setup(); pc=top.o_mem_addr; retired=CORE(csr_minstret);
                    instruction(store ? (split ? 0x0020a1a3 : 0x0020a023)
                                      : (split ? 0x0030a283 : 0x0000a283));
                    if (second) {
                        response(false);
                        check(!top.o_retire && !top.o_trap && top.o_mem_addr==0x104,
                              "split first half");
                    }
                    response(true);
                    fault(store ? 7:5,pc,second ? 0x104 : split ? 0x103:0x100,retired);
                }
            }
        }
        setup(); pc=top.o_mem_addr; retired=CORE(csr_minstret);
        instruction(0x1000a2af); response(true); fault(5,pc,0x100,retired);
        for (bool failed: {false,true}) {
            setup(); instruction(0x1000a02f); response(false); // LR to x0
            check(CORE(lr_valid) && top.o_retire,"LR success");
            pc=top.o_mem_addr; retired=CORE(csr_minstret);
            instruction(0x1820a2af); // SC x5,x2,(x1)
            check(CORE(rf)[5]==0x5a && top.o_mem_wstrb==15 && !CORE(lr_valid),
                  "SC result committed before response");
            response(failed);
            if (failed) fault(7,pc,0x100,retired);
            else check(top.o_retire && !top.o_trap && CORE(rf)[5]==0,"SC success");
        }
        for (int stage=0; stage<3; ++stage) {
            setup(); pc=top.o_mem_addr; retired=CORE(csr_minstret);
            instruction(0x0020a2af); // AMOADD x5,x2,(x1)
            response(stage==0);
            if (stage==0) fault(7,pc,0x100,retired);
            else {
                check(!top.o_retire && CORE(rf)[5]==0x5a && top.o_mem_wdata==0x123456ab,
                      "AMO read committed early");
                response(stage==1);
                if (stage==1) fault(7,pc,0x100,retired);
                else check(top.o_retire && !top.o_trap && CORE(rf)[5]==0x12345678,
                           "AMO success");
            }
        }
        for (bool plic: {false,true}) {
            setup(); instruction(plic ? 0x0c0000b7 : 0x110000b7);
            top.i_mem_ready=1; top.i_mem_rdata=0x0000a283; tick();
            top.i_mem_ready=0; top.i_mem_error=1; tick();
            check(!top.o_mem_valid,"local access escaped SoC");
            tick(); top.i_mem_error=0;
            check(!top.o_trap && top.o_retire,"external error affected local device");
        }
        for (int phase=0; phase<3; ++phase) {
            setup(); instruction(phase==2 ? 0x0020a2af : phase==1 ? 0x0030a283 : 0x0000a283);
            if (phase!=0) response(false);
            check(top.o_mem_valid,"missing stalled request");
            reset();
            check(!top.o_trap && !top.o_retire && !CORE(lr_valid) && CORE(csr_minstret)==0,
                  "reset did not cancel transaction");
            instruction(0x00100313);
            check(top.o_retire && CORE(rf)[6]==1,"reset recovery");
        }
        setup(); top.i_mem_ready=1; top.i_mem_rdata=0x00100313; tick();
        top.i_mem_error=1; tick(); top.i_mem_ready=0; top.i_mem_error=0;
        check(top.o_retire && !top.o_trap && CORE(rf)[6]==1,"idle error trapped");
        // Make the CLINT timer expire while an external instruction fetch stalls.
        // Both successful and faulting responses must belong to the original PC.
        for (bool failed: {false,true}) {
            setup();
            instruction(0x110041b7); // x3 = CLINT mtimecmp
            instruction(0x00300213); // x4 = 3
            instruction(0x0041a023); tick(); // mtimecmp low = 3
            instruction(0x0001a223); tick(); // mtimecmp high = 0
            instruction(0x08000213); // x4 = MTIE
            instruction(0x30421073); // mie = MTIE
            instruction(0x30046073); // mstatus.MIE = 1
            pc=top.o_mem_addr; retired=CORE(csr_minstret);
            tick(); // The memory receiver has now accepted the fetch request.
            top.i_mtime_tick=1;
            for (int n=0; n<5; ++n) {
                tick();
                check(top.o_mem_valid && top.o_mem_addr==pc && !top.o_trap,
                      "interrupt cancelled stalled fetch");
            }
            top.i_mtime_tick=0;
            response(failed,0x00100313);
            if (failed) fault(1,pc,pc,retired);
            else {
                tick();
                check(top.o_retire && !top.o_trap && CORE(rf)[6]==1 &&
                      !top.o_mem_valid,"fetch did not retire before interrupt");
                // A ready/error value outside a request cannot override the IRQ.
                top.i_mem_ready=1; top.i_mem_error=1; tick();
                top.i_mem_ready=0; top.i_mem_error=0;
                check(top.o_trap && top.o_trap_cause==0x80000007 &&
                      CORE(csr_mepc)==pc+4 && CORE(csr_mtval)==0 &&
                      CORE(csr_minstret)==retired+1,"deferred interrupt state");
            }
        }
        top.final();
        context.coveragep()->write("logs/cov/core_bus_error.dat");
        std::puts("Core bus error PASS: fetch/load/store/split/LR/SC/AMO, delay, local decode, reset, recovery");
    }
#undef CORE
};

int main() { Test test; test.run(); }
