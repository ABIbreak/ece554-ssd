// ============================================================
// flash_controller_top_tb_inject.sv
// Injected signal testbench — no real flash model
// ============================================================
`timescale 1ns/1ps  // Timescale: 1ns resolution, 1ps precision for accurate timing

`include "flash_controller_top.sv"  // Include the top-level flash controller module being tested

module flash_controller_top_tb_inject;

    // Timing and data size parameters
    localparam CLK_PERIOD = 10;  // Clock period in nanoseconds (10ns = 100 MHz)
    localparam PAGE_BYTES = 2112;  // NAND page size in bytes
    localparam PAGE_BEATS = PAGE_BYTES / 4;  // Number of AXI-Stream beats per page (2112/4 = 528)

    // AXI-Lite CSR register addresses (5-bit, byte addresses)
    localparam ADDR_FLASH_ADDR = 5'h00;  // Flash row address register
    localparam ADDR_COL_ADDR   = 5'h04;  // Flash column address register
    localparam ADDR_OPERATION  = 5'h08;  // Operation type register
    localparam ADDR_START      = 5'h0C;  // Start/trigger register (write-only)
    localparam ADDR_STATUS     = 5'h10;  // Status register (busy, done, fail flags)
    localparam ADDR_POLL_ADDR  = 5'h14;  // Polling address (not used in this TB)
    localparam ADDR_LBA        = 5'h18;  // Logical block address register

    // Flash operation type codes
    localparam OP_RESET  = 3'd0;  // Reset flash device
    localparam OP_READ   = 3'd1;  // Read page from flash
    localparam OP_PROG   = 3'd2;  // Program (write) page to flash
    localparam OP_ERASE  = 3'd3;  // Erase block in flash
    localparam OP_STATUS = 3'd4;  // Read status from flash

    // Status register bit flags
    localparam STATUS_BUSY = 32'h1;  // Bit 0: Operation in progress
    localparam STATUS_DONE = 32'h2;  // Bit 1: Operation completed successfully
    localparam STATUS_FAIL = 32'h4;  // Bit 2: Operation failed

    // -------------------------------------------------------
    // Clock generation
    // -------------------------------------------------------
    logic clk = 0;  // System clock signal
    logic rst_n;  // Active-low asynchronous reset
    always #(CLK_PERIOD/2) clk = ~clk;  // Toggle clock every 5ns (100 MHz)

    // -------------------------------------------------------
    // DUT signals (AXI-Lite CSR interface)
    // -------------------------------------------------------
    // Write address channel
    logic [4:0]  axil_awaddr;  // Write address
    logic axil_awvalid;  // Write address valid
    logic axil_awready;  // Write address ready
    // Write data channel
    logic [31:0] axil_wdata;   // Write data
    logic [3:0] axil_wstrb;    // Write strobes (byte enables)
    logic        axil_wvalid;  // Write data valid
    logic axil_wready;         // Write data ready
    // Write response channel
    logic [1:0]  axil_bresp;   // Write response (OKAY/SLVERR)
    logic axil_bvalid;         // Response valid
    logic axil_bready;         // Response ready
    // Read address channel
    logic [4:0]  axil_araddr;  // Read address
    logic axil_arvalid;        // Read address valid
    logic axil_arready;        // Read address ready
    // Read data channel
    logic [31:0] axil_rdata;   // Read data
    logic [1:0] axil_rresp;    // Read response (OKAY/SLVERR)
    logic        axil_rvalid;  // Read data valid
    logic axil_rready;         // Read data ready

    // Slave AXI-Stream interface (data to write to flash)
    logic [31:0] s_axis_tdata;   // Input data (4 bytes per beat)
    logic s_axis_tvalid;         // Input data valid
    logic        s_axis_tready;  // Input ready (slave can accept data)
    logic s_axis_tlast;          // Last beat of transfer

    // Master AXI-Stream interface (data read from flash)
    logic [31:0] m_axis_tdata;   // Output data (4 bytes per beat)
    logic m_axis_tvalid;         // Output data valid
    logic        m_axis_tready;  // Output ready (we can accept data)
    logic m_axis_tlast;          // Last beat of transfer

    // NAND flash control signals (low-active for CE#, RE#, WE#)
    logic        nand_ce_n;    // Chip enable (active low)
    logic nand_re_n;           // Read enable (active low)
    logic nand_we_n;           // Write enable (active low)
    logic        nand_cle;     // Command latch enable
    logic        nand_ale;     // Address latch enable
    logic        nand_wp_n;    // Write protect (active low)
    logic        nand_ryby_n;  // Ready/busy (active low = busy)
    wire  [7:0]  nand_io;      // 8-bit bidirectional data bus

    // Fake flash model (testbench drives these)
    logic [7:0]  nand_io_drive;  // Data to drive onto bus
    logic        nand_io_oe;     // Output enable for data bus
    assign nand_io = nand_io_oe ? nand_io_drive : 8'bz;  // Tristate driving logic

    // -------------------------------------------------------
    // DUT
    // -------------------------------------------------------
    flash_controller_top #(
        .CLK_PERIOD_NS (CLK_PERIOD),
        .PAGE_BYTES    (PAGE_BYTES)
    ) dut (
        .clk            (clk),          .rst_n          (rst_n),
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
    // Test result counters
    int pass_count = 0;  // Number of passing checks
    int fail_count = 0;  // Number of failing checks

    // Compare 32-bit values and print pass/fail result with timestamp
    task automatic check(input string n, input logic [31:0] g, input logic [31:0] e);
        if (g === e) begin $display("[%0t]  PASS  %s", $time, n); pass_count++; end  // Match: log PASS
        else begin $display("[%0t]  FAIL  %s | got=0x%08h exp=0x%08h", $time, n, g, e); fail_count++; end  // Mismatch: log FAIL with values
    endtask

    // Compare single-bit flags and print pass/fail result with timestamp
    task automatic check_flag(input string n, input logic g, input logic e);
        if (g === e) begin $display("[%0t]  PASS  %s", $time, n); pass_count++; end  // Match: log PASS
        else begin $display("[%0t]  FAIL  %s | got=%0b exp=%0b", $time, n, g, e); fail_count++; end  // Mismatch: log FAIL with bits
    endtask

    // -------------------------------------------------------
    // AXI-Lite driver tasks
    // -------------------------------------------------------
    // AXI-Lite write transaction: send address+data and wait for response
    task automatic axil_write(input logic [4:0] addr, input logic [31:0] data);
        @(posedge clk);
        // Drive address and data channels simultaneously
        axil_awaddr <= addr; axil_awvalid <= 1;  // Put address on bus with valid
        axil_wdata  <= data; axil_wstrb   <= 4'hF; axil_wvalid <= 1;  // Put data with strobe=all bytes
        // Wait for both address and data to be accepted, in parallel
        fork
            begin do @(posedge clk); while (!axil_awready); axil_awvalid <= 0; end  // Deassert addr valid when ready seen
            begin do @(posedge clk); while (!axil_wready);  axil_wvalid  <= 0; end  // Deassert data valid when ready seen
        join
        // Wait for write response from slave
        axil_bready <= 1;  // Assert ready to accept response
        do @(posedge clk); while (!axil_bvalid);  // Wait for response valid
        axil_bready <= 0;  // Deassert ready
    endtask

    // AXI-Lite read transaction: send address and wait for data response
    task automatic axil_read(input logic [4:0] addr, output logic [31:0] data);
        @(posedge clk);
        axil_araddr <= addr; axil_arvalid <= 1;  // Put read address on bus with valid
        do @(posedge clk); while (!axil_arready);  // Wait for slave to accept address
        axil_arvalid <= 0;  // Deassert address valid
        axil_rready  <= 1;  // Assert ready to accept read data
        do @(posedge clk); while (!axil_rvalid);  // Wait for slave to provide data
        data = axil_rdata;  // Capture the read data
        axil_rready <= 0;  // Deassert ready
    endtask

    // Poll status register until operation completes (BUSY bit clears)
    task automatic axil_poll_done(output logic [31:0] status);
        logic [31:0] s;
        // Keep reading status until BUSY flag is no longer asserted
        do begin axil_read(ADDR_STATUS, s); @(posedge clk); end
        while (s & STATUS_BUSY);  // Exit loop when BUSY bit (0x1) is 0
        status = s;  // Return final status value
    endtask

    // Start a flash operation by writing parameters and triggering start
    task automatic start_op(
        input logic [2:0]  op,      // Operation type (reset/read/prog/erase/status)
        input logic [23:0] row,     // Flash row address
        input logic [11:0] col,     // Flash column address
        input logic [23:0] lba      // Logical block address
    );
        axil_write(ADDR_FLASH_ADDR, {8'h0, row});  // Write row address to FLASH_ADDR register
        axil_write(ADDR_COL_ADDR,   {20'h0, col});  // Write column address to COL_ADDR register
        axil_write(ADDR_LBA,        {8'h0, lba});   // Write LBA to LBA register
        axil_write(ADDR_OPERATION,  {29'h0, op});   // Write operation code to OPERATION register
        axil_write(ADDR_START,      32'h1);         // Write 1 to START register to trigger operation
    endtask

    // -------------------------------------------------------
    // Fake flash
    // -------------------------------------------------------
// Simulated NAND flash storage
    logic [7:0] fake_flash_mem [0:PAGE_BYTES-1];  // Main flash memory array (2112 bytes)
    logic [7:0] nand_io_cap    [0:PAGE_BYTES-1];  // Capture buffer to store written data

    // Write data capture control
    int   wr_capture_idx = 0;  // Index for capturing write bytes
    logic capturing_write = 0;  // Flag to enable write capture

    // Capture data bytes written to NAND when WE# goes high (on rising edge)
    always @(posedge nand_we_n) begin
        // Only capture if chip enabled, and in data write mode (CLE=0, ALE=0), and capturing is enabled
        if (!nand_ce_n && !nand_cle && !nand_ale && capturing_write) begin
            if (wr_capture_idx < PAGE_BYTES) begin
                nand_io_cap[wr_capture_idx] = nand_io;  // Latch the byte on the bus
                wr_capture_idx = wr_capture_idx + 1;    // Advance buffer index
            end
        end
    end

    // Initialize NAND interface signals
    initial nand_ryby_n  = 1;  // NAND ready (not busy)
    initial nand_io_oe   = 0;  // Testbench not driving data bus initially
    initial nand_io_drive = 0;  // Data bus driver value (irrelevant when oe=0)

    // Simulate a busy period on NAND interface
    task automatic fake_busy(input int busy_ns);
        nand_ryby_n = 0;  // Assert busy (low)
        #busy_ns;         // Wait for specified duration
        nand_ryby_n = 1;  // Release busy (high = ready)
    endtask

    // -------------------------------------------------------
    // fake_drive_read_data
    // Pre-loads byte 0 onto the bus BEFORE nand_ryby_n goes
    // high so data is stable when the FSM first asserts RE#.
    // Updates on posedge RE# (after channel has sampled).
    // Call this AFTER setting nand_ryby_n=0 but BEFORE
    // setting nand_ryby_n=1.
    // -------------------------------------------------------
    task automatic fake_drive_read_data;
        // Pre-load byte 0 — must be on bus before first RE# negedge
        nand_io_oe    = 1;
        nand_io_drive = fake_flash_mem[0];

        for (int i = 0; i < PAGE_BYTES; i++) begin
            @(negedge nand_re_n);              // FSM dropped RE# low
            nand_io_drive = fake_flash_mem[i]; // data stable during RE# low
            @(posedge nand_re_n);              // FSM raised RE# — just sampled
            if (i + 1 < PAGE_BYTES)
                nand_io_drive = fake_flash_mem[i + 1]; // pre-load next byte
        end
        nand_io_oe = 0;
    endtask

    // -------------------------------------------------------
    // AXI-Stream helpers
    // -------------------------------------------------------
    // Buffers for write data (to flash) and read data (from flash)
    logic [7:0] write_buf [0:PAGE_BYTES-1];  // Data to write to flash
    logic [7:0] read_buf  [0:PAGE_BYTES-1];  // Data received from flash

    // Send a page of data via AXI-Stream slave interface (pack 4 bytes per beat)
    task automatic send_axis_page(input logic [7:0] page_buf [0:PAGE_BYTES-1]);
        for (int i = 0; i < PAGE_BEATS; i++) begin  // Loop over all beats (528)
            @(posedge clk);
            // Pack 4 bytes in little-endian order: byte0 at [7:0], byte3 at [31:24]
            s_axis_tdata  <= {page_buf[i*4+3], page_buf[i*4+2],
                              page_buf[i*4+1], page_buf[i*4]};
            s_axis_tvalid <= 1;  // Data is valid
            s_axis_tlast  <= (i == PAGE_BEATS-1);  // Assert last on final beat
            do @(posedge clk); while (!s_axis_tready);  // Wait for slave ready
        end
        // End of transfer
        s_axis_tvalid <= 0;  // Deassert valid
        s_axis_tlast  <= 0;  // Deassert last
    endtask

    // Receive data from master AXI-Stream port (unpack 4 bytes per beat)
    int recv_idx = 0;  // Beat counter for received data
    always @(posedge clk) begin
        // Capture data when valid and ready are asserted (handshake)
        if (m_axis_tvalid && m_axis_tready) begin
            if (recv_idx < PAGE_BEATS) begin
                // Unpack 32-bit data into 4 individual bytes
                read_buf[recv_idx*4+0] = m_axis_tdata[7:0];    // Byte 0 (LSB)
                read_buf[recv_idx*4+1] = m_axis_tdata[15:8];   // Byte 1
                read_buf[recv_idx*4+2] = m_axis_tdata[23:16];  // Byte 2
                read_buf[recv_idx*4+3] = m_axis_tdata[31:24];  // Byte 3 (MSB)
                recv_idx = recv_idx + 1;  // Advance to next beat
            end
        end
    end

    // -------------------------------------------------------
    // DEBUG: trace first 5 bytes through every pipeline stage
    // Remove after bug is found
    // -------------------------------------------------------
    int dbg_deser_cnt   = 0;
    int dbg_wrfifo_cnt  = 0;
    int dbg_sc_cnt      = 0;
    int dbg_fsm_rd_cnt  = 0;
    int dbg_dc_cnt      = 0;
    int dbg_rdfifo_cnt  = 0;

    always @(posedge clk) begin

        // Debug: Track first 5 bytes from deserializer input stage
        if (dut.deser_valid && !dut.wr_fifo_full) begin
            if (dbg_deser_cnt < 5)  // Only log first 5 bytes
                $display("[%0t] DESER->WRFIFO   byte[%0d] = 0x%02h",
                         $time, dbg_deser_cnt, dut.deser_byte);  // Show timestamp, index, value
            dbg_deser_cnt = dbg_deser_cnt + 1;  // Increment counter
        end

    // Debug: Track first 5 bytes from write FIFO output (pre-scramble)
        if (dut.wr_fifo_rd_en) begin
            if (dbg_wrfifo_cnt < 5)  // Only log first 5 bytes
                $display("[%0t] WRFIFO->SCRAM    byte[%0d] = 0x%02h",
                         $time, dbg_wrfifo_cnt, dut.wr_fifo_rd_data);  // Show byte before scrambling
            dbg_wrfifo_cnt = dbg_wrfifo_cnt + 1;  // Increment counter
        end

    // Debug: Track first 5 bytes after scrambler output (pre-NAND)
        if (dut.sc_out_valid) begin
            if (dbg_sc_cnt < 5)  // Only log first 5 bytes
                $display("[%0t] SCRAM->FSM       byte[%0d] = 0x%02h",
                         $time, dbg_sc_cnt, dut.sc_data_out);  // Show byte after scrambling
            dbg_sc_cnt = dbg_sc_cnt + 1;  // Increment counter
        end

    // Debug: Track first 5 bytes read from NAND (post-NAND, pre-descramble)
        if (dut.fsm_rd_valid) begin
            if (dbg_fsm_rd_cnt < 5)  // Only log first 5 bytes
                $display("[%0t] FSM_RD->DESCRAM  byte[%0d] = 0x%02h",
                         $time, dbg_fsm_rd_cnt, dut.fsm_rd_byte);  // Show byte read from flash
            dbg_fsm_rd_cnt = dbg_fsm_rd_cnt + 1;  // Increment counter
        end

    // Debug: Track first 5 bytes after descrambler output
        if (dut.dc_out_valid) begin
            if (dbg_dc_cnt < 5)  // Only log first 5 bytes
                $display("[%0t] DESCRAM->RDFIFO  byte[%0d] = 0x%02h",
                         $time, dbg_dc_cnt, dut.dc_data_out);  // Show byte after descrambling
            dbg_dc_cnt = dbg_dc_cnt + 1;  // Increment counter
        end

    // Debug: Track first 5 bytes from read FIFO (pre-serializer)
        if (dut.rd_fifo_rd_en) begin
            if (dbg_rdfifo_cnt < 5)  // Only log first 5 bytes
                $display("[%0t] RDFIFO->SER      byte[%0d] = 0x%02h",
                         $time, dbg_rdfifo_cnt, dut.rd_fifo_rd_data);  // Show byte before serializer
            dbg_rdfifo_cnt = dbg_rdfifo_cnt + 1;  // Increment counter
        end

    end
    initial begin
        // Test variables
        automatic logic [31:0] tb_status;  // Status register value from DUT
        automatic int          tb_errors;  // Counter for mismatched bytes
        automatic int          tb_same_count;  // Counter for unchanged bytes (scramble validation)

        // Initialize testbench interface signals
        axil_awvalid=0; axil_wvalid=0; axil_bready=0;  // AXI-Lite write handshakes
        axil_arvalid=0; axil_rready=0;                 // AXI-Lite read handshakes
        s_axis_tvalid=0; s_axis_tlast=0; s_axis_tdata=0;  // AXI-Stream slave (input)
        m_axis_tready=1;  // AXI-Stream master (output) - always ready

        // Apply reset
        rst_n = 0;  // Assert reset (active low)
        repeat(4) @(posedge clk);  // Hold for 4 clock cycles
        rst_n = 1;  // Release reset
        repeat(2) @(posedge clk);  // Wait for reset synchronization

        // Initialize test buffers
        for (int i = 0; i < PAGE_BYTES; i++)
            write_buf[i] = i[7:0];  // Fill write buffer with pattern: 0x00, 0x01, ..., 0xFF, 0x00, ...
        for (int i = 0; i < PAGE_BYTES; i++)
            fake_flash_mem[i] = 8'hFF;  // Initialize fake flash to all 0xFF (erased state)

        // ================================================
        // TEST 1: AXI-Lite register R/W
        // ================================================
        $display("[%0t] === TEST 1: AXI-Lite Register R/W ===", $time);
        // TEST 1: Register write and read verification
        begin
            logic [31:0] rd;  // Temporary register to hold read values
            // Test FLASH_ADDR register
            axil_write(ADDR_FLASH_ADDR, 32'h00ABCDEF);  // Write test pattern
            axil_read (ADDR_FLASH_ADDR, rd);  // Read back value
            check("FLASH_ADDR", rd, 32'h00ABCDEF);  // Verify matches

            // Test LBA register
            axil_write(ADDR_LBA, 32'h00001234);  // Write test pattern
            axil_read (ADDR_LBA, rd);  // Read back value
            check("LBA reg", rd, 32'h00001234);  // Verify matches

            // Test OPERATION register
            axil_write(ADDR_OPERATION, 32'h2);  // Write op code for PROG
            axil_read (ADDR_OPERATION, rd);  // Read back value
            check("OPERATION", rd, 32'h2);  // Verify matches

            // Test START register (write-only, reads as 0)
            axil_read(ADDR_START, rd);  // Read START register
            check("START reads 0 (WO)", rd, 32'h0);  // Verify it reads as 0 (write-only)
        end

        // ================================================
        // TEST 2: Reset
        // ================================================
        $display("[%0t] === TEST 2: Reset (injected) ===", $time);
        // TEST 2: Reset operation
        begin
            // Run reset command and simulate busy period in parallel
            fork
                start_op(OP_RESET, 24'h0, 12'h0, 24'h0);  // Issue reset command
                begin repeat(5) @(posedge clk); fake_busy(500); end  // Inject 500ns busy period
            join
            // Wait for operation to complete (poll until not busy)
            axil_poll_done(tb_status);  // Read status until BUSY clears
            check("RESET no fail", tb_status & STATUS_FAIL, 32'h0);  // Verify no error flag set
        end

        // ================================================
        // TEST 3: Write path
        // ================================================
        $display("[%0t] === TEST 3: Write path with scrambling ===", $time);
        // TEST 3: Program (write) operation with scrambling
        begin
            // Reset capture buffer for this write
            wr_capture_idx  = 0;  // Reset capture index to start
            capturing_write = 1;  // Enable capture of written bytes

            // Send write data and start PROG operation in parallel
            fork : prog_data
                send_axis_page(write_buf);  // Stream data to write via AXI-Stream input
                begin
                    repeat(3) @(posedge clk);  // Wait 3 cycles for data to start flowing
                    start_op(OP_PROG, 24'h000000, 12'h000, 24'h00002A);  // Issue PROG command
                end
            join_any  // Don't wait for both to complete simultaneously
            wait fork;  // Wait for any spawned processes to finish

            // Simulate NAND flash program operation
            fork : fake_flash_prog
                begin
                    @(negedge nand_ce_n);  // Wait for controller to assert chip enable
                    #((PAGE_BYTES * 4 * CLK_PERIOD) + 500);  // Wait for all data to be written (~42 us)
                    nand_ryby_n = 0;  // Assert busy (simulate program time)
                    #5000;  // Simulate 5 us program operation
                    nand_ryby_n = 1;  // Release busy (program complete)
                end
                begin
                    #9_000_000;  // Timeout: prevent hanging (9 ms)
                end
            join_any  // Exit when first fork completes
            disable fake_flash_prog;  // Kill any remaining processes

            // Verify write completed
            capturing_write = 0;  // Stop capturing data
            axil_poll_done(tb_status);  // Read status until PROG completes
            check("PROG no fail", tb_status & STATUS_FAIL, 32'h0);  // Verify no error

            // Verify data was scrambled (not written as-is)
            tb_same_count = 0;  // Counter for bytes that match original
            for (int i = 0; i < PAGE_BYTES; i++)
                if (nand_io_cap[i] === write_buf[i]) tb_same_count++;  // Count unchanged bytes
            // If >=75% of bytes are scrambled, PASS (less than 25% match original)
            if (tb_same_count < PAGE_BYTES / 4)
                $display("[%0t]  PASS  Data was scrambled (%0d/%0d bytes unchanged)",
                         $time, tb_same_count, PAGE_BYTES);
            else begin
                $display("[%0t]  FAIL  Data appears unscrambled (%0d/%0d same)",
                         $time, tb_same_count, PAGE_BYTES);
                fail_count++;  // Count this as a failed test
            end

            // Copy scrambled data into fake flash (simulating successful program)
            for (int i = 0; i < PAGE_BYTES; i++)
                fake_flash_mem[i] = nand_io_cap[i];  // Store written data
        end

        // ================================================
        // TEST 4: Read path with descrambling
        // ================================================
        $display("[%0t] === TEST 4: Read path with descrambling ===", $time);
        // TEST 4: Read operation with descrambling
        begin
            recv_idx      = 0;  // Reset receive index
            m_axis_tready = 1;  // Keep output ready throughout read

            // Issue read command for data we just programmed
            start_op(OP_READ, 24'h000000, 12'h000, 24'h00002A);  // Same address as PROG

            // Wait for controller to request data from NAND
            @(negedge nand_ce_n);  // Wait for chip enable assertion

            // Simulate NAND page load operation
            // Testbench fills data bus byte-by-byte, synced to RE# (read enable) pulses
            // Pre-load byte 0 to bus BEFORE releasing busy, so first byte is immediately
            // available when controller starts reading (asserts RE#)
            nand_io_oe    = 1;  // Enable testbench to drive data bus
            nand_io_drive = fake_flash_mem[0];  // Place first byte on bus
            nand_ryby_n   = 0;  // Assert busy (simulating page load time)
            #2000;  // Simulate 2 us page load delay
            nand_ryby_n   = 1;  // Release busy (data ready for reading)

            // Drive remaining bytes synced to RE# (read enable) cycles
            // Synchronization: Controller drops RE# to read a byte, then raises RE#.
            // Upon posedge RE# (byte sampled), testbench updates bus with next byte.
            // Data is stable on bus while RE# is high, ready for next negedge RE#.
            for (int i = 0; i < PAGE_BYTES - 1; i++) begin
                @(posedge nand_re_n);  // Wait for RE# to go high (byte i just sampled)
                nand_io_drive = fake_flash_mem[i+1];  // Load byte i+1 while RE# high (setup time)
            end
            @(posedge nand_re_n);  // Wait for last byte to be sampled
            nand_io_oe = 0;  // Disable data bus driving (release to high-Z)

            // Wait for read to complete
            axil_poll_done(tb_status);  // Poll until operation finishes
            check("READ no fail", tb_status & STATUS_FAIL, 32'h0);  // Verify no error flag

            // Wait for all data to be received via AXI-Stream output
            @(posedge clk iff m_axis_tlast);  // Wait for "last" beat on output
            repeat(4) @(posedge clk);  // Extra cycles for pipeline settling

            // Compare read data (descrambled) with original write data
            tb_errors = 0;  // Initialize error counter
            for (int i = 0; i < PAGE_BYTES; i++) begin
                if (read_buf[i] !== write_buf[i]) begin  // Check each byte
                    if (tb_errors < 4)  // Print first 4 mismatches
                        $display("[%0t]  byte[%0d] got=0x%02h exp=0x%02h",
                                 $time, i, read_buf[i], write_buf[i]);
                    if (tb_errors > 2000)  // Print summary of remaining mismatches
                        $display("[%0t]  byte[%0d] got=0x%02h exp=0x%02h",
                                 $time, i, read_buf[i], write_buf[i]);
                    tb_errors++;  // Count this mismatch
                end
            end
            // Report round-trip test result (write-scramble-read-descramble)
            if (tb_errors == 0)
                $display("[%0t]  PASS  All %0d bytes recovered correctly after descramble",
                         $time, PAGE_BYTES);  // Perfect match = success
            else begin
                $display("[%0t]  FAIL  %0d bytes mismatched after round trip", $time, tb_errors);
                fail_count++;  // Count as test failure
            end
        end

        // ================================================
        // Summary
        // ================================================
        // Test complete - print summary
        repeat(4) @(posedge clk);  // Wait a few cycles for last outputs
        $display("[%0t] ========================================", $time);  // Banner
        $display("[%0t]   Results: %0d passed, %0d failed", $time, pass_count, fail_count);  // Summary
        $display("[%0t] ========================================", $time);  // Banner
        $finish;  // End simulation
    end

    // Watchdog timer to prevent simulation from hanging
    initial begin #25_000_000; $display("[%0t] TIMEOUT", $time); $finish; end  // 25 ms timeout
    // VCD waveform dumping for debugging
    initial begin
        $dumpfile("flash_controller_inject.vcd");  // Output file for waveforms
        $dumpvars(0, flash_controller_top_tb_inject);  // Dump all signals in module hierarchy
    end

endmodule