// ============================================================
// flash_channel.sv
// Flash Controller for MX30LF1G28AD (1Gb SLC NAND, x8)
// ============================================================
// Provides a simple internal register interface:
//
//   op_start_i   — pulse to begin operation
//   op_type_i    — 3'b000 RESET
//                  3'b001 READ
//                  3'b010 PROGRAM
//                  3'b011 ERASE
//                  3'b100 READ_STATUS
//   row_addr_i   — 24-bit row (page) address
//   col_addr_i   — 12-bit column address (byte within page)
//   data_i       — write data bus (8-bit per beat)
//   data_wr_i    — strobe: controller samples data_i each cycle this is high
//   data_o       — read data bus
//   data_rd_o    — strobe: valid read byte on data_o
//   busy_o       — high while controller is running any operation
//   done_o       — single-cycle pulse on operation complete
//   status_o     — last status register read from chip
//   fail_o       — SR[0] from last status read (program/erase fail)
//   data_req_o   — high when FSM is in S_PROG_DATA_WRITE and ready
//                  for next byte. Used by top level to gate FIFO read.
//                  Specifically: high when in data write state AND
//                  WE# is not currently low (i.e. not mid-pulse)
//
// NAND geometry (MX30LF1G28AD):
//   Page:  2112 bytes (2048 data + 64 OOB)
//   Block: 64 pages
//   Chip:  1024 blocks = 65536 pages
//
// Address format sent to chip (5 cycles):
//   CA0: col[7:0]
//   CA1: col[11:8]  (only lower 4 bits used)
//   RA0: row[7:0]
//   RA1: row[15:8]
//   RA2: row[23:16]
//
// For erase, only 3 row address cycles are sent (no column).
// ============================================================

