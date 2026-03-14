// descriptor_bypass_wrapper_core_tb.cpp
// Verilator C++ testbench for descriptor_bypass_wrapper_core.sv
//
// Build and run:
//   verilator --cc --exe --build -j0 \
//     descriptor_bypass_wrapper_core.sv \
//     descriptor_bypass_wrapper_core_tb.cpp
//   ./obj_dir/Vdescriptor_bypass_wrapper_core

#include "verilated.h"
#include "Vdescriptor_bypass_wrapper_core.h"

#include <cstdint>
#include <iostream>
#include <string>

// ----------------------------------------------------------------
// Globals
// ----------------------------------------------------------------
static Vdescriptor_bypass_wrapper_core *dut;
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
//
// Sample ready signals before the rising edge, deassert valid
// after the tick on which the handshake fires.
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
    // One more tick so the DUT processes bvalid && bready
    tick();
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
    tick();
    dut->s_axil_rready = 0;
    return data;
}

// ----------------------------------------------------------------
// main
// ----------------------------------------------------------------
int main(int argc, char **argv) {
    Verilated::commandArgs(argc, argv);
    dut = new Vdescriptor_bypass_wrapper_core;

    // Initialise all inputs
    dut->s_axil_aclk       = 0;
    dut->s_axil_aresetn    = 0;
    dut->s_axil_awvalid    = 0;
    dut->s_axil_awaddr     = 0;
    dut->s_axil_wvalid     = 0;
    dut->s_axil_wdata      = 0;
    dut->s_axil_wstrb      = 0xf;
    dut->s_axil_bready     = 0;
    dut->s_axil_arvalid    = 0;
    dut->s_axil_araddr     = 0;
    dut->s_axil_rready     = 0;
    dut->h2c_dsc_byp_ready = 0;
    dut->c2h_dsc_byp_ready = 0;

    // Reset
    for (int i = 0; i < 4; ++i) tick();
    dut->s_axil_aresetn = 1;
    tick(); tick();

    // ================================================================
    std::cout << "--- Test 1: Reset state ---\n";
    // ================================================================
    check("h2c_load=0",      dut->h2c_dsc_byp_load,     0);
    check("c2h_load=0",      dut->c2h_dsc_byp_load,     0);
    check("h2c_src_addr=0",  dut->h2c_dsc_byp_src_addr, 0);
    check("h2c_dst_addr=0",  dut->h2c_dsc_byp_dst_addr, 0);
    check("h2c_len=0",       dut->h2c_dsc_byp_len,      0);
    check("h2c_ctl=0",       dut->h2c_dsc_byp_ctl,      0);
    check("c2h_src_addr=0",  dut->c2h_dsc_byp_src_addr, 0);
    check("c2h_dst_addr=0",  dut->c2h_dsc_byp_dst_addr, 0);
    check("c2h_len=0",       dut->c2h_dsc_byp_len,      0);
    check("c2h_ctl=0",       dut->c2h_dsc_byp_ctl,      0);

    // ================================================================
    std::cout << "--- Test 2: H2C register write and read-back ---\n";
    // ================================================================
    axil_write(0x00, 0xDEAD0001);
    axil_write(0x04, 0xDEAD0002);
    axil_write(0x08, 0xDEAD0003);
    axil_write(0x0C, 0xDEAD0004);
    axil_write(0x10, 0x00001000);
    axil_write(0x14, 0x00000003);

    check("h2c_src_addr", dut->h2c_dsc_byp_src_addr, 0xDEAD0002DEAD0001ULL);
    check("h2c_dst_addr", dut->h2c_dsc_byp_dst_addr, 0xDEAD0004DEAD0003ULL);
    check("h2c_len",      dut->h2c_dsc_byp_len,      0x1000);
    check("h2c_ctl",      dut->h2c_dsc_byp_ctl,      0x0003);

    check("rd h2c src_lo", axil_read(0x00), 0xDEAD0001);
    check("rd h2c src_hi", axil_read(0x04), 0xDEAD0002);
    check("rd h2c dst_lo", axil_read(0x08), 0xDEAD0003);
    check("rd h2c dst_hi", axil_read(0x0C), 0xDEAD0004);
    check("rd h2c len",    axil_read(0x10), 0x00001000);
    check("rd h2c ctl",    axil_read(0x14), 0x00000003);

    // ================================================================
    std::cout << "--- Test 3: C2H register write and read-back ---\n";
    // ================================================================
    axil_write(0x40, 0xC2C20001);
    axil_write(0x44, 0xC2C20002);
    axil_write(0x48, 0xC2C20003);
    axil_write(0x4C, 0xC2C20004);
    axil_write(0x50, 0x00002000);
    axil_write(0x54, 0x00000002);

    check("c2h_src_addr", dut->c2h_dsc_byp_src_addr, 0xC2C20002C2C20001ULL);
    check("c2h_dst_addr", dut->c2h_dsc_byp_dst_addr, 0xC2C20004C2C20003ULL);
    check("c2h_len",      dut->c2h_dsc_byp_len,      0x2000);
    check("c2h_ctl",      dut->c2h_dsc_byp_ctl,      0x0002);

    check("rd c2h src_lo", axil_read(0x40), 0xC2C20001);
    check("rd c2h src_hi", axil_read(0x44), 0xC2C20002);
    check("rd c2h dst_lo", axil_read(0x48), 0xC2C20003);
    check("rd c2h dst_hi", axil_read(0x4C), 0xC2C20004);
    check("rd c2h len",    axil_read(0x50), 0x00002000);
    check("rd c2h ctl",    axil_read(0x54), 0x00000002);

    // ================================================================
    std::cout << "--- Test 4: Status register reflects dsc_byp_ready ---\n";
    // ================================================================
    dut->h2c_dsc_byp_ready = 1;
    dut->c2h_dsc_byp_ready = 0;
    tick();
    check("h2c status=1", axil_read(0x1C), 1);
    check("c2h status=0", axil_read(0x5C), 0);

    dut->h2c_dsc_byp_ready = 0;
    dut->c2h_dsc_byp_ready = 1;
    tick();
    check("h2c status=0", axil_read(0x1C), 0);
    check("c2h status=1", axil_read(0x5C), 1);

    // ================================================================
    std::cout << "--- Test 5: H2C GO — load pulses when ready is high ---\n";
    // ================================================================
    dut->h2c_dsc_byp_ready = 1;
    dut->c2h_dsc_byp_ready = 0;

    axil_write(0x18, 0x1);

    bool h2c_load_seen = false;
    for (int i = 0; i < 4; ++i) {
        tick();
        if (dut->h2c_dsc_byp_load) h2c_load_seen = true;
    }
    check("h2c_load pulsed",   h2c_load_seen,         1);
    check("c2h_load stayed 0", dut->c2h_dsc_byp_load, 0);
    check("h2c_load deasserted after pulse", dut->h2c_dsc_byp_load, 0);

    // ================================================================
    std::cout << "--- Test 6: H2C GO — load waits until ready ---\n";
    // ================================================================
    dut->h2c_dsc_byp_ready = 0;

    axil_write(0x18, 0x1);
    for (int i = 0; i < 3; ++i) tick();
    check("h2c_load not yet (ready=0)", dut->h2c_dsc_byp_load, 0);

    dut->h2c_dsc_byp_ready = 1;
    bool load_fired = false;
    for (int i = 0; i < 4; ++i) {
        tick();
        if (dut->h2c_dsc_byp_load) load_fired = true;
    }
    check("h2c_load fired after ready",  load_fired,            1);
    check("h2c_load deasserted",         dut->h2c_dsc_byp_load, 0);
    dut->h2c_dsc_byp_ready = 0;

    // ================================================================
    std::cout << "--- Test 7: C2H GO — load pulses when ready is high ---\n";
    // ================================================================
    dut->c2h_dsc_byp_ready = 1;

    axil_write(0x58, 0x1);

    bool c2h_load_seen = false;
    for (int i = 0; i < 4; ++i) {
        tick();
        if (dut->c2h_dsc_byp_load) c2h_load_seen = true;
    }
    check("c2h_load pulsed",   c2h_load_seen,         1);
    check("h2c_load stayed 0", dut->h2c_dsc_byp_load, 0);
    dut->c2h_dsc_byp_ready = 0;

    // ================================================================
    std::cout << "--- Test 8: GO register reads back 0 (WO) ---\n";
    // ================================================================
    check("h2c go reads 0", axil_read(0x18), 0);
    check("c2h go reads 0", axil_read(0x58), 0);

    // ================================================================
    std::cout << "--- Test 9: AW before W ---\n";
    // ================================================================
    {
        dut->s_axil_awaddr  = 0x00;
        dut->s_axil_awvalid = 1;
        dut->s_axil_wvalid  = 0;
        dut->s_axil_bready  = 1;

        for (int guard = 0; guard < 20; ++guard) {
            bool aw_rdy = dut->s_axil_awready;
            tick();
            if (aw_rdy) { dut->s_axil_awvalid = 0; break; }
        }
        tick(); tick();  // deliberate gap before W

        dut->s_axil_wdata  = 0xABCD1234;
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

        check("AW-before-W src_lo",
              static_cast<uint32_t>(dut->h2c_dsc_byp_src_addr), 0xABCD1234);
    }

    // ================================================================
    std::cout << "--- Test 10: W before AW ---\n";
    // ================================================================
    {
        dut->s_axil_wdata   = 0x5678BEEF;
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

        dut->s_axil_awaddr  = 0x04;
        dut->s_axil_awvalid = 1;
        for (int guard = 0; guard < 20; ++guard) {
            bool aw_rdy = dut->s_axil_awready;
            tick();
            if (aw_rdy) { dut->s_axil_awvalid = 0; break; }
        }
        while (!dut->s_axil_bvalid) tick();
        tick();
        dut->s_axil_bready = 0;

        check("W-before-AW src_hi",
              static_cast<uint32_t>(dut->h2c_dsc_byp_src_addr >> 32), 0x5678BEEF);
    }

    // ================================================================
    std::cout << "--- Test 11: Unmapped address write is ignored ---\n";
    // ================================================================
    axil_write(0xFF, 0xDEADBEEF);
    check("unmapped write no side-effect", dut->h2c_dsc_byp_len, 0x1000);

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
    return fail_count ? 1 : 0;
}
