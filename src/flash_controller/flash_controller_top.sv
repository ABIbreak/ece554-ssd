// ============================================================
// flash_controller_top.sv
// Flash Controller Top Level
// ============================================================
// Connects all submodules:
//   AXI-Lite Wrapper  ← control plane (MicroBlaze talks here)
//   AXI-S Deserializer← write data path in
//   Write FIFO        ← buffers page before scrambling
//   Scrambler         ← XOR with LFSR seeded by LBA
//   NAND FSM          ← drives physical ONFI signals
//   Descrambler       ← XOR with same LFSR on readback
//   Read FIFO         ← buffers page coming back from flash
//   AXI-S Serializer  ← read data path out
//
// AXI-Lite Register Map:
//   0x00  FLASH_ADDR  [23:0]  RW  Physical page (row) address
//   0x04  COL_ADDR    [11:0]  RW  Column address
//   0x08  OPERATION   [2:0]   RW  0=RST 1=READ 2=PROG 3=ERASE 4=STAT
//   0x0C  START       [0]     WO  Write 1 to begin (self-clears)
//   0x10  STATUS      [2:0]   RO  bit0=busy bit1=done bit2=fail
//   0x14  POLL_ADDR   [31:0]  RW  DDR4 completion address
//   0x18  LBA         [23:0]  RW  Logical block address (scrambler seed)
// ============================================================

