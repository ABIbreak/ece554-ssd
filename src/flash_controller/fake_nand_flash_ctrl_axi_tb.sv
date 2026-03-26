// ============================================================
// nand_flash_ctrl_axi_tb.sv
// AXI-Lite testbench for nand_flash_ctrl_axi
// ============================================================
// All flash operations are driven purely through AXI-Lite
// register writes, mirroring how MicroBlaze firmware would
// talk to the controller.
//
// Test sequence:
//   1. Reset chip via AXI-Lite
//   2. Read status register — verify not busy
//   3. Program page 0 via AXI-Lite START
//   4. Poll STATUS.busy via AXI-Lite until done
//   5. Read page 0 back, verify data
//   6. Erase block 0 via AXI-Lite
//   7. Poll until done, verify STATUS.fail = 0
// ============================================================

`timescale 1ns/100ps

`include "nand_flash_ctrl.sv"
`include "nand_flash_ctrl_axi.sv"
`include "MX30LF1G28AD.v"

module fake_nand_flash_ctrl_axi_tb;

    // -------------------------------------------------------
    // Parameters
    // -------------------------------------------------------
    localparam CLK_PERIOD = 10;
    localparam PAGE_BYTES = 2112;

    // Register offsets
    localparam ADDR_FLASH_ADDR = 5'h00;
    localparam ADDR_COL_ADDR   = 5'h04;
    localparam ADDR_OPERATION  = 5'h08;
    localparam ADDR_START      = 5'h0C;
    localparam ADDR_STATUS     = 5'h10;
    localparam ADDR_POLL_ADDR  = 5'h14;

    // Operation codes
    localparam OP_RESET  = 32'h0;
    localparam OP_READ   = 32'h1;
    localparam OP_PROG   = 32'h2;
    localparam OP_ERASE  = 32'h3;
    localparam OP_STATUS = 32'h4;

    // STATUS register bits
    localparam STATUS_BUSY = 32'h1;
    localparam STATUS_DONE = 32'h2;
    localparam STATUS_FAIL = 32'h4;

    // -------------------------------------------------------
    // Clock & reset
    // -------------------------------------------------------
    logic clk = 0;
    logic rst_n;
    always #(CLK_PERIOD/2) clk = ~clk;

    // -------------------------------------------------------
    // AXI-Lite signals
    // -------------------------------------------------------
    logic [4:0]  axil_awaddr;
    logic        axil_awvalid;
    logic        axil_awready;
    logic [31:0] axil_wdata;
    logic [3:0]  axil_wstrb;
    logic        axil_wvalid;
    logic        axil_wready;
    logic [1:0]  axil_bresp;
    logic        axil_bvalid;
    logic        axil_bready;
    logic [4:0]  axil_araddr;
    logic        axil_arvalid;
    logic        axil_arready;
    logic [31:0] axil_rdata;
    logic [1:0]  axil_rresp;
    logic        axil_rvalid;
    logic        axil_rready;

    // -------------------------------------------------------
    // Data plane signals (bypass — driven directly for now)
    // -------------------------------------------------------
    logic [7:0]  data_in;
    logic        data_wr;
    logic [7:0]  data_out;
    logic        data_rd;

    // -------------------------------------------------------
    // NAND physical bus
    // -------------------------------------------------------
    logic        nand_ce_n, nand_re_n, nand_we_n;
    logic        nand_cle, nand_ale, nand_wp_n;
    logic        nand_ryby_n;
    wire  [7:0]  nand_io;

    // -------------------------------------------------------
    // DUT
    // -------------------------------------------------------
    nand_flash_ctrl_axi #(
        .CLK_PERIOD_NS (CLK_PERIOD),
        .PAGE_BYTES    (PAGE_BYTES)
    ) dut (
        .clk            (clk),
        .rst_n          (rst_n),
        .s_axil_awaddr  (axil_awaddr),
        .s_axil_awvalid (axil_awvalid),
        .s_axil_awready (axil_awready),
        .s_axil_wdata   (axil_wdata),
        .s_axil_wstrb   (axil_wstrb),
        .s_axil_wvalid  (axil_wvalid),
        .s_axil_wready  (axil_wready),
        .s_axil_bresp   (axil_bresp),
        .s_axil_bvalid  (axil_bvalid),
        .s_axil_bready  (axil_bready),
        .s_axil_araddr  (axil_araddr),
        .s_axil_arvalid (axil_arvalid),
        .s_axil_arready (axil_arready),
        .s_axil_rdata   (axil_rdata),
        .s_axil_rresp   (axil_rresp),
        .s_axil_rvalid  (axil_rvalid),
        .s_axil_rready  (axil_rready),
        .data_i         (data_in),
        .data_wr_i      (data_wr),
        .data_o         (data_out),
        .data_rd_o      (data_rd),
        .nand_ce_n      (nand_ce_n),
        .nand_re_n      (nand_re_n),
        .nand_we_n      (nand_we_n),
        .nand_cle       (nand_cle),
        .nand_ale       (nand_ale),
        .nand_wp_n      (nand_wp_n),
        .nand_ryby_n    (nand_ryby_n),
        .nand_io        (nand_io)
    );

    // -------------------------------------------------------
    // Flash behavioral model
    // -------------------------------------------------------
    MX30LF1G28AD flash (
        .CE_B   (nand_ce_n),
        .RE_B   (nand_re_n),
        .WE_B   (nand_we_n),
        .CLE    (nand_cle),
        .ALE    (nand_ale),
        .WP_B   (nand_wp_n),
        .RYBY_B (nand_ryby_n),
        .PT     (1'b0),
        .IO     (nand_io)
    );

    // -------------------------------------------------------
    // AXI-Lite Driver class
    // -------------------------------------------------------
    class axil_driver;

        // ---- Single register write ----------------------
        task write(input logic [4:0] addr, input logic [31:0] data);
            // Write address
            @(posedge clk);
            axil_awaddr  <= addr;
            axil_awvalid <= 1;
            axil_wdata   <= data;
            axil_wstrb   <= 4'hF;
            axil_wvalid  <= 1;

            // Wait for both channels accepted
            fork
                begin do @(posedge clk); while (!axil_awready); axil_awvalid <= 0; end
                begin do @(posedge clk); while (!axil_wready);  axil_wvalid  <= 0; end
            join

            // Wait for write response
            axil_bready <= 1;
            do @(posedge clk); while (!axil_bvalid);
            axil_bready <= 0;
        endtask

        // ---- Single register read -----------------------
        task read(input logic [4:0] addr, output logic [31:0] data);
            @(posedge clk);
            axil_araddr  <= addr;
            axil_arvalid <= 1;

            do @(posedge clk); while (!axil_arready);
            axil_arvalid <= 0;

            axil_rready <= 1;
            do @(posedge clk); while (!axil_rvalid);
            data = axil_rdata;
            axil_rready <= 0;
        endtask

        // ---- Poll STATUS until busy clears --------------
        task poll_until_done(output logic [31:0] final_status);
            logic [31:0] s;
            do begin
                read(ADDR_STATUS, s);
                @(posedge clk);
            end while (s & STATUS_BUSY);
            final_status = s;
        endtask

        // ---- Start a flash operation via AXI-Lite -------
        task start_flash_op(
            input logic [2:0]  op,
            input logic [23:0] row,
            input logic [11:0] col
        );
            write(ADDR_FLASH_ADDR, {8'h0, row});
            write(ADDR_COL_ADDR,   {20'h0, col});
            write(ADDR_OPERATION,  {29'h0, op});
            write(ADDR_START,      32'h1);      // kick off FSM
        endtask

    endclass

    // -------------------------------------------------------
    // Monitor
    // -------------------------------------------------------
    int pass_count = 0;
    int fail_count = 0;

    task automatic check(
        input string      name,
        input logic [31:0] got,
        input logic [31:0] expected
    );
        if (got === expected) begin
            $display("  PASS  %s | got=0x%08h", name, got);
            pass_count++;
        end else begin
            $display("  FAIL  %s | got=0x%08h  expected=0x%08h", name, got, expected);
            fail_count++;
        end
    endtask

    task automatic report;
        $display("\n========================================");
        $display("  Results: %0d passed, %0d failed", pass_count, fail_count);
        $display("========================================\n");
    endtask

    // -------------------------------------------------------
    // Read data capture
    // -------------------------------------------------------
    logic [7:0] read_buf [0:PAGE_BYTES-1];
    logic [7:0] write_buf[0:PAGE_BYTES-1];
    int         read_idx = 0;

    always_ff @(posedge clk) begin
        if (data_rd) begin
            if (read_idx < PAGE_BYTES)
                read_buf[read_idx++] <= data_out;
        end
    end

    // -------------------------------------------------------
    // Main test
    // -------------------------------------------------------
    initial begin
        automatic axil_driver drv = new();
        automatic logic [31:0] status;

        // Init bus signals
        axil_awvalid = 0; axil_wvalid  = 0; axil_bready  = 0;
        axil_arvalid = 0; axil_rready  = 0;
        axil_awaddr  = 0; axil_araddr  = 0;
        axil_wdata   = 0; axil_wstrb   = 0;
        data_in      = 0; data_wr      = 0;

        // Reset
        rst_n = 0;
        repeat(4) @(posedge clk);
        rst_n = 1;

        // Flash power-up wait (Tvcs = 5ms)
        $display("Waiting for flash power-up...");
        #5_000_100;
        $display("Flash ready.\n");

        // ================================================
        // TEST 1: Verify register read/write via AXI-Lite
        // ================================================
        $display("=== TEST 1: AXI-Lite Register R/W ===");

        drv.write(ADDR_FLASH_ADDR, 32'h00AABBCC);
        drv.read (ADDR_FLASH_ADDR, status);
        check("FLASH_ADDR write/read", status, 32'h00AABBCC);

        drv.write(ADDR_COL_ADDR, 32'h00000ABC);
        drv.read (ADDR_COL_ADDR, status);
        check("COL_ADDR write/read", status, 32'h00000ABC);

        drv.write(ADDR_OPERATION, 32'h00000002);
        drv.read (ADDR_OPERATION, status);
        check("OPERATION write/read", status, 32'h00000002);

        // START is WO — reads back 0
        drv.read(ADDR_START, status);
        check("START reads 0 (WO)", status, 32'h0);

        $display("");

        // ================================================
        // TEST 2: Reset via AXI-Lite
        // ================================================
        $display("=== TEST 2: Flash Reset via AXI-Lite ===");
        drv.start_flash_op(3'(OP_RESET), 24'h0, 12'h0);
        drv.poll_until_done(status);
        check("RESET no fail", status & STATUS_FAIL, 32'h0);
        $display("");

        // ================================================
        // TEST 3: Read STATUS register after reset
        // ================================================
        $display("=== TEST 3: Read Status via AXI-Lite ===");
        drv.start_flash_op(3'(OP_STATUS), 24'h0, 12'h0);
        drv.poll_until_done(status);
        check("STATUS op no fail", status & STATUS_FAIL, 32'h0);
        $display("");

        // ================================================
        // TEST 4: Page Program (page 0) via AXI-Lite
        // ================================================
        $display("=== TEST 4: Page Program via AXI-Lite ===");

        // Fill write buffer: byte[i] = i & 0xFF
        for (int i = 0; i < PAGE_BYTES; i++)
            write_buf[i] = i[7:0];

        // Set up and start the program operation
        drv.start_flash_op(3'(OP_PROG), 24'h000000, 12'h000);

        // Wait for controller to enter data phase (tADL delay)
        // then feed page data byte by byte
        @(posedge clk iff dut.u_fsm.busy_o);
        repeat(12) @(posedge clk);   // tADL passes inside FSM

        for (int i = 0; i < PAGE_BYTES; i++) begin
            @(posedge clk);
            data_in <= write_buf[i];
            data_wr <= 1;
            @(posedge clk);
            data_wr <= 0;
            repeat(2) @(posedge clk);
        end
        data_wr <= 0;

        // Poll STATUS via AXI-Lite until not busy
        drv.poll_until_done(status);
        check("PROG no fail", status & STATUS_FAIL, 32'h0);
        $display("");

        // ================================================
        // TEST 5: Page Read (page 0) via AXI-Lite
        // ================================================
        $display("=== TEST 5: Page Read via AXI-Lite ===");
        read_idx = 0;
        drv.start_flash_op(3'(OP_READ), 24'h000000, 12'h000);
        drv.poll_until_done(status);
        check("READ no fail", status & STATUS_FAIL, 32'h0);

        // Verify first 16 bytes
        $display("  Checking first 16 bytes...");
        for (int i = 0; i < 16; i++)
            check($sformatf("byte[%0d]", i), {24'h0, read_buf[i]}, {24'h0, write_buf[i]});

        // Spot checks
        check("byte[255]",  {24'h0, read_buf[255]},  {24'h0, write_buf[255]});
        check("byte[1023]", {24'h0, read_buf[1023]}, {24'h0, write_buf[1023]});
        $display("");

        // ================================================
        // TEST 6: Block Erase via AXI-Lite
        // ================================================
        $display("=== TEST 6: Block Erase via AXI-Lite ===");
        drv.start_flash_op(3'(OP_ERASE), 24'h000000, 12'h000);
        drv.poll_until_done(status);
        check("ERASE no fail", status & STATUS_FAIL, 32'h0);
        $display("");

        // ================================================
        // TEST 7: Read after erase — expect 0xFF
        // ================================================
        $display("=== TEST 7: Read after erase (expect 0xFF) ===");
        read_idx = 0;
        drv.start_flash_op(3'(OP_READ), 24'h000000, 12'h000);
        drv.poll_until_done(status);

        for (int i = 0; i < 16; i++)
            check($sformatf("erased[%0d]", i), {24'h0, read_buf[i]}, 32'hFF);

        // ================================================
        // Done
        // ================================================
        repeat(10) @(posedge clk);
        report();
        $finish;
    end

    // Timeout watchdog
    initial begin
        #50_000_000;
        $display("TIMEOUT");
        $finish;
    end

    // Waveform dump
    initial begin
        $dumpfile("nand_flash_ctrl_axi_tb.vcd");
        $dumpvars(0, nand_flash_ctrl_axi_tb);
    end

endmodule