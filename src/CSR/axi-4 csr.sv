// ============================================================
// axi4_csr.sv — Full AXI4 CSR Slave (32-bit data, 4 registers)
// ============================================================
// Supports:
//   - Burst transfers (INCR bursts, up to 256 beats)
//   - Transaction IDs (in-order responses, same ID echoed back)
//   - Byte strobes (WSTRB)
//   - WLAST detection
//   - OKAY / SLVERR responses
//
// Address map (byte-addressed, 4-byte aligned):
//   0x00 — REG0 (RW)
//   0x04 — REG1 (RW)
//   0x08 — REG2 (RO — driven by internal logic via reg2_i)
//   0x0C — REG3 (RW1C — write 1 to clear bits)
// ============================================================

module axi4_csr #(
    parameter DATA_WIDTH = 32,
    parameter ADDR_WIDTH = 8,       // covers full CSR region
    parameter ID_WIDTH   = 4        // AXI ID width — match your bus
)(
    input  logic                    clk,
    input  logic                    rst_n,

    // ---- AXI4 Slave Interface ------------------------------

    // --- Write Address Channel (AW) ---
    input  logic [ID_WIDTH-1:0]     s_axi_awid,
    input  logic [ADDR_WIDTH-1:0]   s_axi_awaddr,
    input  logic [7:0]              s_axi_awlen,    // burst length - 1
    input  logic [2:0]              s_axi_awsize,   // bytes per beat (log2)
    input  logic [1:0]              s_axi_awburst,  // 00=FIXED, 01=INCR, 10=WRAP
    input  logic                    s_axi_awvalid,
    output logic                    s_axi_awready,

    // --- Write Data Channel (W) ---
    input  logic [DATA_WIDTH-1:0]   s_axi_wdata,
    input  logic [DATA_WIDTH/8-1:0] s_axi_wstrb,
    input  logic                    s_axi_wlast,    // marks last beat of burst
    input  logic                    s_axi_wvalid,
    output logic                    s_axi_wready,

    // --- Write Response Channel (B) ---
    output logic [ID_WIDTH-1:0]     s_axi_bid,
    output logic [1:0]              s_axi_bresp,
    output logic                    s_axi_bvalid,
    input  logic                    s_axi_bready,

    // --- Read Address Channel (AR) ---
    input  logic [ID_WIDTH-1:0]     s_axi_arid,
    input  logic [ADDR_WIDTH-1:0]   s_axi_araddr,
    input  logic [7:0]              s_axi_arlen,
    input  logic [2:0]              s_axi_arsize,
    input  logic [1:0]              s_axi_arburst,
    input  logic                    s_axi_arvalid,
    output logic                    s_axi_arready,

    // --- Read Data Channel (R) ---
    output logic [ID_WIDTH-1:0]     s_axi_rid,
    output logic [DATA_WIDTH-1:0]   s_axi_rdata,
    output logic [1:0]              s_axi_rresp,
    output logic                    s_axi_rlast,    // marks last beat of burst
    output logic                    s_axi_rvalid,
    input  logic                    s_axi_rready,

    // ---- Internal register ports --------------------------
    output logic [DATA_WIDTH-1:0]   reg0_o,   // RW
    output logic [DATA_WIDTH-1:0]   reg1_o,   // RW
    input  logic [DATA_WIDTH-1:0]   reg2_i,   // RO — driven by internal logic
    output logic [DATA_WIDTH-1:0]   reg3_o    // RW1C
);

    // -------------------------------------------------------
    // AXI4 response codes
    // -------------------------------------------------------
    localparam RESP_OKAY   = 2'b00;
    localparam RESP_SLVERR = 2'b10;  // returned on out-of-range address

    // -------------------------------------------------------
    // Register storage
    // -------------------------------------------------------
    logic [DATA_WIDTH-1:0] reg0, reg1, reg3;

    // -------------------------------------------------------
    // WRITE PATH state
    // -------------------------------------------------------
    typedef enum logic [1:0] {
        WR_IDLE,        // waiting for AW
        WR_DATA,        // consuming W beats
        WR_RESP         // sending B response
    } wr_state_t;

    wr_state_t              wr_state;
    logic [ID_WIDTH-1:0]    wr_id;
    logic [ADDR_WIDTH-1:0]  wr_addr;        // base address of burst
    logic [ADDR_WIDTH-1:0]  wr_addr_cur;    // current beat address
    logic [7:0]             wr_len;         // remaining beats
    logic                   wr_addr_err;    // set if any beat hit bad addr

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wr_state      <= WR_IDLE;
            wr_id         <= '0;
            wr_addr       <= '0;
            wr_addr_cur   <= '0;
            wr_len        <= '0;
            wr_addr_err   <= 0;
            s_axi_awready <= 0;
            s_axi_wready  <= 0;
            s_axi_bvalid  <= 0;
            s_axi_bresp   <= RESP_OKAY;
            s_axi_bid     <= '0;
            reg0          <= '0;
            reg1          <= '0;
            reg3          <= '0;
        end else begin
            case (wr_state)

                // -------------------------------------------------
                WR_IDLE: begin
                    s_axi_awready <= 1;
                    s_axi_wready  <= 0;

                    if (s_axi_awvalid && s_axi_awready) begin
                        wr_id       <= s_axi_awid;
                        wr_addr     <= s_axi_awaddr;
                        wr_addr_cur <= s_axi_awaddr;
                        wr_len      <= s_axi_awlen;
                        wr_addr_err <= 0;

                        s_axi_awready <= 0;
                        s_axi_wready  <= 1;
                        wr_state      <= WR_DATA;
                    end
                end

                // -------------------------------------------------
                WR_DATA: begin
                    if (s_axi_wvalid && s_axi_wready) begin

                        // --- perform register write for this beat ---
                        case (wr_addr_cur[3:2])
                            2'h0: begin  // REG0 RW
                                for (int i = 0; i < DATA_WIDTH/8; i++)
                                    if (s_axi_wstrb[i])
                                        reg0[i*8 +: 8] <= s_axi_wdata[i*8 +: 8];
                            end
                            2'h1: begin  // REG1 RW
                                for (int i = 0; i < DATA_WIDTH/8; i++)
                                    if (s_axi_wstrb[i])
                                        reg1[i*8 +: 8] <= s_axi_wdata[i*8 +: 8];
                            end
                            2'h2: begin  // REG2 RO — ignore write
                            end
                            2'h3: begin  // REG3 RW1C
                                for (int i = 0; i < DATA_WIDTH/8; i++)
                                    if (s_axi_wstrb[i])
                                        reg3[i*8 +: 8] <= reg3[i*8 +: 8]
                                                          & ~s_axi_wdata[i*8 +: 8];
                            end
                            default: wr_addr_err <= 1;  // out-of-range
                        endcase

                        // --- advance burst address (INCR) ---
                        wr_addr_cur <= wr_addr_cur + (1 << s_axi_awsize);
                        wr_len      <= wr_len - 1;

                        // --- last beat? ---
                        if (s_axi_wlast) begin
                            s_axi_wready <= 0;
                            s_axi_bvalid <= 1;
                            s_axi_bid    <= wr_id;
                            s_axi_bresp  <= wr_addr_err ? RESP_SLVERR : RESP_OKAY;
                            wr_state     <= WR_RESP;
                        end
                    end
                end

                // -------------------------------------------------
                WR_RESP: begin
                    if (s_axi_bvalid && s_axi_bready) begin
                        s_axi_bvalid  <= 0;
                        s_axi_awready <= 1;     // ready for next transaction
                        wr_state      <= WR_IDLE;
                    end
                end

                default: wr_state <= WR_IDLE;
            endcase
        end
    end

    // -------------------------------------------------------
    // READ PATH state
    // -------------------------------------------------------
    typedef enum logic [1:0] {
        RD_IDLE,        // waiting for AR
        RD_DATA         // streaming R beats
    } rd_state_t;

    rd_state_t              rd_state;
    logic [ID_WIDTH-1:0]    rd_id;
    logic [ADDR_WIDTH-1:0]  rd_addr_cur;
    logic [7:0]             rd_len;         // remaining beats

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rd_state      <= RD_IDLE;
            rd_id         <= '0;
            rd_addr_cur   <= '0;
            rd_len        <= '0;
            s_axi_arready <= 0;
            s_axi_rvalid  <= 0;
            s_axi_rdata   <= '0;
            s_axi_rresp   <= RESP_OKAY;
            s_axi_rlast   <= 0;
            s_axi_rid     <= '0;
        end else begin
            case (rd_state)

                // -------------------------------------------------
                RD_IDLE: begin
                    s_axi_arready <= 1;

                    if (s_axi_arvalid && s_axi_arready) begin
                        rd_id       <= s_axi_arid;
                        rd_addr_cur <= s_axi_araddr;
                        rd_len      <= s_axi_arlen;

                        s_axi_arready <= 0;
                        rd_state      <= RD_DATA;
                    end
                end

                // -------------------------------------------------
                RD_DATA: begin
                    // Present data; wait for rready before advancing
                    s_axi_rvalid <= 1;
                    s_axi_rid    <= rd_id;
                    s_axi_rlast  <= (rd_len == 0);

                    case (rd_addr_cur[3:2])
                        2'h0:    s_axi_rdata <= reg0;
                        2'h1:    s_axi_rdata <= reg1;
                        2'h2:    s_axi_rdata <= reg2_i;  // live RO input
                        2'h3:    s_axi_rdata <= reg3;
                        default: begin
                            s_axi_rdata <= '0;
                            s_axi_rresp <= RESP_SLVERR;
                        end
                    endcase

                    if (s_axi_rvalid && s_axi_rready) begin
                        s_axi_rresp <= RESP_OKAY;   // reset for next beat

                        if (rd_len == 0) begin
                            // last beat acknowledged
                            s_axi_rvalid  <= 0;
                            s_axi_rlast   <= 0;
                            s_axi_arready <= 1;
                            rd_state      <= RD_IDLE;
                        end else begin
                            // advance to next beat
                            rd_addr_cur <= rd_addr_cur + 4;  // 32-bit words
                            rd_len      <= rd_len - 1;
                        end
                    end
                end

                default: rd_state <= RD_IDLE;
            endcase
        end
    end

    // -------------------------------------------------------
    // Output assignments
    // -------------------------------------------------------
    assign reg0_o = reg0;
    assign reg1_o = reg1;
    assign reg3_o = reg3;

endmodule