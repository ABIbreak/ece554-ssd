// ============================================================
// nand_flash_ctrl_tb.sv
// Testbench: nand_flash_ctrl <-> MX30LF1G28AD behavioral model
// ============================================================
// Tests:
//   1. Reset
//   2. Read Status
//   3. Page Program (write known pattern to page 0)
//   4. Page Read   (read page 0 back, verify data)
//   5. Block Erase (erase block 0)
//   6. Read after erase (verify 0xFF)
// ============================================================

`timescale 1ns/100ps

// Include DUT and behavioral model
`include "nand_flash_ctrl.sv"
`include "MX30LF1G28AD.v"

module nand_flash_ctrl_tb;

    // -------------------------------------------------------
    // Parameters
    // -------------------------------------------------------
    localparam CLK_PERIOD  = 10;      // 100 MHz
    localparam PAGE_BYTES  = 2112;
    localparam TEST_PAGES  = 4;       // only write/read first 4 pages

    // -------------------------------------------------------
    // Clock & reset
    // -------------------------------------------------------
    logic clk  = 0;
    logic rst_n;
    always #(CLK_PERIOD/2) clk = ~clk;

    // -------------------------------------------------------
    // DUT signals
    // -------------------------------------------------------
    logic        op_start;
    logic [2:0]  op_type;
    logic [23:0] row_addr;
    logic [11:0] col_addr;
    logic [7:0]  data_in;
    logic        data_wr;
    logic [7:0]  data_out;
    logic        data_rd;
    logic        busy;
    logic        done;
    logic [7:0]  status;
    logic        fail;

    // NAND physical bus
    logic        nand_ce_n;
    logic        nand_re_n;
    logic        nand_we_n;
    logic        nand_cle;
    logic        nand_ale;
    logic        nand_wp_n;
    logic        nand_ryby_n;
    wire  [7:0]  nand_io;

    // -------------------------------------------------------
    // DUT instantiation
    // -------------------------------------------------------
    nand_flash_ctrl #(
        .CLK_PERIOD_NS (CLK_PERIOD),
        .PAGE_BYTES    (PAGE_BYTES)
    ) dut (
        .clk          (clk),
        .rst_n        (rst_n),
        .op_start_i   (op_start),
        .op_type_i    (op_type),
        .row_addr_i   (row_addr),
        .col_addr_i   (col_addr),
        .data_i       (data_in),
        .data_wr_i    (data_wr),
        .data_o       (data_out),
        .data_rd_o    (data_rd),
        .busy_o       (busy),
        .done_o       (done),
        .status_o     (status),
        .fail_o       (fail),
        .nand_ce_n    (nand_ce_n),
        .nand_re_n    (nand_re_n),
        .nand_we_n    (nand_we_n),
        .nand_cle     (nand_cle),
        .nand_ale     (nand_ale),
        .nand_wp_n    (nand_wp_n),
        .nand_ryby_n  (nand_ryby_n),
        .nand_io      (nand_io)
    );

    // -------------------------------------------------------
    // MX30LF1G28AD behavioral model instantiation
    // -------------------------------------------------------
    MX30LF1G28AD flash (
        .CE_B   (nand_ce_n),
        .RE_B   (nand_re_n),
        .WE_B   (nand_we_n),
        .CLE    (nand_cle),
        .ALE    (nand_ale),
        .WP_B   (nand_wp_n),
        .RYBY_B (nand_ryby_n),
        .PT     (1'b0),        // block protection off
        .IO     (nand_io)
    );

    // -------------------------------------------------------
    // Monitor / checker state
    // -------------------------------------------------------
    int pass_count = 0;
    int fail_count = 0;

    // Buffer to collect read bytes for comparison
    logic [7:0] read_buf  [0:PAGE_BYTES-1];
    logic [7:0] write_buf [0:PAGE_BYTES-1];
    int         read_idx;

    // -------------------------------------------------------
    // Capture read data as it streams out
    // -------------------------------------------------------
    always_ff @(posedge clk) begin
        if (data_rd) begin
            if (read_idx < PAGE_BYTES) begin
                read_buf[read_idx] <= data_out;
                read_idx <= read_idx + 1;
            end
        end
    end

    // -------------------------------------------------------
    // Helper tasks
    // -------------------------------------------------------

    // Wait for done pulse
    task automatic wait_done;
        @(posedge clk iff done);
        @(posedge clk);
    endtask

    // Issue a single-cycle op_start pulse
    task automatic start_op(
        input [2:0]  t,
        input [23:0] row,
        input [11:0] col
    );
        @(posedge clk);
        op_start <= 1;
        op_type  <= t;
        row_addr <= row;
        col_addr <= col;
        @(posedge clk);
        op_start <= 0;
    endtask

    // Check and report
    task automatic check(
        input string   name,
        input logic [7:0] got,
        input logic [7:0] expected
    );
        if (got === expected) begin
            $display("  PASS  %s | got=0x%02h", name, got);
            pass_count++;
        end else begin
            $display("  FAIL  %s | got=0x%02h expected=0x%02h", name, got, expected);
            fail_count++;
        end
    endtask

    task automatic report;
        $display("\n========================================");
        $display("  Results: %0d passed, %0d failed", pass_count, fail_count);
        $display("========================================\n");
    endtask

    // -------------------------------------------------------
    // Main test sequence
    // -------------------------------------------------------
    initial begin
        // Init
        op_start  = 0;
        op_type   = 0;
        row_addr  = 0;
        col_addr  = 0;
        data_in   = 0;
        data_wr   = 0;
        read_idx  = 0;

        // Reset
        rst_n = 0;
        repeat(4) @(posedge clk);
        rst_n = 1;

        // Wait for flash power-up (Tvcs = 5ms)
        $display("Waiting for flash power-up (Tvcs = 5ms sim time)...");
        #5_000_100;  // slightly more than Tvcs=5_000_000 ns
        $display("Flash ready.\n");

        // ====================================================
        // TEST 1: RESET
        // ====================================================
        $display("=== TEST 1: Reset ===");
        start_op(3'b000, 0, 0);
        wait_done();
        $display("  Reset complete.\n");

        // ====================================================
        // TEST 2: READ STATUS
        // ====================================================
        $display("=== TEST 2: Read Status ===");
        start_op(3'b100, 0, 0);
        wait_done();
        // After reset, SR[6]=1 (ready), SR[5]=1, SR[0]=0 (no fail)
        check("STATUS[6] ready", status[6], 1'b1);
        check("STATUS[0] no fail", status[0], 1'b0);
        $display("");

        // ====================================================
        // TEST 3: PAGE PROGRAM (page 0, column 0)
        // ====================================================
        $display("=== TEST 3: Page Program (page 0) ===");

        // Fill write buffer with a simple pattern: byte[i] = i & 0xFF
        for (int i = 0; i < PAGE_BYTES; i++)
            write_buf[i] = i[7:0];

        // Start program op
        start_op(3'b010, 24'h000000, 12'h000);

        // Feed data bytes when controller is in S_PROG_DATA_WRITE
        // Wait for tADL to pass (controller goes busy then waits)
        // We poll busy and feed when the controller is ready for data
        @(posedge clk iff busy);
        // tADL wait in controller — just feed on every clock after that
        // Controller samples data_wr each cycle
        repeat(10) @(posedge clk);   // let tADL pass

        for (int i = 0; i < PAGE_BYTES; i++) begin
            @(posedge clk);
            data_in <= write_buf[i];
            data_wr <= 1;
            @(posedge clk);
            data_wr <= 0;
            // Give controller one cycle to latch WE#
            repeat(2) @(posedge clk);
        end
        data_wr <= 0;

        wait_done();
        check("PROG fail bit", fail, 1'b0);
        $display("");

        // ====================================================
        // TEST 4: PAGE READ (page 0, column 0)
        // ====================================================
        $display("=== TEST 4: Page Read (page 0) ===");
        read_idx = 0;
        start_op(3'b001, 24'h000000, 12'h000);
        wait_done();

        // Verify first 16 bytes of read data against write pattern
        $display("  Checking first 16 bytes...");
        for (int i = 0; i < 16; i++) begin
            check($sformatf("byte[%0d]", i), read_buf[i], write_buf[i]);
        end
        // Spot check middle
        check("byte[255]", read_buf[255], write_buf[255]);
        check("byte[1023]", read_buf[1023], write_buf[1023]);
        $display("");

        // ====================================================
        // TEST 5: BLOCK ERASE (block 0)
        // ====================================================
        $display("=== TEST 5: Block Erase (block 0) ===");
        // Row address for block 0 = 0x000000
        // Erase uses only row addr bits, column ignored
        start_op(3'b011, 24'h000000, 12'h000);
        wait_done();
        check("ERASE fail bit", fail, 1'b0);
        $display("");

        // Read status after erase
        start_op(3'b100, 0, 0);
        wait_done();
        check("POST-ERASE STATUS[6]", status[6], 1'b1);
        check("POST-ERASE STATUS[0]", status[0], 1'b0);

        // ====================================================
        // TEST 6: READ after ERASE (should be 0xFF)
        // ====================================================
        $display("\n=== TEST 6: Read after erase (expect 0xFF) ===");
        read_idx = 0;
        start_op(3'b001, 24'h000000, 12'h000);
        wait_done();

        $display("  Checking first 16 bytes after erase...");
        for (int i = 0; i < 16; i++) begin
            check($sformatf("erased byte[%0d]", i), read_buf[i], 8'hFF);
        end

        // ====================================================
        // Done
        // ====================================================
        repeat(10) @(posedge clk);
        report();
        $finish;
    end

    // -------------------------------------------------------
    // Timeout watchdog — erase takes 4ms, give plenty of room
    // -------------------------------------------------------
    initial begin
        #50_000_000;
        $display("TIMEOUT");
        $finish;
    end

    // -------------------------------------------------------
    // Waveform dump
    // -------------------------------------------------------
    initial begin
        $dumpfile("nand_flash_ctrl_tb.vcd");
        $dumpvars(0, nand_flash_ctrl_tb);
    end

endmodule