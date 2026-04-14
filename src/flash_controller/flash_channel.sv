// ============================================================
// flash_channel.sv
// Flash Controller for MX30LF1G28AD (1Gb SLC NAND, x8)
// ============================================================

module flash_channel #(
    parameter CLK_PERIOD_NS = 10,
    parameter PAGE_BYTES    = 2112,
    parameter COL_BITS      = 12,
    parameter ROW_BITS      = 24
)(
    input  logic                  clk,
    input  logic                  rst_n,

    input  logic                  op_start_i,
    input  logic [2:0]            op_type_i,
    input  logic [ROW_BITS-1:0]   row_addr_i,
    input  logic [COL_BITS-1:0]   col_addr_i,

    input  logic [7:0]            data_i,
    input  logic                  data_wr_i,

    output logic [7:0]            data_o,
    output logic                  data_rd_o,

    output logic                  busy_o,
    output logic                  done_o,
    output logic [7:0]            status_o,
    output logic                  fail_o,
    output logic                  data_req_o,

    output logic                  nand_ce_n,
    output logic                  nand_re_n,
    output logic                  nand_we_n,
    output logic                  nand_cle,
    output logic                  nand_ale,
    output logic                  nand_wp_n,
    input  logic                  nand_ryby_n,
    inout  wire  [7:0]            nand_io
);

    localparam OP_RESET  = 3'b000;
    localparam OP_READ   = 3'b001;
    localparam OP_PROG   = 3'b010;
    localparam OP_ERASE  = 3'b011;
    localparam OP_STATUS = 3'b100;

    localparam CMD_READ1  = 8'h00;
    localparam CMD_READ2  = 8'h30;
    localparam CMD_PROG1  = 8'h80;
    localparam CMD_PROG2  = 8'h10;
    localparam CMD_ERASE1 = 8'h60;
    localparam CMD_ERASE2 = 8'hD0;
    localparam CMD_STATUS = 8'h70;
    localparam CMD_RESET  = 8'hFF;

    // -------------------------------------------------------
    // Timing parameters (all in clock cycles)
    // TWH_CYC covers Twh=7ns, Tclh=5ns, Talh=5ns, Tdh=5ns
    // -------------------------------------------------------
    localparam TWB_CYC  = (100 + CLK_PERIOD_NS - 1) / CLK_PERIOD_NS;
    localparam TADL_CYC = (70  + CLK_PERIOD_NS - 1) / CLK_PERIOD_NS;
    localparam TWHR_CYC = (60  + CLK_PERIOD_NS - 1) / CLK_PERIOD_NS;
    localparam TWP_CYC  = (10  + CLK_PERIOD_NS - 1) / CLK_PERIOD_NS;
    localparam TWH_CYC  = (10  + CLK_PERIOD_NS - 1) / CLK_PERIOD_NS;
    localparam TRP_CYC  = (10  + CLK_PERIOD_NS - 1) / CLK_PERIOD_NS;
    localparam TREA_CYC = (16  + CLK_PERIOD_NS - 1) / CLK_PERIOD_NS;
    localparam TRR_CYC  = (20  + CLK_PERIOD_NS - 1) / CLK_PERIOD_NS;

    // -------------------------------------------------------
    // States
    // Every WE# write has a paired _HOLD state that keeps
    // CLE/ALE/IO stable for TWH_CYC after WE# rises.
    // S_READ_ALE_WAIT and S_ERASE_ALE_WAIT ensure ALE is
    // stable low before CLE and WE# are asserted for the
    // second command byte.
    // -------------------------------------------------------
    typedef enum logic [5:0] {
        S_IDLE,
        S_CMD_WRITE,        S_CMD_HOLD,
        S_ADDR_COL0,        S_ADDR_COL0_HOLD,
        S_ADDR_COL1,        S_ADDR_COL1_HOLD,
        S_ADDR_ROW0,        S_ADDR_ROW0_HOLD,
        S_ADDR_ROW1,        S_ADDR_ROW1_HOLD,
        S_ADDR_ROW2,        S_ADDR_ROW2_HOLD,
        S_READ_ALE_WAIT,                        // ALE→low settle before CMD2
        S_READ_CMD2,        S_READ_CMD2_HOLD,
        S_READ_BUSYWAIT,
        S_READ_WAIT,        S_READ_TRR,
        S_READ_DATA,        S_READ_DATA_HOLD,
        S_PROG_WAIT_DATA,   S_PROG_DATA_WRITE,
        S_PROG_CMD2,        S_PROG_CMD2_HOLD,
        S_PROG_WAIT,
        S_ERASE_ALE_WAIT,                       // ALE→low settle before CMD2
        S_ERASE_CMD2,       S_ERASE_CMD2_HOLD,
        S_ERASE_WAIT,
        S_STATUS_TWHR,      S_STATUS_READ,
        S_RESET_WAIT,
        S_DONE
    } state_t;

    state_t state;

    logic [7:0] io_out;
    logic       io_oe;
    assign nand_io = io_oe ? io_out : 8'bz;

    logic [2:0]          op_type_r;
    logic [ROW_BITS-1:0] row_addr_r;
    logic [COL_BITS-1:0] col_addr_r;
    logic [15:0]         timer;
    logic [12:0]         byte_cnt;

    assign data_req_o = (state == S_PROG_DATA_WRITE) &&
                         nand_we_n && !data_wr_i && (timer == 0);

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state      <= S_IDLE;
            nand_ce_n  <= 1; nand_re_n <= 1; nand_we_n <= 1;
            nand_cle   <= 0; nand_ale  <= 0; nand_wp_n <= 1;
            io_out     <= '0; io_oe    <= 0;
            busy_o     <= 0;  done_o   <= 0;
            data_o     <= '0; data_rd_o <= 0;
            status_o   <= '0; fail_o   <= 0;
            op_type_r  <= '0; row_addr_r <= '0; col_addr_r <= '0;
            timer      <= '0; byte_cnt   <= '0;
        end else begin
            done_o    <= 0;
            data_rd_o <= 0;

            case (state)

                // ==========================================
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

                // ---- First command byte ------------------
                S_CMD_WRITE: begin
                    if (timer > 0) timer <= timer - 1;
                    else begin
                        nand_we_n <= 1;          // WE# high — CLE/IO still held
                        timer     <= TWH_CYC;
                        state     <= S_CMD_HOLD;
                    end
                end

                S_CMD_HOLD: begin
                    if (timer > 0) timer <= timer - 1;
                    else begin
                        nand_cle <= 0;           // safe to release CLE now
                        io_oe    <= 0;
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

                // ---- Address cycles ----------------------
                S_ADDR_COL0: begin
                    if (timer > 0) timer <= timer - 1;
                    else begin
                        nand_we_n <= 1;
                        timer     <= TWH_CYC;
                        state     <= S_ADDR_COL0_HOLD;
                    end
                end
                S_ADDR_COL0_HOLD: begin
                    if (timer > 0) timer <= timer - 1;
                    else begin
                        io_out    <= {4'h0, col_addr_r[11:8]};
                        nand_we_n <= 0;
                        timer     <= TWP_CYC;
                        state     <= S_ADDR_COL1;
                    end
                end

                S_ADDR_COL1: begin
                    if (timer > 0) timer <= timer - 1;
                    else begin
                        nand_we_n <= 1;
                        timer     <= TWH_CYC;
                        state     <= S_ADDR_COL1_HOLD;
                    end
                end
                S_ADDR_COL1_HOLD: begin
                    if (timer > 0) timer <= timer - 1;
                    else begin
                        io_out    <= row_addr_r[7:0];
                        nand_we_n <= 0;
                        timer     <= TWP_CYC;
                        state     <= S_ADDR_ROW0;
                    end
                end

                S_ADDR_ROW0: begin
                    if (timer > 0) timer <= timer - 1;
                    else begin
                        nand_we_n <= 1;
                        timer     <= TWH_CYC;
                        state     <= S_ADDR_ROW0_HOLD;
                    end
                end
                S_ADDR_ROW0_HOLD: begin
                    if (timer > 0) timer <= timer - 1;
                    else begin
                        io_out    <= row_addr_r[15:8];
                        nand_we_n <= 0;
                        timer     <= TWP_CYC;
                        state     <= S_ADDR_ROW1;
                    end
                end

                S_ADDR_ROW1: begin
                    if (timer > 0) timer <= timer - 1;
                    else begin
                        nand_we_n <= 1;
                        timer     <= TWH_CYC;
                        state     <= S_ADDR_ROW1_HOLD;
                    end
                end
                S_ADDR_ROW1_HOLD: begin
                    if (timer > 0) timer <= timer - 1;
                    else begin
                        io_out    <= row_addr_r[23:16];
                        nand_we_n <= 0;
                        timer     <= TWP_CYC;
                        state     <= S_ADDR_ROW2;
                    end
                end

                S_ADDR_ROW2: begin
                    if (timer > 0) timer <= timer - 1;
                    else begin
                        nand_we_n <= 1;
                        timer     <= TWH_CYC;
                        state     <= S_ADDR_ROW2_HOLD;
                    end
                end

                // After last address byte WE# is high and ALE is still high.
                // Drop ALE first and wait TWH_CYC for Talh hold,
                // then go to ALE_WAIT for one more cycle of ALE=0 settle
                // before asserting CLE and WE# for the second command.
                S_ADDR_ROW2_HOLD: begin
                    if (timer > 0) timer <= timer - 1;
                    else begin
                        nand_ale <= 0;   // drop ALE — Talh satisfied by TWH_CYC above
                        io_oe    <= 0;
                        case (op_type_r)
                            OP_READ: begin
                                timer <= TWH_CYC;  // one more settle cycle
                                state <= S_READ_ALE_WAIT;
                            end
                            OP_PROG: begin
                                byte_cnt <= 0;
                                timer    <= TADL_CYC;
                                state    <= S_PROG_WAIT_DATA;
                            end
                            OP_ERASE: begin
                                timer <= TWH_CYC;  // one more settle cycle
                                state <= S_ERASE_ALE_WAIT;
                            end
                            default: state <= S_IDLE;
                        endcase
                    end
                end

                // ALE is now stable low — safe to assert CLE and WE#
                S_READ_ALE_WAIT: begin
                    if (timer > 0) timer <= timer - 1;
                    else begin
                        nand_cle  <= 1;
                        nand_we_n <= 0;
                        io_oe     <= 1;
                        io_out    <= CMD_READ2;
                        timer     <= TWP_CYC;
                        state     <= S_READ_CMD2;
                    end
                end

                S_ERASE_ALE_WAIT: begin
                    if (timer > 0) timer <= timer - 1;
                    else begin
                        nand_cle  <= 1;
                        nand_we_n <= 0;
                        io_oe     <= 1;
                        io_out    <= CMD_ERASE2;
                        timer     <= TWP_CYC;
                        state     <= S_ERASE_CMD2;
                    end
                end

                // ---- READ flow ---------------------------
                S_READ_CMD2: begin
                    if (timer > 0) timer <= timer - 1;
                    else begin
                        nand_we_n <= 1;
                        timer     <= TWH_CYC;
                        state     <= S_READ_CMD2_HOLD;
                    end
                end
                // After S_READ_CMD2_HOLD, go to S_READ_BUSYWAIT first
                S_READ_CMD2_HOLD: begin
                    if (timer > 0) timer <= timer - 1;
                    else begin
                        nand_cle <= 0;
                        io_oe    <= 0;
                        state    <= S_READ_BUSYWAIT;  // wait for R/B# to go LOW first
                    end
                end

                // New state: wait for R/B# to assert low (chip is busy)
                S_READ_BUSYWAIT: begin
                    if (!nand_ryby_n) state <= S_READ_WAIT;
                end

                // Existing: wait for R/B# to go back HIGH (chip ready)
                S_READ_WAIT: begin
                    if (nand_ryby_n) begin
                        timer <= TRR_CYC;
                        state <= S_READ_TRR;
                    end
                end

                S_READ_TRR: begin
                    if (timer > 0) timer <= timer - 1;
                    else begin
                        byte_cnt  <= 0;
                        nand_re_n <= 0;
                        timer     <= TREA_CYC;
                        state     <= S_READ_DATA;
                    end
                end

                S_READ_DATA: begin
                    if (timer > 0) timer <= timer - 1;
                    else begin
                        data_o    <= nand_io;
                        data_rd_o <= 1;
                        nand_re_n <= 1;
                        byte_cnt  <= byte_cnt + 1;
                        timer     <= TRP_CYC;
                        state     <= S_READ_DATA_HOLD;
                    end
                end

                S_READ_DATA_HOLD: begin
                    if (timer > 0) timer <= timer - 1;
                    else begin
                        if (byte_cnt >= PAGE_BYTES)
                            state <= S_DONE;
                        else begin
                            nand_re_n <= 0;
                            timer     <= TREA_CYC;
                            state     <= S_READ_DATA;
                        end
                    end
                end

                // ---- PROGRAM flow ------------------------
                S_PROG_WAIT_DATA: begin
                    if (timer > 0) timer <= timer - 1;
                    else begin
                        byte_cnt <= 0;
                        io_oe    <= 1;
                        state    <= S_PROG_DATA_WRITE;
                    end
                end

                S_PROG_DATA_WRITE: begin
                    if (data_wr_i) begin
                        io_out    <= data_i;
                        nand_we_n <= 0;
                        timer     <= TWP_CYC;
                        byte_cnt  <= byte_cnt + 1;
                    end else if (!nand_we_n) begin
                        if (timer > 0) timer <= timer - 1;
                        else           nand_we_n <= 1;
                    end else if (byte_cnt >= PAGE_BYTES) begin
                        timer <= TWH_CYC;
                        state <= S_PROG_CMD2;
                    end
                end

                S_PROG_CMD2: begin
                    if (timer > 0) timer <= timer - 1;
                    else begin
                        nand_cle  <= 1;
                        nand_we_n <= 0;
                        io_out    <= CMD_PROG2;
                        timer     <= TWP_CYC;
                        state     <= S_PROG_CMD2_HOLD;
                    end
                end

                S_PROG_CMD2_HOLD: begin
                    if (timer > 0) timer <= timer - 1;
                    else begin
                        nand_we_n <= 1;
                        timer     <= TWH_CYC;
                        state     <= S_PROG_WAIT;
                    end
                end

                S_PROG_WAIT: begin
                    if (nand_cle) begin
                        nand_cle <= 0;
                        io_oe    <= 0;
                    end else if (nand_ryby_n) begin
                        state <= S_DONE;
                    end
                end

                // ---- ERASE flow --------------------------
                S_ERASE_CMD2: begin
                    if (timer > 0) timer <= timer - 1;
                    else begin
                        nand_we_n <= 1;
                        timer     <= TWH_CYC;
                        state     <= S_ERASE_CMD2_HOLD;
                    end
                end
                S_ERASE_CMD2_HOLD: begin
                    if (timer > 0) timer <= timer - 1;
                    else begin
                        nand_cle <= 0;
                        io_oe    <= 0;
                        state    <= S_ERASE_WAIT;
                    end
                end

                S_ERASE_WAIT: begin
                    if (nand_ryby_n) state <= S_DONE;
                end

                // ---- STATUS READ -------------------------
                S_STATUS_TWHR: begin
                    if (timer > 0) timer <= timer - 1;
                    else begin
                        nand_re_n <= 0;
                        timer     <= TREA_CYC;
                        state     <= S_STATUS_READ;
                    end
                end

                S_STATUS_READ: begin
                    if (timer > 0) timer <= timer - 1;
                    else begin
                        status_o  <= nand_io;
                        fail_o    <= nand_io[0];
                        nand_re_n <= 1;
                        state     <= S_DONE;
                    end
                end

                // ---- RESET flow --------------------------
                S_RESET_WAIT: begin
                    if (timer > 0) timer <= timer - 1;
                    else if (nand_ryby_n) state <= S_DONE;
                end

                // ---- DONE --------------------------------
                S_DONE: begin
                    done_o    <= 1;
                    busy_o    <= 0;
                    nand_ce_n <= 1;
                    nand_re_n <= 1;
                    nand_we_n <= 1;
                    nand_cle  <= 0;
                    nand_ale  <= 0;
                    io_oe     <= 0;
                    state     <= S_IDLE;
                end

                default: state <= S_IDLE;

            endcase
        end
    end

endmodule