`include "flash_channel.sv"
`include "axis_serializer.sv"
`include "axis_deserializer.sv"
`include "fifo.sv"
`include "scrambler.sv"

module flash_controller_top #(
    parameter CLK_PERIOD_NS  = 10,
    parameter PAGE_BYTES     = 2112,
    parameter AXIS_WIDTH     = 32,
    parameter ADDR_WIDTH     = 5,
    parameter ID_WIDTH       = 4
)(
    input  logic                  clk,
    input  logic                  rst_n,

    // ---- AXI-Lite Slave (control plane) ------------------
    input  logic [ADDR_WIDTH-1:0] s_axil_awaddr,
    input  logic                  s_axil_awvalid,
    output logic                  s_axil_awready,
    input  logic [31:0]           s_axil_wdata,
    input  logic [3:0]            s_axil_wstrb,
    input  logic                  s_axil_wvalid,
    output logic                  s_axil_wready,
    output logic [1:0]            s_axil_bresp,
    output logic                  s_axil_bvalid,
    input  logic                  s_axil_bready,
    input  logic [ADDR_WIDTH-1:0] s_axil_araddr,
    input  logic                  s_axil_arvalid,
    output logic                  s_axil_arready,
    output logic [31:0]           s_axil_rdata,
    output logic [1:0]            s_axil_rresp,
    output logic                  s_axil_rvalid,
    input  logic                  s_axil_rready,

    // ---- AXI-Stream write data (from DMA engine) ---------
    input  logic [AXIS_WIDTH-1:0] s_axis_tdata,
    input  logic                  s_axis_tvalid,
    output logic                  s_axis_tready,
    input  logic                  s_axis_tlast,

    // ---- AXI-Stream read data (to DMA engine) ------------
    output logic [AXIS_WIDTH-1:0] m_axis_tdata,
    output logic                  m_axis_tvalid,
    input  logic                  m_axis_tready,
    output logic                  m_axis_tlast,

    // ---- NAND physical interface -------------------------
    output logic                  nand_ce_n,
    output logic                  nand_re_n,
    output logic                  nand_we_n,
    output logic                  nand_cle,
    output logic                  nand_ale,
    output logic                  nand_wp_n,
    input  logic                  nand_ryby_n,
    inout  wire  [7:0]            nand_io
);

    // -------------------------------------------------------
    // AXI-Lite register addresses
    // -------------------------------------------------------
    localparam ADDR_FLASH_ADDR = 5'h00;
    localparam ADDR_COL_ADDR   = 5'h04;
    localparam ADDR_OPERATION  = 5'h08;
    localparam ADDR_START      = 5'h0C;
    localparam ADDR_STATUS     = 5'h10;
    localparam ADDR_POLL_ADDR  = 5'h14;
    localparam ADDR_LBA        = 5'h18;

    // -------------------------------------------------------
    // AXI-Lite registers
    // -------------------------------------------------------
    logic [23:0] reg_flash_addr;
    logic [11:0] reg_col_addr;
    logic [2:0]  reg_operation;
    logic        reg_start;
    logic [31:0] reg_poll_addr;
    logic [23:0] reg_lba;

    // -------------------------------------------------------
    // Internal wires
    // -------------------------------------------------------
    // FSM control
    logic        fsm_busy;
    logic        fsm_done;
    logic        fsm_fail;
    logic        fsm_data_req;
    logic [7:0]  fsm_status_byte;

    // Write path: deserializer → write FIFO → scrambler → FSM
    logic [7:0]  deser_byte;
    logic        deser_valid;
    logic        deser_ready;     // = !wr_fifo_full
    logic        deser_page_done;

    logic        wr_fifo_full;
    logic        wr_fifo_empty;
    logic        wr_fifo_rd_en;
    logic [7:0]  wr_fifo_rd_data;

    logic [7:0]  sc_data_out;
    logic        sc_out_valid;

    // Read path: FSM → descrambler → read FIFO → serializer
    logic [7:0]  fsm_rd_byte;
    logic        fsm_rd_valid;

    logic [7:0]  dc_data_out;
    logic        dc_out_valid;

    logic        rd_fifo_full;
    logic        rd_fifo_empty;
    logic        rd_fifo_rd_en;
    logic [7:0]  rd_fifo_rd_data;
    logic [12:0] rd_fifo_count;
    logic rd_fifo_flush;
    assign rd_fifo_flush = reg_start && (reg_operation == 3'd1);

    logic        ser_start;
    logic        ser_done;

    // Scrambler/descrambler seed control
    logic        seed_valid;

    // FSM data connections — write path feeds from scrambler output
    logic [7:0]  fsm_data_in;
    logic        fsm_data_wr;

    // -------------------------------------------------------
    // AXI-Lite Write Path
    // -------------------------------------------------------
    logic                  aw_done;
    logic [ADDR_WIDTH-1:0] aw_addr_lat;
    logic                  w_done;
    logic [31:0]           w_data_lat;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            aw_done        <= 0;
            aw_addr_lat    <= '0;
            w_done         <= 0;
            w_data_lat     <= '0;
            s_axil_awready <= 1;
            s_axil_wready  <= 1;
            s_axil_bvalid  <= 0;
            s_axil_bresp   <= 2'b00;
            reg_flash_addr <= '0;
            reg_col_addr   <= '0;
            reg_operation  <= '0;
            reg_start      <= 0;
            reg_poll_addr  <= '0;
            reg_lba        <= '0;
            seed_valid     <= 0;
        end else begin
            reg_start  <= 0;
            seed_valid <= 0;

            if (s_axil_awvalid && s_axil_awready) begin
                aw_addr_lat    <= s_axil_awaddr;
                aw_done        <= 1;
                s_axil_awready <= 0;
            end

            if (s_axil_wvalid && s_axil_wready) begin
                w_data_lat    <= s_axil_wdata;
                w_done        <= 1;
                s_axil_wready <= 0;
            end

            if (aw_done && w_done) begin
                aw_done        <= 0;
                w_done         <= 0;
                s_axil_awready <= 1;
                s_axil_wready  <= 1;
                s_axil_bvalid  <= 1;
                s_axil_bresp   <= 2'b00;

                case (aw_addr_lat)
                    ADDR_FLASH_ADDR: reg_flash_addr <= w_data_lat[23:0];
                    ADDR_COL_ADDR:   reg_col_addr   <= w_data_lat[11:0];
                    ADDR_OPERATION:  reg_operation  <= w_data_lat[2:0];
                    ADDR_POLL_ADDR:  reg_poll_addr  <= w_data_lat;
                    ADDR_LBA:        reg_lba        <= w_data_lat[23:0];
                    ADDR_START: begin
                        reg_start  <= w_data_lat[0];
                        seed_valid <= w_data_lat[0]; // pulse seed on start
                    end
                    ADDR_STATUS: ;   // RO
                    default: s_axil_bresp <= 2'b10;
                endcase
            end

            if (s_axil_bvalid && s_axil_bready)
                s_axil_bvalid <= 0;
        end
    end

    // -------------------------------------------------------
    // AXI-Lite Read Path
    // -------------------------------------------------------
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            s_axil_arready <= 1;
            s_axil_rvalid  <= 0;
            s_axil_rdata   <= '0;
            s_axil_rresp   <= 2'b00;
        end else begin
            s_axil_arready <= !s_axil_rvalid;

            if (s_axil_arvalid && s_axil_arready) begin
                s_axil_rvalid <= 1;
                s_axil_rresp  <= 2'b00;
                case (s_axil_araddr)
                    ADDR_FLASH_ADDR: s_axil_rdata <= {8'h0,  reg_flash_addr};
                    ADDR_COL_ADDR:   s_axil_rdata <= {20'h0, reg_col_addr};
                    ADDR_OPERATION:  s_axil_rdata <= {29'h0, reg_operation};
                    ADDR_START:      s_axil_rdata <= 32'h0;
                    ADDR_STATUS:     s_axil_rdata <= {29'h0, fsm_fail,
                                                      fsm_done, fsm_busy};
                    ADDR_POLL_ADDR:  s_axil_rdata <= reg_poll_addr;
                    ADDR_LBA:        s_axil_rdata <= {8'h0, reg_lba};
                    default: begin
                        s_axil_rdata <= 32'h0;
                        s_axil_rresp <= 2'b10;
                    end
                endcase
            end

            if (s_axil_rvalid && s_axil_rready)
                s_axil_rvalid <= 0;
        end
    end
    // -------------------------------------------------------
    // Serializer start — trigger when read op completes
    // loading the read FIFO
    // -------------------------------------------------------
    // Start serializer one cycle after FSM done on a READ op

    logic ser_started;
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) ser_started <= 0;
        else begin
            if (reg_start && (reg_operation == 3'd1)) ser_started <= 0;
            else if (ser_start) ser_started <= 1;
        end
    end

    always_ff @(posedge clk) begin
    if (reg_start && (reg_operation == 3'd1))
        $display("[%0t] LATCH RESET: read op start detected", $time);
    end

    always_ff @(posedge clk) begin
        if (ser_start)
            $display("[%0t] SER_START fired: rd_fifo_count=%0d", $time, rd_fifo_count);
        end

    logic read_done_latch;
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) read_done_latch <= 0;
        else begin
            if (reg_start && (reg_operation == 3'd1)) read_done_latch <= 0;
            else if (fsm_done && (reg_operation == 3'd1)) read_done_latch <= 1;
        end
    end
    assign ser_start = (rd_fifo_count >= 4) && (reg_operation == 3'd1) && !ser_started && read_done_latch;

    always_ff @(posedge clk) begin
    if (reg_start)
        $display("[%0t] REG_START fired: operation=%0d", $time, reg_operation);
    end

    // -------------------------------------------------------
    // Write path connections
    // -------------------------------------------------------
    // Deserializer output → write FIFO
    assign deser_ready = !wr_fifo_full;

    // Write FIFO → scrambler
    // Pull from FIFO when scrambler can accept (always ready
    // since scrambler is purely registered with no stall)

/*     always_ff @(posedge clk) begin
    if (!wr_fifo_empty)
        $display("[%0t] WR_PATH: fsm_data_req=%b wr_fifo_rd_en=%b wr_fifo_rd_data=%h sc_out_valid=%b sc_data_out=%h fsm_data_wr=%b fsm_data_in=%h",
                 $time,
                 fsm_data_req,
                 wr_fifo_rd_en,
                 wr_fifo_rd_data,
                 sc_out_valid,
                 sc_data_out,
                 fsm_data_wr,
                 fsm_data_in);
    end */
    assign wr_fifo_rd_en = !wr_fifo_empty && fsm_data_req;

    logic wr_fifo_rd_en_r;
        always_ff @(posedge clk or negedge rst_n) begin
            if (!rst_n) wr_fifo_rd_en_r <= 0;
            else        wr_fifo_rd_en_r <= wr_fifo_rd_en;
        end

    // Scrambler output → FSM write data
    assign fsm_data_in = sc_data_out;
    assign fsm_data_wr = sc_out_valid;

    // -------------------------------------------------------
    // AXI-S Deserializer
    // -------------------------------------------------------
    axis_deserializer #(
        .AXIS_WIDTH (AXIS_WIDTH)
    ) u_deser (
        .clk            (clk),
        .rst_n          (rst_n),
        .s_axis_tdata   (s_axis_tdata),
        .s_axis_tvalid  (s_axis_tvalid),
        .s_axis_tready  (s_axis_tready),
        .s_axis_tlast   (s_axis_tlast),
        .out_data_o     (deser_byte),
        .out_valid_o    (deser_valid),
        .out_ready_i    (deser_ready),
        .page_done_o    (deser_page_done)
    );

    // -------------------------------------------------------
    // Write FIFO
    // -------------------------------------------------------
    fifo #(
        .DATA_WIDTH (8),
        .DEPTH      (PAGE_BYTES)
    ) u_wr_fifo (
        .clk          (clk),
        .rst_n        (rst_n),
        .wr_en_i      (deser_valid),
        .wr_data_i    (deser_byte),
        .full_o       (wr_fifo_full),
        .rd_en_i      (wr_fifo_rd_en),
        .rd_data_o    (wr_fifo_rd_data),
        .empty_o      (wr_fifo_empty),
        .flush_i      (1'b0),
        .almost_full_o(),
        .count_o      (),
        .overflow_o   (),
        .underflow_o  ()
    );

    // -------------------------------------------------------
    // Scrambler
    // -------------------------------------------------------
    scrambler u_scrambler (
        .clk          (clk),
        .rst_n        (rst_n),
        .seed_valid_i (seed_valid),
        .seed_i       (reg_lba),
        .data_i       (wr_fifo_rd_data),
        .in_valid_i   (wr_fifo_rd_en_r),
        .data_o       (sc_data_out),
        .out_valid_o  (sc_out_valid),
        .byte_count_o ()
    );

    // -------------------------------------------------------
    // NAND Flash FSM
    // -------------------------------------------------------
    flash_channel #(
        .CLK_PERIOD_NS (CLK_PERIOD_NS),
        .PAGE_BYTES    (PAGE_BYTES)
    ) u_fsm (
        .clk         (clk),
        .rst_n       (rst_n),
        .op_start_i  (reg_start),
        .op_type_i   (reg_operation),
        .row_addr_i  (reg_flash_addr),
        .col_addr_i  (reg_col_addr),
        .data_i      (fsm_data_in),
        .data_wr_i   (fsm_data_wr),
        .data_o      (fsm_rd_byte),
        .data_rd_o   (fsm_rd_valid),
        .busy_o      (fsm_busy),
        .done_o      (fsm_done),
        .status_o    (fsm_status_byte),
        .fail_o      (fsm_fail),
        .data_req_o  (fsm_data_req),
        .nand_ce_n   (nand_ce_n),
        .nand_re_n   (nand_re_n),
        .nand_we_n   (nand_we_n),
        .nand_cle    (nand_cle),
        .nand_ale    (nand_ale),
        .nand_wp_n   (nand_wp_n),
        .nand_ryby_n (nand_ryby_n),
        .nand_io     (nand_io)
    );

    // -------------------------------------------------------
    // Descrambler (same module as scrambler)
    // -------------------------------------------------------
    scrambler u_descrambler (
        .clk          (clk),
        .rst_n        (rst_n),
        .seed_valid_i (seed_valid),
        .seed_i       (reg_lba),
        .data_i       (fsm_rd_byte),
        .in_valid_i   (fsm_rd_valid),
        .data_o       (dc_data_out),
        .out_valid_o  (dc_out_valid),
        .byte_count_o ()
    );

    // -------------------------------------------------------
    // Read FIFO
    // -------------------------------------------------------
    fifo #(
        .DATA_WIDTH (8),
        .DEPTH      (PAGE_BYTES)
    ) u_rd_fifo (
        .clk          (clk),
        .rst_n        (rst_n),
        .wr_en_i      (dc_out_valid),
        .wr_data_i    (dc_data_out),
        .full_o       (rd_fifo_full),
        .rd_en_i      (rd_fifo_rd_en),
        .rd_data_o    (rd_fifo_rd_data),
        .empty_o      (rd_fifo_empty),
        .flush_i      (rd_fifo_flush),
        .almost_full_o(),
        .count_o      (rd_fifo_count),
        .overflow_o   (),
        .underflow_o  ()
    );

    // -------------------------------------------------------
    // AXI-S Serializer
    // -------------------------------------------------------
    axis_serializer #(
        .AXIS_WIDTH  (AXIS_WIDTH),
        .PAGE_BYTES  (PAGE_BYTES)
    ) u_ser (
        .clk            (clk),
        .rst_n          (rst_n),
        .in_data_i      (rd_fifo_rd_data),
        .in_valid_i     (!rd_fifo_empty),
        .rd_en_o        (rd_fifo_rd_en),
        .m_axis_tdata   (m_axis_tdata),
        .m_axis_tvalid  (m_axis_tvalid),
        .m_axis_tready  (m_axis_tready),
        .m_axis_tlast   (m_axis_tlast),
        .start_i        (ser_start),
        .done_o         (ser_done)
    );

endmodule