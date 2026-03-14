// axil_dma_ctrl_tb.cpp
// Verilator C++ testbench for axil_dma_ctrl.sv
//
// Build and run:
//   verilator --cc --exe --build -j0 \
//     axil_dma_ctrl.sv \
//     axil_dma_ctrl_tb.cpp
//   ./obj_dir/Vaxil_dma_ctrl

#include "verilated.h"
#include "Vaxil_dma_ctrl.h"

#include <cstdint>
#include <iostream>
#include <string>

// ----------------------------------------------------------------
// Globals
// ----------------------------------------------------------------
static VerilatedContext *ctx;
static Vaxil_dma_ctrl  *dut;
static int pass_count = 0;
static int fail_count = 0;

// ----------------------------------------------------------------
// Clock
// ----------------------------------------------------------------
static void tick() {
    dut->s_axil_aclk = 0;
    dut->eval();
    dut->s_axil_aclk = 1;
    dut->eval();
}

// ----------------------------------------------------------------
// Check helper
// ----------------------------------------------------------------
static void check(const std::string &name, uint64_t got, uint64_t exp) {
    if (got == exp) {
        std::cout << "  PASS  " << name << "\n";
        ++pass_count;
    } else {
        std::cout << std::hex
                  << "  FAIL  " << name
                  << ": got 0x" << got
                  << ", expected 0x" << exp
                  << std::dec << "\n";
        ++fail_count;
    }
}

// ----------------------------------------------------------------
// AXI-Lite helpers
// ----------------------------------------------------------------
static void axil_write(uint32_t addr, uint32_t data) {
    dut->s_axil_awaddr  = addr;
    dut->s_axil_awvalid = 1;
    dut->s_axil_wdata   = data;
    dut->s_axil_wstrb   = 0xf;
    dut->s_axil_wvalid  = 1;
    dut->s_axil_bready  = 1;

    bool aw_done = false, w_done = false;
    for (int guard = 0; guard < 100; ++guard) {
        if (!aw_done && dut->s_axil_awready) aw_done = true;
        if (!w_done  && dut->s_axil_wready)  w_done  = true;
        tick();
        if (aw_done) dut->s_axil_awvalid = 0;
        if (w_done)  dut->s_axil_wvalid  = 0;
        if (aw_done && w_done && dut->s_axil_bvalid) break;
    }
    tick();  // DUT processes bvalid && bready
    dut->s_axil_bready = 0;
}

static uint32_t axil_read(uint32_t addr) {
    dut->s_axil_araddr  = addr;
    dut->s_axil_arvalid = 1;
    dut->s_axil_rready  = 1;

    for (int guard = 0; guard < 100; ++guard) {
        bool ar_accepted = dut->s_axil_arready;
        tick();
        if (ar_accepted) { dut->s_axil_arvalid = 0; break; }
    }
    for (int guard = 0; guard < 100; ++guard) {
        if (dut->s_axil_rvalid) break;
        tick();
    }
    uint32_t data = dut->s_axil_rdata;
    tick();  // DUT processes rvalid && rready
    dut->s_axil_rready = 0;
    return data;
}

// Read a 64-bit register as two 32-bit AXI reads
static uint64_t axil_read64(uint32_t addr_lo) {
    uint64_t lo = axil_read(addr_lo);
    uint64_t hi = axil_read(addr_lo + 4);
    return (hi << 32) | lo;
}