module flash_channel #(
    parameter CLK_PERIOD_NS = 10,
    parameter PAGE_BYTES    = 2112,
    parameter COL_BITS      = 12,
    parameter ROW_BITS      = 24
)(
    input  logic                  clk,
    input  logic                  rst_n,

    // ---- Operation interface ------------------------------
    input  logic                  op_start_i,
    input  logic [2:0]            op_type_i,
    input  logic [ROW_BITS-1:0]   row_addr_i,
    input  logic [COL_BITS-1:0]   col_addr_i,

    // Write data feed (for PROGRAM)
    input  logic [7:0]            data_i,
    input  logic                  data_wr_i,

    // Read data output (for READ)
    output logic [7:0]            data_o,
    output logic                  data_rd_o,

    // Status
    output logic                  busy_o,
    output logic                  done_o,
    output logic [7:0]            status_o,
    output logic                  fail_o,

    // Data request — high when FSM wants next write byte
    // Top level uses this to gate FIFO read + scrambler
    output logic                  data_req_o,

    // ---- NAND Flash physical interface -------------------
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
    // Operation type encoding
    // -------------------------------------------------------
    localparam OP_RESET  = 3'b000;
    localparam OP_READ   = 3'b001;
    localparam OP_PROG   = 3'b010;
    localparam OP_ERASE  = 3'b011;
    localparam OP_STATUS = 3'b100;

    // -------------------------------------------------------
    // NAND command bytes
    // -------------------------------------------------------
    localparam CMD_READ1  = 8'h00;
    localparam CMD_READ2  = 8'h30;
    localparam CMD_PROG1  = 8'h80;
    localparam CMD_PROG2  = 8'h10;
    localparam CMD_ERASE1 = 8'h60;
    localparam CMD_ERASE2 = 8'hD0;
    localparam CMD_STATUS = 8'h70;
    localparam CMD_RESET  = 8'hFF;

    // -------------------------------------------------------
    // Timing parameters (clock cycles)
    // -------------------------------------------------------
    localparam TWB_CYC  = (100 + CLK_PERIOD_NS - 1) / CLK_PERIOD_NS;
    localparam TADL_CYC = (70  + CLK_PERIOD_NS - 1) / CLK_PERIOD_NS;
    localparam TWHR_CYC = (60  + CLK_PERIOD_NS - 1) / CLK_PERIOD_NS;
    localparam TWP_CYC  = (10  + CLK_PERIOD_NS - 1) / CLK_PERIOD_NS;
    localparam TRP_CYC  = (10  + CLK_PERIOD_NS - 1) / CLK_PERIOD_NS;
    localparam TREA_CYC = (16  + CLK_PERIOD_NS - 1) / CLK_PERIOD_NS;

    // -------------------------------------------------------
    // State machine
    // -------------------------------------------------------
    typedef enum logic [4:0] {
        S_IDLE,
        S_CMD_WRITE,
        S_ADDR_COL0, S_ADDR_COL1,
        S_ADDR_ROW0, S_ADDR_ROW1, S_ADDR_ROW2,
        S_READ_CMD2, S_READ_WAIT, S_READ_DATA, S_READ_DATA_HOLD,
        S_PROG_WAIT_DATA, S_PROG_DATA_WRITE, S_PROG_CMD2, S_PROG_WAIT,
        S_ERASE_CMD2, S_ERASE_WAIT,
        S_STATUS_TWHR, S_STATUS_READ,
        S_RESET_WAIT,
        S_DONE
    } state_t;

    state_t state;

    // -------------------------------------------------------
    // IO bus control
    // -------------------------------------------------------
    logic [7:0] io_out;
    logic       io_oe;

    assign nand_io = io_oe ? io_out : 8'bz;

    // -------------------------------------------------------
    // Internal registers
    // -------------------------------------------------------
    logic [2:0]          op_type_r;
    logic [ROW_BITS-1:0] row_addr_r;
    logic [COL_BITS-1:0] col_addr_r;
    logic [15:0]         timer;
    logic [12:0]         byte_cnt;

    // -------------------------------------------------------
    // data_req_o — combinational
    // High when FSM is in S_PROG_DATA_WRITE and WE# is idle
    // (not mid-pulse). This tells the top level to read the
    // next byte from the FIFO through the scrambler.
    // -------------------------------------------------------
    assign data_req_o = (state == S_PROG_DATA_WRITE) && nand_we_n && !data_wr_i;

    // -------------------------------------------------------
    // FSM
    // -------------------------------------------------------
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state      <= S_IDLE;
            nand_ce_n  <= 1;
            nand_re_n  <= 1;
            nand_we_n  <= 1;
            nand_cle   <= 0;
            nand_ale   <= 0;
            nand_wp_n  <= 1;
            io_out     <= '0;
            io_oe      <= 0;
            busy_o     <= 0;
            done_o     <= 0;
            data_o     <= '0;
            data_rd_o  <= 0;
            status_o   <= '0;
            fail_o     <= 0;
            op_type_r  <= '0;
            row_addr_r <= '0;
            col_addr_r <= '0;
            timer      <= '0;
            byte_cnt   <= '0;
        end else begin
            done_o    <= 0;
            data_rd_o <= 0;

            case (state)

                // ============================================
                S_IDLE: begin
                    busy_o    <= 0;
                    nand_ce_n <= 1;
                    io_oe     <= 0;

                    if (op_start_i) begin
                        op_type_r  <= op_type_i;
                        row_addr_r <= row_addr_i;
                        col_addr_r <= col_addr_i;
                        busy_o     <= 1;
                        nand_ce_n  <= 0;
                        nand_wp_n  <= 1;
                        io_oe      <= 1;
                        nand_cle   <= 1;
                        nand_ale   <= 0;
                        nand_we_n  <= 0;

                        case (op_type_i)
                            OP_RESET:  io_out <= CMD_RESET;
                            OP_READ:   io_out <= CMD_READ1;
                            OP_PROG:   io_out <= CMD_PROG1;
                            OP_ERASE:  io_out <= CMD_ERASE1;
                            OP_STATUS: io_out <= CMD_STATUS;
                            default:   io_out <= CMD_RESET;
                        endcase

                        timer <= TWP_CYC;
                        state <= S_CMD_WRITE;
                    end
                end

                // ============================================
                S_CMD_WRITE: begin
                    if (timer > 0) begin
                        timer <= timer - 1;
                    end else begin
                        nand_we_n <= 1;
                        nand_cle  <= 0;
                        io_oe     <= 0;

                        case (op_type_r)
                            OP_RESET: begin
                                timer <= TWB_CYC;
                                state <= S_RESET_WAIT;
                            end
                            OP_STATUS: begin
                                timer <= TWHR_CYC;
                                state <= S_STATUS_TWHR;
                            end
                            OP_READ, OP_PROG: begin
                                nand_ale  <= 1;
                                nand_we_n <= 0;
                                io_oe     <= 1;
                                io_out    <= col_addr_r[7:0];
                                timer     <= TWP_CYC;
                                state     <= S_ADDR_COL0;
                            end
                            OP_ERASE: begin
                                nand_ale  <= 1;
                                nand_we_n <= 0;
                                io_oe     <= 1;
                                io_out    <= row_addr_r[7:0];
                                timer     <= TWP_CYC;
                                state     <= S_ADDR_ROW0;
                            end
                            default: state <= S_IDLE;
                        endcase
                    end
                end

                // ============================================
                // Address cycles
                // ============================================
                S_ADDR_COL0: begin
                    if (timer > 0) begin
                        timer <= timer - 1;
                    end else begin
                        nand_we_n <= 1;
                        io_out    <= {4'h0, col_addr_r[11:8]};
                        timer     <= TWP_CYC;
                        state     <= S_ADDR_COL1;
                        nand_we_n <= 0;
                    end
                end

                S_ADDR_COL1: begin
                    if (timer > 0) begin
                        timer <= timer - 1;
                    end else begin
                        nand_we_n <= 1;
                        io_out    <= row_addr_r[7:0];
                        timer     <= TWP_CYC;
                        state     <= S_ADDR_ROW0;
                        nand_we_n <= 0;
                    end
                end

                S_ADDR_ROW0: begin
                    if (timer > 0) begin
                        timer <= timer - 1;
                    end else begin
                        nand_we_n <= 1;
                        io_out    <= row_addr_r[15:8];
                        timer     <= TWP_CYC;
                        state     <= S_ADDR_ROW1;
                        nand_we_n <= 0;
                    end
                end

                S_ADDR_ROW1: begin
                    if (timer > 0) begin
                        timer <= timer - 1;
                    end else begin
                        nand_we_n <= 1;
                        io_out    <= row_addr_r[23:16];
                        timer     <= TWP_CYC;
                        state     <= S_ADDR_ROW2;
                        nand_we_n <= 0;
                    end
                end

                S_ADDR_ROW2: begin
                    if (timer > 0) begin
                        timer <= timer - 1;
                    end else begin
                        nand_we_n <= 1;
                        nand_ale  <= 0;
                        io_oe     <= 0;

                        case (op_type_r)
                            OP_READ: begin
                                nand_cle  <= 1;
                                nand_we_n <= 0;
                                io_oe     <= 1;
                                io_out    <= CMD_READ2;
                                timer     <= TWP_CYC;
                                state     <= S_READ_CMD2;
                            end
                            OP_PROG: begin
                                byte_cnt <= 0;
                                timer    <= TADL_CYC;
                                state    <= S_PROG_WAIT_DATA;
                            end
                            OP_ERASE: begin
                                nand_cle  <= 1;
                                nand_we_n <= 0;
                                io_oe     <= 1;
                                io_out    <= CMD_ERASE2;
                                timer     <= TWP_CYC;
                                state     <= S_ERASE_CMD2;
                            end
                            default: state <= S_IDLE;
                        endcase
                    end
                end

                // ============================================
                // READ flow
                // ============================================
                S_READ_CMD2: begin
                    if (timer > 0) begin
                        timer <= timer - 1;
                    end else begin
                        nand_we_n <= 1;
                        nand_cle  <= 0;
                        io_oe     <= 0;
                        state     <= S_READ_WAIT;
                    end
                end

                S_READ_WAIT: begin
                    if (nand_ryby_n) begin
                        byte_cnt  <= 0;
                        nand_re_n <= 0;
                        timer     <= TREA_CYC;
                        state     <= S_READ_DATA;
                    end
                end

                S_READ_DATA: begin
                    if (timer > 0) begin
                        timer <= timer - 1;
                    end else begin
                        data_o    <= nand_io;
                        data_rd_o <= 1;
                        nand_re_n <= 1;
                        byte_cnt  <= byte_cnt + 1;
                        timer     <= TRP_CYC;
                        state     <= S_READ_DATA_HOLD;
                    end
                end

                S_READ_DATA_HOLD: begin
                    if (timer > 0) begin
                        timer <= timer - 1;
                    end else begin
                        if (byte_cnt >= PAGE_BYTES) begin
                            state <= S_DONE;
                        end else begin
                            nand_re_n <= 0;
                            timer     <= TREA_CYC;
                            state     <= S_READ_DATA;
                        end
                    end
                end

                // ============================================
                // PROGRAM flow
                // ============================================
                S_PROG_WAIT_DATA: begin
                    // tADL delay — wait before accepting data
                    if (timer > 0) begin
                        timer <= timer - 1;
                    end else begin
                        // tADL done — enter data write state
                        // data_req_o goes high combinationally from here
                        byte_cnt <= 0;
                        io_oe    <= 1;
                        state    <= S_PROG_DATA_WRITE;
                    end
                end

                S_PROG_DATA_WRITE: begin
                    // data_req_o is combinational — high when we_n is idle
                    // Top level: sees data_req_o → reads FIFO → scrambles
                    //            → asserts data_wr_i with data_i

                    if (data_wr_i) begin
                        // Latch incoming byte and start WE# pulse
                        io_out    <= data_i;
                        nand_we_n <= 0;
                        timer     <= TWP_CYC;
                        byte_cnt  <= byte_cnt + 1;
                    end else if (!nand_we_n) begin
                        // Mid WE# pulse — count down
                        if (timer > 0)
                            timer <= timer - 1;
                        else
                            nand_we_n <= 1;   // raise WE# — chip latches byte
                    end else if (byte_cnt >= PAGE_BYTES) begin
                        // All bytes written — send program confirm command
                        nand_cle  <= 1;
                        nand_we_n <= 0;
                        io_out    <= CMD_PROG2;
                        timer     <= TWP_CYC;
                        state     <= S_PROG_CMD2;
                    end
                    // else: idle, waiting for next data_wr_i pulse
                    // data_req_o stays high → top level will feed next byte
                end

                S_PROG_CMD2: begin
                    if (timer > 0) begin
                        timer <= timer - 1;
                    end else begin
                        nand_we_n <= 1;
                        nand_cle  <= 0;
                        io_oe     <= 0;
                        state     <= S_PROG_WAIT;
                    end
                end

                S_PROG_WAIT: begin
                    if (nand_ryby_n) begin
                        state <= S_DONE;
                    end
                end

                // ============================================
                // ERASE flow
                // ============================================
                S_ERASE_CMD2: begin
                    if (timer > 0) begin
                        timer <= timer - 1;
                    end else begin
                        nand_we_n <= 1;
                        nand_cle  <= 0;
                        io_oe     <= 0;
                        state     <= S_ERASE_WAIT;
                    end
                end

                S_ERASE_WAIT: begin
                    if (nand_ryby_n) begin
                        state <= S_DONE;
                    end
                end

                // ============================================
                // STATUS READ flow
                // ============================================
                S_STATUS_TWHR: begin
                    if (timer > 0) begin
                        timer <= timer - 1;
                    end else begin
                        nand_re_n <= 0;
                        timer     <= TREA_CYC;
                        state     <= S_STATUS_READ;
                    end
                end

                S_STATUS_READ: begin
                    if (timer > 0) begin
                        timer <= timer - 1;
                    end else begin
                        status_o  <= nand_io;
                        fail_o    <= nand_io[0];
                        nand_re_n <= 1;
                        state     <= S_DONE;
                    end
                end

                // ============================================
                // RESET flow
                // ============================================
                S_RESET_WAIT: begin
                    if (timer > 0) begin
                        timer <= timer - 1;
                    end else if (nand_ryby_n) begin
                        state <= S_DONE;
                    end
                end

                // ============================================
                // DONE
                // ============================================
                S_DONE: begin
                    done_o    <= 1;
                    busy_o    <= 0;
                    nand_ce_n <= 1;
                    nand_re_n <= 1;
                    nand_we_n <= 1;
                    io_oe     <= 0;
                    state     <= S_IDLE;
                end

                default: state <= S_IDLE;

            endcase
        end
    end

endmodule