// ============================================================
// flash_controller_top_tb_inject.sv
// Injected signal testbench — no real flash model
// ============================================================
// All NAND signals are driven by the testbench directly.
// This lets you test the full data path (AXI-S → deserializer
// → FIFO → scrambler → FSM → descrambler → FIFO → serializer)
// without waiting for real flash timing (ms erase, µs program).
//
// The testbench acts as a fake flash chip:
//   - Monitors nand_cle/ale/we_n to detect commands/addresses
//   - Drives nand_ryby_n low then high to simulate busy/ready
//   - Drives nand_io with known data during read cycles
//
// Tests:
//   1. AXI-Lite register read/write
//   2. Write path: AXI-S → through pipeline → fake flash write
//   3. Read path:  fake flash read → through pipeline → AXI-S
//   4. Round trip: write then read back, verify data matches
//   5. Scrambling: verify data on NAND bus differs from input
// ============================================================

`timescale 1ns/1ps

`include "flash_controller_top.sv"

module flash_controller_top_tb_inject;

    localparam CLK_PERIOD = 10;
    localparam PAGE_BYTES = 2112;
    localparam PAGE_BEATS = PAGE_BYTES / 4;  // 528

    // Register addresses
    localparam ADDR_FLASH_ADDR = 5'h00;
    localparam ADDR_COL_ADDR   = 5'h04;
    localparam ADDR_OPERATION  = 5'h08;
    localparam ADDR_START      = 5'h0C;
    localparam ADDR_STATUS     = 5'h10;
    localparam ADDR_POLL_ADDR  = 5'h14;
    localparam ADDR_LBA        = 5'h18;

    localparam OP_RESET  = 3'd0;
    localparam OP_READ   = 3'd1;
    localparam OP_PROG   = 3'd2;
    localparam OP_ERASE  = 3'd3;
    localparam OP_STATUS = 3'd4;

    localparam STATUS_BUSY = 32'h1;
    localparam STATUS_DONE = 32'h2;
    localparam STATUS_FAIL = 32'h4;

    // -------------------------------------------------------
    // Clock
    // -------------------------------------------------------
    logic clk = 0;
    logic rst_n;
    always #(CLK_PERIOD/2) clk = ~clk;

    // -------------------------------------------------------
    // DUT signals
    // -------------------------------------------------------
    // AXI-Lite
    logic [4:0]  axil_awaddr;  logic axil_awvalid; logic axil_awready;
    logic [31:0] axil_wdata;   logic [3:0] axil_wstrb;
    logic        axil_wvalid;  logic axil_wready;
    logic [1:0]  axil_bresp;   logic axil_bvalid;  logic axil_bready;
    logic [4:0]  axil_araddr;  logic axil_arvalid; logic axil_arready;
    logic [31:0] axil_rdata;   logic [1:0] axil_rresp;
    logic        axil_rvalid;  logic axil_rready;

    // AXI-Stream write (TB drives this)
    logic [31:0] s_axis_tdata;  logic s_axis_tvalid;
    logic        s_axis_tready; logic s_axis_tlast;

    // AXI-Stream read (TB receives this)
    logic [31:0] m_axis_tdata;  logic m_axis_tvalid;
    logic        m_axis_tready; logic m_axis_tlast;

    // NAND physical (TB acts as fake flash)
    logic        nand_ce_n, nand_re_n, nand_we_n;
    logic        nand_cle, nand_ale, nand_wp_n;
    logic        nand_ryby_n;
    wire  [7:0]  nand_io;

    // TB drives nand_io during reads
    logic [7:0]  nand_io_drive;
    logic        nand_io_oe;
    assign nand_io = nand_io_oe ? nand_io_drive : 8'bz;

    // -------------------------------------------------------
    // DUT
    // -------------------------------------------------------
    flash_controller_top #(
        .CLK_PERIOD_NS (CLK_PERIOD),
        .PAGE_BYTES    (PAGE_BYTES)
    ) dut (
        .clk            (clk),         .rst_n          (rst_n),
        .s_axil_awaddr  (axil_awaddr),  .s_axil_awvalid (axil_awvalid),
        .s_axil_awready (axil_awready), .s_axil_wdata   (axil_wdata),
        .s_axil_wstrb   (axil_wstrb),   .s_axil_wvalid  (axil_wvalid),
        .s_axil_wready  (axil_wready),  .s_axil_bresp   (axil_bresp),
        .s_axil_bvalid  (axil_bvalid),  .s_axil_bready  (axil_bready),
        .s_axil_araddr  (axil_araddr),  .s_axil_arvalid (axil_arvalid),
        .s_axil_arready (axil_arready), .s_axil_rdata   (axil_rdata),
        .s_axil_rresp   (axil_rresp),   .s_axil_rvalid  (axil_rvalid),
        .s_axil_rready  (axil_rready),
        .s_axis_tdata   (s_axis_tdata), .s_axis_tvalid  (s_axis_tvalid),
        .s_axis_tready  (s_axis_tready),.s_axis_tlast   (s_axis_tlast),
        .m_axis_tdata   (m_axis_tdata), .m_axis_tvalid  (m_axis_tvalid),
        .m_axis_tready  (m_axis_tready),.m_axis_tlast   (m_axis_tlast),
        .nand_ce_n      (nand_ce_n),    .nand_re_n      (nand_re_n),
        .nand_we_n      (nand_we_n),    .nand_cle       (nand_cle),
        .nand_ale       (nand_ale),     .nand_wp_n      (nand_wp_n),
        .nand_ryby_n    (nand_ryby_n),  .nand_io        (nand_io)
    );

    // -------------------------------------------------------
    // Checker
    // -------------------------------------------------------
    int pass_count = 0;
    int fail_count = 0;

    task automatic check(input string n, input logic [31:0] g, input logic [31:0] e);
        if (g === e) begin $display("  PASS  %s", n); pass_count++; end
        else begin $display("  FAIL  %s | got=0x%08h exp=0x%08h", n, g, e); fail_count++; end
    endtask
    task automatic check_flag(input string n, input logic g, input logic e);
        if (g === e) begin $display("  PASS  %s", n); pass_count++; end
        else begin $display("  FAIL  %s | got=%0b exp=%0b", n, g, e); fail_count++; end
    endtask

    // -------------------------------------------------------
    // AXI-Lite driver tasks
    // -------------------------------------------------------
    task automatic axil_write(input logic [4:0] addr, input logic [31:0] data);
        @(posedge clk);
        axil_awaddr <= addr; axil_awvalid <= 1;
        axil_wdata  <= data; axil_wstrb   <= 4'hF; axil_wvalid <= 1;
        fork
            begin do @(posedge clk); while (!axil_awready); axil_awvalid <= 0; end
            begin do @(posedge clk); while (!axil_wready);  axil_wvalid  <= 0; end
        join
        axil_bready <= 1;
        do @(posedge clk); while (!axil_bvalid);
        axil_bready <= 0;
    endtask

    task automatic axil_read(input logic [4:0] addr, output logic [31:0] data);
        @(posedge clk);
        axil_araddr <= addr; axil_arvalid <= 1;
        do @(posedge clk); while (!axil_arready);
        axil_arvalid <= 0;
        axil_rready  <= 1;
        do @(posedge clk); while (!axil_rvalid);
        data = axil_rdata;
        axil_rready <= 0;
    endtask

    task automatic axil_poll_done(output logic [31:0] status);
        logic [31:0] s;
        do begin axil_read(ADDR_STATUS, s); @(posedge clk); end
        while (s & STATUS_BUSY);
        status = s;
    endtask

    task automatic start_op(
        input logic [2:0]  op,
        input logic [23:0] row,
        input logic [11:0] col,
        input logic [23:0] lba
    );
        axil_write(ADDR_FLASH_ADDR, {8'h0, row});
        axil_write(ADDR_COL_ADDR,   {20'h0, col});
        axil_write(ADDR_LBA,        {8'h0, lba});
        axil_write(ADDR_OPERATION,  {29'h0, op});
        axil_write(ADDR_START,      32'h1);
    endtask

    // -------------------------------------------------------
    // Fake flash — responds to NAND signals
    // -------------------------------------------------------
    logic [7:0] fake_flash_mem [0:PAGE_BYTES-1];  // fake page storage
    logic [7:0] nand_io_cap    [0:PAGE_BYTES-1];  // captured write bytes

    // Captures bytes written to the fake flash on WE# rising edges
    int wr_capture_idx = 0;
    logic capturing_write = 0;

    always @(posedge nand_we_n) begin
        if (!nand_ce_n && !nand_cle && !nand_ale && capturing_write) begin
            if (wr_capture_idx < PAGE_BYTES) begin
                nand_io_cap[wr_capture_idx] = nand_io;
                wr_capture_idx = wr_capture_idx + 1;
            end
        end
    end

    // Fake flash R/B# and read data — driven by tasks below
    initial nand_ryby_n = 1;
    initial nand_io_oe  = 0;
    initial nand_io_drive = 0;

    // Task: simulate flash busy then ready
    task automatic fake_busy(input int busy_ns);
        nand_ryby_n = 0;
        #busy_ns;
        nand_ryby_n = 1;
    endtask

    // Task: drive read data out when RE# is toggled
    task automatic fake_drive_read_data;
        int byte_idx = 0;
        nand_io_oe = 1;
        while (byte_idx < PAGE_BYTES) begin
            @(negedge nand_re_n);
            nand_io_drive = fake_flash_mem[byte_idx++];
        end
        nand_io_oe = 0;
    endtask

    // -------------------------------------------------------
    // AXI-Stream write sender (TB → DUT)
    // -------------------------------------------------------
    logic [7:0] write_buf [0:PAGE_BYTES-1];
    logic [7:0] read_buf  [0:PAGE_BYTES-1];

    task automatic send_axis_page(input logic [7:0] page_buf [0:PAGE_BYTES-1]);
        for (int i = 0; i < PAGE_BEATS; i++) begin
            @(posedge clk);
            s_axis_tdata  <= {page_buf[i*4+3], page_buf[i*4+2], page_buf[i*4+1], page_buf[i*4]};
            s_axis_tvalid <= 1;
            s_axis_tlast  <= (i == PAGE_BEATS-1);
            do @(posedge clk); while (!s_axis_tready);
        end
        s_axis_tvalid <= 0;
        s_axis_tlast  <= 0;
    endtask

    // AXI-Stream read receiver (DUT → TB)
    int recv_idx = 0;
    always @(posedge clk) begin
        if (m_axis_tvalid && m_axis_tready) begin
            if (recv_idx < PAGE_BEATS) begin
                read_buf[recv_idx*4+0] = m_axis_tdata[7:0];
                read_buf[recv_idx*4+1] = m_axis_tdata[15:8];
                read_buf[recv_idx*4+2] = m_axis_tdata[23:16];
                read_buf[recv_idx*4+3] = m_axis_tdata[31:24];
                recv_idx = recv_idx + 1;
            end
        end
    end

    // -------------------------------------------------------
    // Main test
    // -------------------------------------------------------
    initial begin
        // Declarations must come first in Questa 2020
        automatic logic [31:0] tb_status;
        automatic int          tb_errors;
        automatic int          tb_same_count;

        // Init
        axil_awvalid=0; axil_wvalid=0; axil_bready=0;
        axil_arvalid=0; axil_rready=0;
        s_axis_tvalid=0; s_axis_tlast=0; s_axis_tdata=0;
        m_axis_tready=1;

        rst_n = 0;
        repeat(4) @(posedge clk);
        rst_n = 1;
        repeat(2) @(posedge clk);

        // Fill write buffer with known pattern
        for (int i = 0; i < PAGE_BYTES; i++)
            write_buf[i] = i[7:0];

        // Fill fake flash with 0xFF (erased state)
        for (int i = 0; i < PAGE_BYTES; i++)
            fake_flash_mem[i] = 8'hFF;

        // ================================================
        // TEST 1: AXI-Lite register R/W
        // ================================================
        $display("\n=== TEST 1: AXI-Lite Register R/W ===");
        begin
            logic [31:0] rd;
            axil_write(ADDR_FLASH_ADDR, 32'h00ABCDEF);
            axil_read (ADDR_FLASH_ADDR, rd);
            check("FLASH_ADDR", rd, 32'h00ABCDEF);

            axil_write(ADDR_LBA, 32'h00001234);
            axil_read (ADDR_LBA, rd);
            check("LBA reg", rd, 32'h00001234);

            axil_write(ADDR_OPERATION, 32'h2);
            axil_read (ADDR_OPERATION, rd);
            check("OPERATION", rd, 32'h2);

            axil_read(ADDR_START, rd);
            check("START reads 0 (WO)", rd, 32'h0);
        end

        // ================================================
        // TEST 2: Reset operation (injected R/B#)
        // ================================================
        $display("\n=== TEST 2: Reset (injected) ===");
        begin
            fork
                start_op(OP_RESET, 24'h0, 12'h0, 24'h0);
                begin repeat(5) @(posedge clk); fake_busy(500); end
            join
            axil_poll_done(tb_status);
            check("RESET no fail", tb_status & STATUS_FAIL, 32'h0);
        end

        // ================================================
        // TEST 3: Write path — AXI-S → pipeline → fake flash
        //         Verify scrambled bytes land on NAND bus
        // ================================================
        $display("\n=== TEST 3: Write path with scrambling ===");
        begin
            wr_capture_idx  = 0;
            capturing_write = 1;

            // Start program op and send AXI-S data concurrently
            // (data must be flowing when FSM enters data phase)
            fork : prog_data
                send_axis_page(write_buf);
                begin
                    repeat(3) @(posedge clk);
                    start_op(OP_PROG, 24'h000000, 12'h000, 24'h00002A);
                end
            join_any
            // Wait for both to finish
            wait fork;
            // After enough WE# pulses for cmd+addr+data+confirm, go busy then ready.
            // We use a simple approach: wait for nand_ce_n to go low, then after
            // a fixed number of WE# pulses (command + 5 addr + page data + confirm)
            // assert busy briefly then release.
            fork : fake_flash_prog
                begin
                    // Wait for CE# to assert (transaction starts)
                    @(negedge nand_ce_n);
                    // Wait for program confirm (0x10) — it comes after
                    // 1 cmd + 5 addr + PAGE_BYTES data beats + 1 confirm
                    // Rather than count beats, just wait for CE# to go high
                    // (FSM deasserts CE# only after done) — use a generous delay
                    // that covers the address + data phase
                    #((PAGE_BYTES * 4 * CLK_PERIOD) + 500);  // data phase + margin
                    // Now assert busy to simulate flash programming
                    nand_ryby_n = 0;
                    #5000;   // 5µs fake program time
                    nand_ryby_n = 1;
                end
                begin
                    // Safety timeout for this thread
                    #9_000_000;
                end
            join_any
            disable fake_flash_prog;

            capturing_write = 0;
            axil_poll_done(tb_status);
            check("PROG no fail", tb_status & STATUS_FAIL, 32'h0);

            // Verify scrambling — captured bytes should differ from input
            tb_same_count = 0;
            for (int i = 0; i < PAGE_BYTES; i++)
                if (nand_io_cap[i] === write_buf[i]) tb_same_count++;
            if (tb_same_count < PAGE_BYTES / 4)
                $display("  PASS  Data was scrambled (%0d/%0d bytes unchanged)",
                         tb_same_count, PAGE_BYTES);
            else begin
                $display("  FAIL  Data appears unscrambled (%0d/%0d same)",
                         tb_same_count, PAGE_BYTES);
                fail_count++;
            end

            // Save scrambled bytes as what flash would store
            for (int i = 0; i < PAGE_BYTES; i++)
                fake_flash_mem[i] = nand_io_cap[i];
        end

        // ================================================
        // TEST 4: Read path — fake flash → pipeline → AXI-S
        // ================================================
        $display("\n=== TEST 4: Read path with descrambling ===");
        begin
            recv_idx      = 0;
            m_axis_tready = 1;

            // Start the read op
            start_op(OP_READ, 24'h000000, 12'h000, 24'h00002A);

            // Fake flash response: wait for CE# low (FSM started),
            // then simulate page load busy time, then drive read data
            @(negedge nand_ce_n);
            nand_ryby_n = 0;       // go busy (loading page from array)
            #2000;                 // 2µs fake page load
            nand_ryby_n = 1;       // ready — FSM will now start clocking RE#

            // Drive read bytes as RE# toggles
            fake_drive_read_data();

            axil_poll_done(tb_status);
            check("READ no fail", tb_status & STATUS_FAIL, 32'h0);

            @(posedge clk iff m_axis_tlast);
            repeat(4) @(posedge clk);

            tb_errors = 0;
            for (int i = 0; i < PAGE_BYTES; i++) begin
                if (read_buf[i] !== write_buf[i]) begin
                    if (tb_errors < 4)
                        $display("  byte[%0d] got=0x%02h exp=0x%02h",
                                 i, read_buf[i], write_buf[i]);
                    if (tb_errors > 2000)
                        $display("  byte[%0d] got=0x%02h exp=0x%02h",
                                 i, read_buf[i], write_buf[i]);
                    tb_errors++;
                end
            end
            if (tb_errors == 0)
                $display("  PASS  All %0d bytes recovered correctly after descramble",
                         PAGE_BYTES);
            else begin
                $display("  FAIL  %0d bytes mismatched after round trip", tb_errors);
                fail_count++;
            end
        end

        // ================================================
        // Summary
        // ================================================
        repeat(4) @(posedge clk);
        $display("\n========================================");
        $display("  Results: %0d passed, %0d failed", pass_count, fail_count);
        $display("========================================\n");
        $finish;
    end

    initial begin #25_000_000; $display("TIMEOUT"); $finish; end
    initial begin
        $dumpfile("flash_controller_inject.vcd");
        $dumpvars(0, flash_controller_top_tb_inject);
    end

endmodule