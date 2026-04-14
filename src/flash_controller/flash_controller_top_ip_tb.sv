// ============================================================
// flash_controller_top_ip_tb.sv
// Real flash model testbench — uses MX30LF1G28AD behavioral model
// ============================================================
// Connects flash_controller_top directly to the Macronix
// behavioral model. All timing is real:
//   Tvcs  = 5ms   power-up
//   Tr    = 25µs  page read
//   Tprog = 320µs page program
//   Terase= 4ms   block erase
//
// No fake flash signals needed — the model drives nand_ryby_n
// and nand_io automatically in response to ONFI commands.
//
// Tests:
//   1. Reset
//   2. Erase block 0 (required before first program)
//   3. Program page 0, LBA=42
//   4. Read page 0 back, verify round trip
//   5. Program page 1, LBA=99
//   6. Read page 1 back, verify round trip
// ============================================================

`timescale 1ns/100ps
`include "MX30LF1G28AD.v"
`include "flash_controller_top.sv"


module flash_controller_top_ip_tb;

    localparam CLK_PERIOD = 20;
    localparam PAGE_BYTES = 2112;
    localparam PAGE_BEATS = PAGE_BYTES / 4;  // 528

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

    localparam STATUS_BUSY = 32'h1;
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
    logic [4:0]  axil_awaddr;  logic axil_awvalid; logic axil_awready;
    logic [31:0] axil_wdata;   logic [3:0] axil_wstrb;
    logic        axil_wvalid;  logic axil_wready;
    logic [1:0]  axil_bresp;   logic axil_bvalid;  logic axil_bready;
    logic [4:0]  axil_araddr;  logic axil_arvalid; logic axil_arready;
    logic [31:0] axil_rdata;   logic [1:0] axil_rresp;
    logic        axil_rvalid;  logic axil_rready;

    logic [31:0] s_axis_tdata;  logic s_axis_tvalid;
    logic        s_axis_tready; logic s_axis_tlast;
    logic [31:0] m_axis_tdata;  logic m_axis_tvalid;
    logic        m_axis_tready; logic m_axis_tlast;

    logic        nand_ce_n, nand_re_n, nand_we_n;
    logic        nand_cle, nand_ale, nand_wp_n;
    wire         nand_ryby_n;   // driven by flash model
    pullup (nand_ryby_n); 
    wire  [7:0]  nand_io;       // bidirectional, driven by flash model on reads

    // -------------------------------------------------------
    // DUT — flash_controller_top
    // -------------------------------------------------------
    flash_controller_top #(
        .CLK_PERIOD_NS (CLK_PERIOD),
        .PAGE_BYTES    (PAGE_BYTES)
    ) dut (
        .clk            (clk),          .rst_n          (rst_n),
        .s_axil_awaddr  (axil_awaddr),   .s_axil_awvalid (axil_awvalid),
        .s_axil_awready (axil_awready),  .s_axil_wdata   (axil_wdata),
        .s_axil_wstrb   (axil_wstrb),    .s_axil_wvalid  (axil_wvalid),
        .s_axil_wready  (axil_wready),   .s_axil_bresp   (axil_bresp),
        .s_axil_bvalid  (axil_bvalid),   .s_axil_bready  (axil_bready),
        .s_axil_araddr  (axil_araddr),   .s_axil_arvalid (axil_arvalid),
        .s_axil_arready (axil_arready),  .s_axil_rdata   (axil_rdata),
        .s_axil_rresp   (axil_rresp),    .s_axil_rvalid  (axil_rvalid),
        .s_axil_rready  (axil_rready),
        .s_axis_tdata   (s_axis_tdata),  .s_axis_tvalid  (s_axis_tvalid),
        .s_axis_tready  (s_axis_tready), .s_axis_tlast   (s_axis_tlast),
        .m_axis_tdata   (m_axis_tdata),  .m_axis_tvalid  (m_axis_tvalid),
        .m_axis_tready  (m_axis_tready), .m_axis_tlast   (m_axis_tlast),
        .nand_ce_n      (nand_ce_n),     .nand_re_n      (nand_re_n),
        .nand_we_n      (nand_we_n),     .nand_cle       (nand_cle),
        .nand_ale       (nand_ale),      .nand_wp_n      (nand_wp_n),
        .nand_ryby_n    (nand_ryby_n),   .nand_io        (nand_io)
    );

    // -------------------------------------------------------
    // Macronix MX30LF1G28AD behavioral model
    // Handles all ONFI timing and IO bus driving automatically
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
    // Checker
    // -------------------------------------------------------
    int pass_count = 0;
    int fail_count = 0;

    task automatic check(input string n, input logic [31:0] g, input logic [31:0] e);
        if (g === e) begin $display("  PASS  %s", n); pass_count++; end
        else begin $display("  FAIL  %s | got=0x%08h exp=0x%08h", n, g, e); fail_count++; end
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
    // AXI-Stream helpers
    // -------------------------------------------------------
    logic [7:0] write_buf  [0:PAGE_BYTES-1];
    logic [7:0] write_buf2 [0:PAGE_BYTES-1];
    logic [7:0] read_buf   [0:PAGE_BYTES-1];

    task automatic send_axis_page(input logic [7:0] page_buf [0:PAGE_BYTES-1]);
        for (int i = 0; i < PAGE_BEATS; i++) begin
            @(posedge clk);
            s_axis_tdata  <= {page_buf[i*4+3], page_buf[i*4+2],
                              page_buf[i*4+1], page_buf[i*4]};
            s_axis_tvalid <= 1;
            s_axis_tlast  <= (i == PAGE_BEATS-1);
            do @(posedge clk); while (!s_axis_tready);
        end
        s_axis_tvalid <= 0;
        s_axis_tlast  <= 0;
    endtask

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
    // DEBUG: trace first 5 bytes through pipeline
    // -------------------------------------------------------
    int dbg_deser_cnt  = 0;
    int dbg_wrfifo_cnt = 0;
    int dbg_sc_cnt     = 0;
    int dbg_fsm_rd_cnt = 0;
    int dbg_dc_cnt     = 0;
    int dbg_rdfifo_cnt = 0;

    always @(posedge clk) begin
        if (dut.deser_valid && !dut.wr_fifo_full) begin
            if (dbg_deser_cnt < 5)
                $display("[%0t] DESER->WRFIFO   byte[%0d] = 0x%02h",
                         $time, dbg_deser_cnt, dut.deser_byte);
            dbg_deser_cnt = dbg_deser_cnt + 1;
        end
        if (dut.wr_fifo_rd_en_r) begin
            if (dbg_wrfifo_cnt < 5)
                $display("[%0t] WRFIFO->SCRAM    byte[%0d] = 0x%02h",
                         $time, dbg_wrfifo_cnt, dut.wr_fifo_rd_data);
            dbg_wrfifo_cnt = dbg_wrfifo_cnt + 1;
        end
        if (dut.sc_out_valid) begin
            if (dbg_sc_cnt < 5)
                $display("[%0t] SCRAM->FSM       byte[%0d] = 0x%02h",
                         $time, dbg_sc_cnt, dut.sc_data_out);
            dbg_sc_cnt = dbg_sc_cnt + 1;
        end
        if (dut.fsm_rd_valid) begin
            if (dbg_fsm_rd_cnt < 5)
                $display("[%0t] FSM_RD->DESCRAM  byte[%0d] = 0x%02h",
                         $time, dbg_fsm_rd_cnt, dut.fsm_rd_byte);
            dbg_fsm_rd_cnt = dbg_fsm_rd_cnt + 1;
        end
        if (dut.dc_out_valid) begin
            if (dbg_dc_cnt < 5)
                $display("[%0t] DESCRAM->RDFIFO  byte[%0d] = 0x%02h",
                         $time, dbg_dc_cnt, dut.dc_data_out);
            dbg_dc_cnt = dbg_dc_cnt + 1;
        end
        if (dut.rd_fifo_rd_en) begin
            if (dbg_rdfifo_cnt < 5)
                $display("[%0t] RDFIFO->SER      byte[%0d] = 0x%02h",
                         $time, dbg_rdfifo_cnt, dut.rd_fifo_rd_data);
            dbg_rdfifo_cnt = dbg_rdfifo_cnt + 1;
        end
    end


    /*always @(posedge dut.nand_we_n) begin
        if (!dut.nand_ce_n && !dut.nand_cle && !dut.nand_ale)
            $display("[%0t] WEN_RISING: io=%02h nand_io=%02h byte_cnt=%0d", 
                    $time, dut.u_fsm.io_out, dut.nand_io, dut.u_fsm.byte_cnt);
    end */
    // -------------------------------------------------------
    // Main test
    // -------------------------------------------------------
    initial begin
        automatic logic [31:0] tb_status;
        automatic int          tb_errors;

        // Init signals
        axil_awvalid=0; axil_wvalid=0; axil_bready=0;
        axil_arvalid=0; axil_rready=0;
        s_axis_tvalid=0; s_axis_tlast=0; s_axis_tdata=0;
        m_axis_tready=1;

        rst_n = 0;
        repeat(4) @(posedge clk);
        rst_n = 1;

        // Must wait for flash power-up (Tvcs = 5_000_000 ns)
        $display("Waiting for flash power-up (5ms)...");
        #5_000_100;
        $display("Flash ready.\n");

        // Fill write patterns
        for (int i = 0; i < PAGE_BYTES; i++) write_buf[i]  = i[7:0];
        for (int i = 0; i < PAGE_BYTES; i++) begin
            automatic int val = PAGE_BYTES - i;
            write_buf2[i] = val[7:0];
        end

        // ================================================
        // TEST 1: Reset
        // ================================================
        $display("=== TEST 1: Reset ===");
        start_op(OP_RESET, 24'h0, 12'h0, 24'h0);
        axil_poll_done(tb_status);
        check("RESET no fail", tb_status & STATUS_FAIL, 32'h0);

        // ================================================
        // TEST 2: Erase block 0
        // NAND flash must be erased before programming
        // ================================================
        $display("\n=== TEST 2: Erase block 0 ===");
        start_op(OP_ERASE, 24'h000000, 12'h0, 24'h0);
        axil_poll_done(tb_status);
        check("ERASE no fail", tb_status & STATUS_FAIL, 32'h0);

        // ================================================
        // TEST 3: Program page 0, LBA=42
        // ================================================
        $display("\n=== TEST 3: Program page 0 (LBA=42) ===");
        fork
            send_axis_page(write_buf);
            begin
                repeat(5) @(posedge clk);
                start_op(OP_PROG, 24'h000000, 12'h000, 24'h00002A);
            end
        join
        axil_poll_done(tb_status);
        check("PROG no fail", tb_status & STATUS_FAIL, 32'h0);

        // ================================================
        // TEST 4: Read page 0 back, verify round trip
        // ================================================
        $display("\n=== TEST 4: Read page 0 (LBA=42), verify ===");
        recv_idx = 0;
        start_op(OP_READ, 24'h000000, 12'h000, 24'h00002A);
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
            $display("  PASS  All %0d bytes match after write→read round trip",
                     PAGE_BYTES);
        else begin
            $display("  FAIL  %0d bytes mismatched", tb_errors);
            fail_count++;
        end

        // ================================================
        // TEST 5: Program page 1, LBA=99
        // ================================================
        $display("\n=== TEST 5: Program page 1 (LBA=99) ===");
        fork
            send_axis_page(write_buf2);
            begin
                repeat(5) @(posedge clk);
                start_op(OP_PROG, 24'h000001, 12'h000, 24'h000063);
            end
        join
        axil_poll_done(tb_status);
        check("PROG page1 no fail", tb_status & STATUS_FAIL, 32'h0);

        $display("[%0t] DEBUG: rd_fifo_count=%0d read_done_latch=%b ser_started=%b",
         $time,
         dut.rd_fifo_count,
         dut.read_done_latch,
         dut.ser_started);

        // ================================================
        // TEST 6: Read page 1 back, verify round trip
        // ================================================
        $display("\n=== TEST 6: Read page 1 (LBA=99), verify ===");
        recv_idx = 0;
        start_op(OP_READ, 24'h000001, 12'h000, 24'h000063);
        axil_poll_done(tb_status);
        check("READ page1 no fail", tb_status & STATUS_FAIL, 32'h0);

        @(posedge clk iff m_axis_tlast);
        repeat(4) @(posedge clk);

        tb_errors = 0;
        for (int i = 0; i < PAGE_BYTES; i++) begin
            if (read_buf[i] !== write_buf2[i]) begin
                if (tb_errors < 4)
                    $display("  byte[%0d] got=0x%02h exp=0x%02h",
                             i, read_buf[i], write_buf2[i]);
                tb_errors++;
            end
        end
        if (tb_errors == 0)
            $display("  PASS  All %0d bytes match for page 1", PAGE_BYTES);
        else begin
            $display("  FAIL  %0d bytes mismatched on page 1", tb_errors);
            fail_count++;
        end

        // ================================================
        // Summary
        // ================================================
        repeat(10) @(posedge clk);
        $display("\n========================================");
        $display("  Results: %0d passed, %0d failed", pass_count, fail_count);
        $display("========================================\n");
        $finish;
    end

    // Timeout: covers 5ms powerup + erase(4ms) + 2x prog(320µs) + 2x read(25µs) + margin
    initial begin
        #25_000_000;
        $display("TIMEOUT");
        $finish;
    end

    initial begin
        $dumpfile("flash_controller_ip.vcd");
        $dumpvars(0, flash_controller_top_ip_tb);
    end

endmodule