// ----------------------------------------------------------------
// main
// ----------------------------------------------------------------
int main(int argc, char **argv) {
    ctx = new VerilatedContext;
    ctx->commandArgs(argc, argv);
    dut = new Vaxil_dma_ctrl{ctx};

    // Initialise all inputs
    dut->s_axil_aclk    = 0;
    dut->s_axil_aresetn = 0;
    dut->s_axil_awvalid = 0;
    dut->s_axil_awaddr  = 0;
    dut->s_axil_wvalid  = 0;
    dut->s_axil_wdata   = 0;
    dut->s_axil_wstrb   = 0xf;
    dut->s_axil_bready  = 0;
    dut->s_axil_arvalid = 0;
    dut->s_axil_araddr  = 0;
    dut->s_axil_rready  = 0;

    // Reset
    for (int i = 0; i < 4; ++i) tick();
    dut->s_axil_aresetn = 1;
    tick(); tick();

    // ================================================================
    std::cout << "--- Test 1: Reset state ---\n";
    // ================================================================
    check("host_addr_lo=0", axil_read(0x00), 0);
    check("host_addr_hi=0", axil_read(0x04), 0);
    check("card_addr_lo=0", axil_read(0x08), 0);
    check("card_addr_hi=0", axil_read(0x0C), 0);
    check("len_lo=0",       axil_read(0x10), 0);
    check("len_hi=0",       axil_read(0x14), 0);

    // ================================================================
    std::cout << "--- Test 2: host_addr write and read-back ---\n";
    // ================================================================
    axil_write(0x00, 0xDEADBEEF);
    axil_write(0x04, 0xCAFEF00D);

    check("rd host_addr_lo", axil_read(0x00), 0xDEADBEEF);
    check("rd host_addr_hi", axil_read(0x04), 0xCAFEF00D);

    // ================================================================
    std::cout << "--- Test 3: card_addr write and read-back ---\n";
    // ================================================================
    axil_write(0x08, 0x11223344);
    axil_write(0x0C, 0x55667788);

    check("rd card_addr_lo", axil_read(0x08), 0x11223344);
    check("rd card_addr_hi", axil_read(0x0C), 0x55667788);

    // ================================================================
    std::cout << "--- Test 4: len write and read-back ---\n";
    // ================================================================
    axil_write(0x10, 0x00100000);
    axil_write(0x14, 0x00000000);

    check("rd len_lo", axil_read(0x10), 0x00100000);
    check("rd len_hi", axil_read(0x14), 0x00000000);

    // ================================================================
    std::cout << "--- Test 5: Overwrite updates register ---\n";
    // ================================================================
    axil_write(0x00, 0xAAAAAAAA);
    axil_write(0x04, 0xBBBBBBBB);

    check("host_addr overwritten", axil_read64(0x00), 0xBBBBBBBBAAAAAAAAULL);
    check("card_addr unchanged",   axil_read64(0x08), 0x5566778811223344ULL);
    check("len unchanged",         axil_read64(0x10), 0x0000000000100000ULL);

    // ================================================================
    std::cout << "--- Test 6: AW before W ---\n";
    // ================================================================
    {
        dut->s_axil_awaddr  = 0x08;
        dut->s_axil_awvalid = 1;
        dut->s_axil_wvalid  = 0;
        dut->s_axil_bready  = 1;

        for (int guard = 0; guard < 20; ++guard) {
            bool aw_rdy = dut->s_axil_awready;
            tick();
            if (aw_rdy) { dut->s_axil_awvalid = 0; break; }
        }
        tick(); tick();  // deliberate gap before W

        dut->s_axil_wdata  = 0xFACEFACE;
        dut->s_axil_wstrb  = 0xf;
        dut->s_axil_wvalid = 1;
        for (int guard = 0; guard < 20; ++guard) {
            bool w_rdy = dut->s_axil_wready;
            tick();
            if (w_rdy) { dut->s_axil_wvalid = 0; break; }
        }
        while (!dut->s_axil_bvalid) tick();
        tick();
        dut->s_axil_bready = 0;

        check("AW-before-W card_addr_lo", axil_read(0x08), 0xFACEFACE);
    }

    // ================================================================
    std::cout << "--- Test 7: W before AW ---\n";
    // ================================================================
    {
        dut->s_axil_wdata   = 0x0BADF00D;
        dut->s_axil_wstrb   = 0xf;
        dut->s_axil_wvalid  = 1;
        dut->s_axil_awvalid = 0;
        dut->s_axil_bready  = 1;

        for (int guard = 0; guard < 20; ++guard) {
            bool w_rdy = dut->s_axil_wready;
            tick();
            if (w_rdy) { dut->s_axil_wvalid = 0; break; }
        }
        tick(); tick();  // deliberate gap before AW

        dut->s_axil_awaddr  = 0x0C;
        dut->s_axil_awvalid = 1;
        for (int guard = 0; guard < 20; ++guard) {
            bool aw_rdy = dut->s_axil_awready;
            tick();
            if (aw_rdy) { dut->s_axil_awvalid = 0; break; }
        }
        while (!dut->s_axil_bvalid) tick();
        tick();
        dut->s_axil_bready = 0;

        check("W-before-AW card_addr_hi", axil_read(0x0C), 0x0BADF00D);
    }

    // ================================================================
    std::cout << "--- Test 8: Unmapped address write is ignored ---\n";
    // ================================================================
    uint32_t len_lo_before    = axil_read(0x10);
    uint32_t host_hi_before   = axil_read(0x04);
    axil_write(0xFF, 0xDEADBEEF);
    check("unmapped write no side-effect on len_lo",    axil_read(0x10), len_lo_before);
    check("unmapped write no side-effect on host_hi",   axil_read(0x04), host_hi_before);

    // ================================================================
    std::cout << "--- Test 9: Unmapped address reads back 0 ---\n";
    // ================================================================
    check("rd unmapped 0x18", axil_read(0x18), 0x00000000);
    check("rd unmapped 0x1C", axil_read(0x1C), 0x00000000);

    // ================================================================
    std::cout << "--- Test 10: All registers independent ---\n";
    // ================================================================
    axil_write(0x00, 0x00000001); axil_write(0x04, 0x00000002);
    axil_write(0x08, 0x00000003); axil_write(0x0C, 0x00000004);
    axil_write(0x10, 0x00000005); axil_write(0x14, 0x00000006);

    check("host_addr", axil_read64(0x00), 0x0000000200000001ULL);
    check("card_addr", axil_read64(0x08), 0x0000000400000003ULL);
    check("len",       axil_read64(0x10), 0x0000000600000005ULL);

    // ================================================================
    std::cout << "--- Summary ---\n";
    // ================================================================
    std::cout << "PASSED: " << pass_count
              << "  FAILED: " << fail_count << "\n";
    if (fail_count == 0)
        std::cout << "ALL TESTS PASSED\n";
    else
        std::cout << "SOME TESTS FAILED\n";

    dut->final();
    delete dut;
    delete ctx;
    return fail_count ? 1 : 0;
}
