// descriptor_bypass_wrapper_tb.sv
//
// AXI4-Lite VIP (PG267 v1.1) testbench for descriptor_bypass_wrapper.v
//
// The AXI VIP master component (axi_vip_mst_0) must be generated in the
// Vivado IP Catalog with the following settings:
//   Component Name  : axi_vip_mst_0
//   PROTOCOL        : AXI4LITE
//   INTERFACE_MODE  : MASTER
//   ADDR_WIDTH      : 32
//   DATA_WIDTH      : 32
//   HAS_WSTRB       : 1
//   HAS_BRESP       : 1
//   HAS_RRESP       : 1
//
// Compile order (Vivado xvlog -sv):
//   1. Xilinx simulation libraries (unisims_ver, axi_vip_v1_1_*)
//   2. axi_vip_mst_0_pkg.sv           -- generated component package
//   3. axi_vip_mst_0.sv               -- generated component wrapper
//   4. descriptor_bypass_wrapper_core.sv
//   5. descriptor_bypass_wrapper.v
//   6. descriptor_bypass_wrapper_tb.sv (this file)
//
// The VIP agent is created with the hierarchy path:
//   descriptor_bypass_wrapper_tb.u_vip_mst.inst.IF

`timescale 1ns / 1ps

module descriptor_bypass_wrapper_tb;

    import axi_vip_pkg::*;
    import axi_vip_mst_0_pkg::*;

    // ----------------------------------------------------------------
    // Clock and reset
    // ----------------------------------------------------------------
    localparam CLK_HALF = 5; // 100 MHz

    logic aclk    = 1'b0;
    logic aresetn = 1'b0;

    always #CLK_HALF aclk = ~aclk;

    // ----------------------------------------------------------------
    // AXI-Lite bus wires (VIP master ↔ DUT slave)
    // ----------------------------------------------------------------
    wire [31:0] axil_awaddr;
    wire        axil_awvalid;
    wire        axil_awready;

    wire [31:0] axil_wdata;
    wire [3:0]  axil_wstrb;
    wire        axil_wvalid;
    wire        axil_wready;

    wire [1:0]  axil_bresp;
    wire        axil_bvalid;
    wire        axil_bready;

    wire [31:0] axil_araddr;
    wire        axil_arvalid;
    wire        axil_arready;

    wire [31:0] axil_rdata;
    wire [1:0]  axil_rresp;
    wire        axil_rvalid;
    wire        axil_rready;

    // ----------------------------------------------------------------
    // Descriptor bypass signals
    // ----------------------------------------------------------------
    logic        h2c_dsc_byp_ready = 1'b1;
    wire         h2c_dsc_byp_load;
    wire [63:0]  h2c_dsc_byp_src_addr;
    wire [63:0]  h2c_dsc_byp_dst_addr;
    wire [27:0]  h2c_dsc_byp_len;
    wire [15:0]  h2c_dsc_byp_ctl;

    logic        c2h_dsc_byp_ready = 1'b1;
    wire         c2h_dsc_byp_load;
    wire [63:0]  c2h_dsc_byp_src_addr;
    wire [63:0]  c2h_dsc_byp_dst_addr;
    wire [27:0]  c2h_dsc_byp_len;
    wire [15:0]  c2h_dsc_byp_ctl;

    // ----------------------------------------------------------------
    // AXI VIP master instance
    // ----------------------------------------------------------------
    axi_vip_mst_0 u_vip_mst (
        .aclk           (aclk),
        .aresetn        (aresetn),
        .m_axi_awaddr   (axil_awaddr),
        .m_axi_awvalid  (axil_awvalid),
        .m_axi_awready  (axil_awready),
        .m_axi_wdata    (axil_wdata),
        .m_axi_wstrb    (axil_wstrb),
        .m_axi_wvalid   (axil_wvalid),
        .m_axi_wready   (axil_wready),
        .m_axi_bresp    (axil_bresp),
        .m_axi_bvalid   (axil_bvalid),
        .m_axi_bready   (axil_bready),
        .m_axi_araddr   (axil_araddr),
        .m_axi_arvalid  (axil_arvalid),
        .m_axi_arready  (axil_arready),
        .m_axi_rdata    (axil_rdata),
        .m_axi_rresp    (axil_rresp),
        .m_axi_rvalid   (axil_rvalid),
        .m_axi_rready   (axil_rready)
    );

    // ----------------------------------------------------------------
    // DUT instance
    // ----------------------------------------------------------------
    descriptor_bypass_wrapper dut (
        .s_axil_aclk            (aclk),
        .s_axil_aresetn         (aresetn),

        .s_axil_awaddr          (axil_awaddr),
        .s_axil_awvalid         (axil_awvalid),
        .s_axil_awready         (axil_awready),

        .s_axil_wdata           (axil_wdata),
        .s_axil_wstrb           (axil_wstrb),
        .s_axil_wvalid          (axil_wvalid),
        .s_axil_wready          (axil_wready),

        .s_axil_bresp           (axil_bresp),
        .s_axil_bvalid          (axil_bvalid),
        .s_axil_bready          (axil_bready),

        .s_axil_araddr          (axil_araddr),
        .s_axil_arvalid         (axil_arvalid),
        .s_axil_arready         (axil_arready),

        .s_axil_rdata           (axil_rdata),
        .s_axil_rresp           (axil_rresp),
        .s_axil_rvalid          (axil_rvalid),
        .s_axil_rready          (axil_rready),

        .h2c_dsc_byp_ready      (h2c_dsc_byp_ready),
        .h2c_dsc_byp_load       (h2c_dsc_byp_load),
        .h2c_dsc_byp_src_addr   (h2c_dsc_byp_src_addr),
        .h2c_dsc_byp_dst_addr   (h2c_dsc_byp_dst_addr),
        .h2c_dsc_byp_len        (h2c_dsc_byp_len),
        .h2c_dsc_byp_ctl        (h2c_dsc_byp_ctl),

        .c2h_dsc_byp_ready      (c2h_dsc_byp_ready),
        .c2h_dsc_byp_load       (c2h_dsc_byp_load),
        .c2h_dsc_byp_src_addr   (c2h_dsc_byp_src_addr),
        .c2h_dsc_byp_dst_addr   (c2h_dsc_byp_dst_addr),
        .c2h_dsc_byp_len        (c2h_dsc_byp_len),
        .c2h_dsc_byp_ctl        (c2h_dsc_byp_ctl)
    );

    // ----------------------------------------------------------------
    // VIP master agent (PG267 §7: Must Haves)
    //   typedef: <component_name>_mst_t
    //   hierarchy path: <tb>.<vip_instance>.inst.IF
    // ----------------------------------------------------------------
    axi_vip_mst_0_mst_t mst_agent;

    // ----------------------------------------------------------------
    // Test counters
    // ----------------------------------------------------------------
    int pass_count = 0;
    int fail_count = 0;

    // ----------------------------------------------------------------
    // Check helpers
    // ----------------------------------------------------------------
    task automatic check_reg(
        input string         name,
        input xil_axi_data_beat got,   // 32 significant bits for AXI4LITE
        input logic [31:0]   exp
    );
        if (got[31:0] === exp) begin
            $display("  PASS  %s", name);
            pass_count++;
        end else begin
            $display("  FAIL  %s : got 0x%08h, expected 0x%08h",
                     name, got[31:0], exp);
            fail_count++;
        end
    endtask

    task automatic check_64(
        input string       name,
        input logic [63:0] got,
        input logic [63:0] exp
    );
        if (got === exp) begin
            $display("  PASS  %s", name);
            pass_count++;
        end else begin
            $display("  FAIL  %s : got 0x%016h, expected 0x%016h",
                     name, got, exp);
            fail_count++;
        end
    endtask

    task automatic check_1(
        input string     name,
        input logic      got,
        input logic      exp
    );
        if (got === exp) begin
            $display("  PASS  %s", name);
            pass_count++;
        end else begin
            $display("  FAIL  %s : got %b, expected %b", name, got, exp);
            fail_count++;
        end
    endtask

    // ----------------------------------------------------------------
    // AXI-Lite transaction wrappers (PG267 §7: Method 2 — blocking)
    // ----------------------------------------------------------------
    task automatic axil_write(
        input  xil_axi_ulong   addr,
        input  logic [31:0]    wdata,
        input  xil_axi_strb_beat wstrb = 4'hF
    );
        xil_axi_resp_t bresp;
        mst_agent.AXI4LITE_WRITE_BURST(addr, 3'b000,
                                        xil_axi_data_beat'(wdata),
                                        wstrb, bresp);
    endtask

    task automatic axil_read(
        input  xil_axi_ulong    addr,
        output xil_axi_data_beat rdata
    );
        xil_axi_resp_t rresp;
        mst_agent.AXI4LITE_READ_BURST(addr, 3'b000, rdata, rresp);
    endtask

    // ----------------------------------------------------------------
    // Main stimulus
    // ----------------------------------------------------------------
    xil_axi_data_beat rdata;

    initial begin
        // --- VIP agent setup (PG267 §7 steps 2-4) ---
        mst_agent = new("mst_agent",
                        descriptor_bypass_wrapper_tb.u_vip_mst.inst.IF);
        mst_agent.set_agent_tag("MST");
        mst_agent.set_verbosity(XIL_AXI_VERBOSITY_NONE);
        mst_agent.start_master();

        // --- Reset sequence (PG267 §4: aresetn ≥ 16 cycles low) ---
        aresetn = 1'b0;
        repeat (20) @(posedge aclk);
        aresetn = 1'b1;
        repeat (4)  @(posedge aclk);

        // ============================================================
        $display("--- Test 1: Reset state ---");
        // ============================================================
        axil_read(32'h00, rdata); check_reg("H2C src_addr_lo = 0",  rdata, 32'h0);
        axil_read(32'h04, rdata); check_reg("H2C src_addr_hi = 0",  rdata, 32'h0);
        axil_read(32'h08, rdata); check_reg("H2C dst_addr_lo = 0",  rdata, 32'h0);
        axil_read(32'h0C, rdata); check_reg("H2C dst_addr_hi = 0",  rdata, 32'h0);
        axil_read(32'h10, rdata); check_reg("H2C len = 0",          rdata, 32'h0);
        axil_read(32'h14, rdata); check_reg("H2C ctl = 0",          rdata, 32'h0);
        axil_read(32'h1C, rdata); check_reg("H2C status ready=1",   rdata, 32'h1);

        axil_read(32'h40, rdata); check_reg("C2H src_addr_lo = 0",  rdata, 32'h0);
        axil_read(32'h44, rdata); check_reg("C2H src_addr_hi = 0",  rdata, 32'h0);
        axil_read(32'h48, rdata); check_reg("C2H dst_addr_lo = 0",  rdata, 32'h0);
        axil_read(32'h4C, rdata); check_reg("C2H dst_addr_hi = 0",  rdata, 32'h0);
        axil_read(32'h50, rdata); check_reg("C2H len = 0",          rdata, 32'h0);
        axil_read(32'h54, rdata); check_reg("C2H ctl = 0",          rdata, 32'h0);
        axil_read(32'h5C, rdata); check_reg("C2H status ready=1",   rdata, 32'h1);

        // ============================================================
        $display("--- Test 2: H2C register write/read-back ---");
        // ============================================================
        axil_write(32'h00, 32'hDEAD_BEEF);
        axil_write(32'h04, 32'hCAFE_F00D);
        axil_write(32'h08, 32'h1234_5678);
        axil_write(32'h0C, 32'h9ABC_DEF0);
        axil_write(32'h10, 32'h0FFF_FFFF);  // max 28-bit len
        axil_write(32'h14, 32'h0000_ABCD);  // 16-bit ctl

        axil_read(32'h00, rdata); check_reg("H2C src_addr_lo", rdata, 32'hDEAD_BEEF);
        axil_read(32'h04, rdata); check_reg("H2C src_addr_hi", rdata, 32'hCAFE_F00D);
        axil_read(32'h08, rdata); check_reg("H2C dst_addr_lo", rdata, 32'h1234_5678);
        axil_read(32'h0C, rdata); check_reg("H2C dst_addr_hi", rdata, 32'h9ABC_DEF0);
        axil_read(32'h10, rdata); check_reg("H2C len",         rdata, 32'h0FFF_FFFF);
        axil_read(32'h14, rdata); check_reg("H2C ctl",         rdata, 32'h0000_ABCD);

        // ============================================================
        $display("--- Test 3: C2H register write/read-back ---");
        // ============================================================
        axil_write(32'h40, 32'hAABB_CCDD);
        axil_write(32'h44, 32'hEEFF_0011);
        axil_write(32'h48, 32'h2233_4455);
        axil_write(32'h4C, 32'h6677_8899);
        axil_write(32'h50, 32'h0100_0000);
        axil_write(32'h54, 32'h0000_1234);

        axil_read(32'h40, rdata); check_reg("C2H src_addr_lo", rdata, 32'hAABB_CCDD);
        axil_read(32'h44, rdata); check_reg("C2H src_addr_hi", rdata, 32'hEEFF_0011);
        axil_read(32'h48, rdata); check_reg("C2H dst_addr_lo", rdata, 32'h2233_4455);
        axil_read(32'h4C, rdata); check_reg("C2H dst_addr_hi", rdata, 32'h6677_8899);
        axil_read(32'h50, rdata); check_reg("C2H len",         rdata, 32'h0100_0000);
        axil_read(32'h54, rdata); check_reg("C2H ctl",         rdata, 32'h0000_1234);

        // ============================================================
        $display("--- Test 4: H2C GO — load pulses when ready=1 ---");
        // ============================================================
        // ready is already high from reset defaults
        h2c_dsc_byp_ready = 1'b1;
        axil_write(32'h18, 32'h0000_0001);  // GO

        @(posedge aclk);  // load fires this cycle (go_pending && ready)
        check_1 ("H2C load asserted",      h2c_dsc_byp_load,     1'b1);
        check_64("H2C src_addr on output", h2c_dsc_byp_src_addr,
                 {32'hCAFE_F00D, 32'hDEAD_BEEF});
        check_64("H2C dst_addr on output", h2c_dsc_byp_dst_addr,
                 {32'h9ABC_DEF0, 32'h1234_5678});
        check_1 ("H2C len[27:0] correct",
                 (h2c_dsc_byp_len === 28'hFFF_FFFF), 1'b1);
        check_1 ("H2C ctl[15:0] correct",
                 (h2c_dsc_byp_ctl === 16'hABCD),     1'b1);

        @(posedge aclk);
        check_1("H2C load deasserted", h2c_dsc_byp_load, 1'b0);

        // ============================================================
        $display("--- Test 5: H2C GO — load held until ready rises ---");
        // ============================================================
        h2c_dsc_byp_ready = 1'b0;  // drop ready before writing GO

        axil_write(32'h00, 32'hAAAA_AAAA);
        axil_write(32'h04, 32'hBBBB_BBBB);
        axil_write(32'h08, 32'hCCCC_CCCC);
        axil_write(32'h0C, 32'hDDDD_DDDD);
        axil_write(32'h10, 32'h0000_1000);
        axil_write(32'h14, 32'h0000_0001);
        axil_write(32'h18, 32'h0000_0001);  // GO while ready=0

        @(posedge aclk);
        check_1("H2C load low while ready=0", h2c_dsc_byp_load, 1'b0);

        repeat (3) @(posedge aclk);     // hold ready low a few cycles
        h2c_dsc_byp_ready = 1'b1;      // now raise ready

        @(posedge aclk);
        check_1("H2C load fires after ready rises", h2c_dsc_byp_load, 1'b1);
        check_64("H2C src_addr after deferred GO",  h2c_dsc_byp_src_addr,
                 {32'hBBBB_BBBB, 32'hAAAA_AAAA});

        @(posedge aclk);
        check_1("H2C load deasserted",              h2c_dsc_byp_load, 1'b0);

        // ============================================================
        $display("--- Test 6: C2H GO sequence ---");
        // ============================================================
        c2h_dsc_byp_ready = 1'b1;

        axil_write(32'h40, 32'h1111_1111);
        axil_write(32'h44, 32'h2222_2222);
        axil_write(32'h48, 32'h3333_3333);
        axil_write(32'h4C, 32'h4444_4444);
        axil_write(32'h50, 32'h0000_0400);
        axil_write(32'h54, 32'h0000_000F);
        axil_write(32'h58, 32'h0000_0001);  // C2H GO

        @(posedge aclk);
        check_1 ("C2H load asserted",      c2h_dsc_byp_load,     1'b1);
        check_64("C2H src_addr on output", c2h_dsc_byp_src_addr,
                 {32'h2222_2222, 32'h1111_1111});
        check_64("C2H dst_addr on output", c2h_dsc_byp_dst_addr,
                 {32'h4444_4444, 32'h3333_3333});
        check_1 ("C2H len correct",
                 (c2h_dsc_byp_len === 28'h000_0400), 1'b1);
        check_1 ("C2H ctl correct",
                 (c2h_dsc_byp_ctl === 16'h000F),     1'b1);

        @(posedge aclk);
        check_1("C2H load deasserted", c2h_dsc_byp_load, 1'b0);

        // ============================================================
        $display("--- Test 7: Status register tracks ready ---");
        // ============================================================
        h2c_dsc_byp_ready = 1'b0;
        c2h_dsc_byp_ready = 1'b0;
        @(posedge aclk);
        axil_read(32'h1C, rdata); check_reg("H2C status ready=0", rdata, 32'h0);
        axil_read(32'h5C, rdata); check_reg("C2H status ready=0", rdata, 32'h0);

        h2c_dsc_byp_ready = 1'b1;
        c2h_dsc_byp_ready = 1'b1;
        @(posedge aclk);
        axil_read(32'h1C, rdata); check_reg("H2C status ready=1", rdata, 32'h1);
        axil_read(32'h5C, rdata); check_reg("C2H status ready=1", rdata, 32'h1);

        // ============================================================
        $display("--- Test 8: GO register reads back 0 (write-only) ---");
        // ============================================================
        axil_read(32'h18, rdata); check_reg("H2C GO reads 0", rdata, 32'h0);
        axil_read(32'h58, rdata); check_reg("C2H GO reads 0", rdata, 32'h0);

        // ============================================================
        $display("--- Test 9: Write strobe — byte-lane masking ---");
        // ============================================================
        // Seed H2C src_addr_lo with a full-word value
        axil_write(32'h00, 32'hAABB_CCDD);
        axil_read (32'h00, rdata);
        check_reg("strobe seed",              rdata, 32'hAABB_CCDD);

        // strb=0x1: only byte 0 (bits 7:0) updated
        axil_write(32'h00, 32'h1122_3344, 4'h1);
        axil_read (32'h00, rdata);
        check_reg("strb=0x1 byte0 only",      rdata, 32'hAABB_CC44);

        // strb=0xC: only bytes 2-3 (bits 31:16) updated
        axil_write(32'h00, 32'h5566_7788, 4'hC);
        axil_read (32'h00, rdata);
        check_reg("strb=0xC bytes2-3 only",   rdata, 32'h5566_CC44);

        // strb=0x6: only bytes 1-2 (bits 23:8) updated
        axil_write(32'h00, 32'hFFFF_FFFF, 4'h6);
        axil_read (32'h00, rdata);
        check_reg("strb=0x6 bytes1-2 only",   rdata, 32'h55FF_FF44);

        // strb=0xF: full word write
        axil_write(32'h00, 32'h1234_5678, 4'hF);
        axil_read (32'h00, rdata);
        check_reg("strb=0xF full word",        rdata, 32'h1234_5678);

        // Adjacent register must be untouched throughout
        axil_read(32'h04, rdata);
        check_reg("src_addr_hi untouched",     rdata, 32'hBBBB_BBBB);

        // ============================================================
        $display("--- Test 10: H2C and C2H load independently ---");
        // ============================================================
        h2c_dsc_byp_ready = 1'b0;
        c2h_dsc_byp_ready = 1'b0;

        // Write both GO bits while both ready=0
        axil_write(32'h18, 32'h0000_0001);  // H2C GO
        axil_write(32'h58, 32'h0000_0001);  // C2H GO

        @(posedge aclk);
        check_1("H2C load=0 (both ready=0)", h2c_dsc_byp_load, 1'b0);
        check_1("C2H load=0 (both ready=0)", c2h_dsc_byp_load, 1'b0);

        // Release H2C ready only
        h2c_dsc_byp_ready = 1'b1;
        @(posedge aclk);
        check_1("H2C load fires first",   h2c_dsc_byp_load, 1'b1);
        check_1("C2H load still low",     c2h_dsc_byp_load, 1'b0);

        // Release C2H ready one cycle later
        c2h_dsc_byp_ready = 1'b1;
        @(posedge aclk);
        check_1("H2C load cleared",       h2c_dsc_byp_load, 1'b0);
        check_1("C2H load fires second",  c2h_dsc_byp_load, 1'b1);

        @(posedge aclk);
        check_1("C2H load cleared",       c2h_dsc_byp_load, 1'b0);

        // ============================================================
        $display("--- Summary ---");
        // ============================================================
        $display("PASSED: %0d  FAILED: %0d", pass_count, fail_count);
        if (fail_count == 0)
            $display("ALL TESTS PASSED");
        else
            $display("SOME TESTS FAILED");

        $finish;
    end

    // Watchdog — abort if simulation stalls
    initial begin
        #1_000_000;
        $display("TIMEOUT");
        $finish;
    end

endmodule
