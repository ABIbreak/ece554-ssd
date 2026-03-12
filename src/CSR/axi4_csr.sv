// ============================================================
// axi4_csr.sv — Full AXI4 CSR Slave, parametric access types
// ============================================================
// Each register's behavior is set via ACCESS parameter bits:
//
//   ACCESS[r*2 +: 2] = 2'b00 — RW   (read/write)
//   ACCESS[r*2 +: 2] = 2'b01 — RO   (read-only, driven by reg_i port)
//   ACCESS[r*2 +: 2] = 2'b10 — RW1C (write-1-to-clear)
//   ACCESS[r*2 +: 2] = 2'b11 — WO   (write-only, reads return 0)
//
// Example instantiation — 4 registers:
//
//   axi4_csr #(
//       .NUM_REGS (4),
//       .ACCESS   ({`REG_RW1C, `REG_RO, `REG_RW, `REG_RW})
//                   REG3        REG2     REG1      REG0
//   ) u_csr ( ... );
//
// Ports:
//   reg_i[r] — live input for RO registers (ignored for others)
//   reg_o[r] — stored value output (RW/RW1C/WO); mirrors reg_i for RO
// ============================================================

`define REG_RW   2'b00
`define REG_RO   2'b01
`define REG_RW1C 2'b10
`define REG_WO   2'b11

module axi4_csr #(
    parameter int                  DATA_WIDTH = 32,
    parameter int                  ADDR_WIDTH = 8,
    parameter int                  ID_WIDTH   = 4,
    parameter int                  NUM_REGS   = 4,

    // 2 bits per register: ACCESS[r*2 +: 2] = access type for register r
    // Pack LSB = REG0, MSB = REG(NUM_REGS-1)
    parameter [NUM_REGS*2-1:0]     ACCESS     = '0    // default: all RW
)(
    input  logic                                    clk,
    input  logic                                    rst_n,

    // ---- AXI4 Slave Interface ----------------------------

    // Write Address Channel
    input  logic [ID_WIDTH-1:0]                     s_axi_awid,
    input  logic [ADDR_WIDTH-1:0]                   s_axi_awaddr,
    input  logic [7:0]                              s_axi_awlen,
    input  logic [2:0]                              s_axi_awsize,
    input  logic [1:0]                              s_axi_awburst,
    input  logic                                    s_axi_awvalid,
    output logic                                    s_axi_awready,

    // Write Data Channel
    input  logic [DATA_WIDTH-1:0]                   s_axi_wdata,
    input  logic [DATA_WIDTH/8-1:0]                 s_axi_wstrb,
    input  logic                                    s_axi_wlast,
    input  logic                                    s_axi_wvalid,
    output logic                                    s_axi_wready,

    // Write Response Channel
    output logic [ID_WIDTH-1:0]                     s_axi_bid,
    output logic [1:0]                              s_axi_bresp,
    output logic                                    s_axi_bvalid,
    input  logic                                    s_axi_bready,

    // Read Address Channel
    input  logic [ID_WIDTH-1:0]                     s_axi_arid,
    input  logic [ADDR_WIDTH-1:0]                   s_axi_araddr,
    input  logic [7:0]                              s_axi_arlen,
    input  logic [2:0]                              s_axi_arsize,
    input  logic [1:0]                              s_axi_arburst,
    input  logic                                    s_axi_arvalid,
    output logic                                    s_axi_arready,

    // Read Data Channel
    output logic [ID_WIDTH-1:0]                     s_axi_rid,
    output logic [DATA_WIDTH-1:0]                   s_axi_rdata,
    output logic [1:0]                              s_axi_rresp,
    output logic                                    s_axi_rlast,
    output logic                                    s_axi_rvalid,
    input  logic                                    s_axi_rready,

    // ---- Register ports ----------------------------------
    input  logic [NUM_REGS-1:0][DATA_WIDTH-1:0]    reg_i,  // RO live inputs
    output logic [NUM_REGS-1:0][DATA_WIDTH-1:0]    reg_o   // all reg outputs
);

    // -------------------------------------------------------
    // Local access type constants
    // -------------------------------------------------------
    localparam [1:0] RW   = 2'b00;
    localparam [1:0] RO   = 2'b01;
    localparam [1:0] RW1C = 2'b10;
    localparam [1:0] WO   = 2'b11;

    localparam [1:0] RESP_OKAY   = 2'b00;
    localparam [1:0] RESP_SLVERR = 2'b10;

    // -------------------------------------------------------
    // Register file — stores state for RW / RW1C / WO regs
    // -------------------------------------------------------
    logic [NUM_REGS-1:0][DATA_WIDTH-1:0] regfile;

    // Convert a byte address to a register index
    // Bits [2 + $clog2(NUM_REGS) - 1 : 2] select the word
    function automatic int unsigned reg_idx(input logic [ADDR_WIDTH-1:0] addr);
        return int'(addr[$clog2(NUM_REGS)+1 : 2]);
    endfunction

    // -------------------------------------------------------
    // WRITE PATH
    // -------------------------------------------------------
    typedef enum logic [1:0] { WR_IDLE, WR_DATA, WR_RESP } wr_state_t;

    wr_state_t              wr_state;
    logic [ID_WIDTH-1:0]    wr_id;
    logic [ADDR_WIDTH-1:0]  wr_addr_cur;
    logic [7:0]             wr_len;
    logic                   wr_addr_err;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wr_state      <= WR_IDLE;
            wr_id         <= '0;
            wr_addr_cur   <= '0;
            wr_len        <= '0;
            wr_addr_err   <= 0;
            s_axi_awready <= 0;
            s_axi_wready  <= 0;
            s_axi_bvalid  <= 0;
            s_axi_bresp   <= RESP_OKAY;
            s_axi_bid     <= '0;
            regfile       <= '0;
        end else begin
            case (wr_state)

                // ---- Wait for write address ----------------
                WR_IDLE: begin
                    s_axi_awready <= 1;
                    s_axi_wready  <= 0;

                    if (s_axi_awvalid && s_axi_awready) begin
                        wr_id         <= s_axi_awid;
                        wr_addr_cur   <= s_axi_awaddr;
                        wr_len        <= s_axi_awlen;
                        wr_addr_err   <= 0;
                        s_axi_awready <= 0;
                        s_axi_wready  <= 1;
                        wr_state      <= WR_DATA;
                    end
                end

                // ---- Consume write data beats --------------
                WR_DATA: begin
                    if (s_axi_wvalid && s_axi_wready) begin
                        automatic int unsigned idx = reg_idx(wr_addr_cur);

                        if (idx >= NUM_REGS) begin
                            wr_addr_err <= 1;   // flag bad address
                        end else begin
                            // Apply write based on this register's access type
                            case (ACCESS[idx*2 +: 2])

                                RW: begin
                                    for (int i = 0; i < DATA_WIDTH/8; i++)
                                        if (s_axi_wstrb[i])
                                            regfile[idx][i*8 +: 8] <= s_axi_wdata[i*8 +: 8];
                                end

                                RO: begin
                                    // Silently ignore — host cannot overwrite RO regs
                                end

                                RW1C: begin
                                    // Writing a 1 clears that bit; writing 0 has no effect
                                    for (int i = 0; i < DATA_WIDTH/8; i++)
                                        if (s_axi_wstrb[i])
                                            regfile[idx][i*8 +: 8] <=
                                                regfile[idx][i*8 +: 8] & ~s_axi_wdata[i*8 +: 8];
                                end

                                WO: begin
                                    // Stored but not readable back
                                    for (int i = 0; i < DATA_WIDTH/8; i++)
                                        if (s_axi_wstrb[i])
                                            regfile[idx][i*8 +: 8] <= s_axi_wdata[i*8 +: 8];
                                end

                            endcase
                        end

                        // Advance burst address
                        wr_addr_cur <= wr_addr_cur + (1 << s_axi_awsize);
                        wr_len      <= wr_len - 1;

                        // Last beat — move to response
                        if (s_axi_wlast) begin
                            s_axi_wready <= 0;
                            s_axi_bvalid <= 1;
                            s_axi_bid    <= wr_id;
                            s_axi_bresp  <= wr_addr_err ? RESP_SLVERR : RESP_OKAY;
                            wr_state     <= WR_RESP;
                        end
                    end
                end

                // ---- Send write response -------------------
                WR_RESP: begin
                    if (s_axi_bvalid && s_axi_bready) begin
                        s_axi_bvalid  <= 0;
                        s_axi_awready <= 1;
                        wr_state      <= WR_IDLE;
                    end
                end

                default: wr_state <= WR_IDLE;
            endcase
        end
    end

    // -------------------------------------------------------
    // READ PATH
    // -------------------------------------------------------
    typedef enum logic [1:0] { RD_IDLE, RD_DATA } rd_state_t;

    rd_state_t              rd_state;
    logic [ID_WIDTH-1:0]    rd_id;
    logic [ADDR_WIDTH-1:0]  rd_addr_cur;
    logic [7:0]             rd_len;

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

                // ---- Wait for read address -----------------
                RD_IDLE: begin
                    s_axi_arready <= 1;

                    if (s_axi_arvalid && s_axi_arready) begin
                        rd_id         <= s_axi_arid;
                        rd_addr_cur   <= s_axi_araddr;
                        rd_len        <= s_axi_arlen;
                        s_axi_arready <= 0;
                        rd_state      <= RD_DATA;
                    end
                end

                // ---- Stream read data beats ----------------
                RD_DATA: begin
                    automatic int unsigned idx = reg_idx(rd_addr_cur);

                    s_axi_rvalid <= 1;
                    s_axi_rid    <= rd_id;
                    s_axi_rlast  <= (rd_len == 0);

                    if (idx >= NUM_REGS) begin
                        s_axi_rdata <= '0;
                        s_axi_rresp <= RESP_SLVERR;
                    end else begin
                        s_axi_rresp <= RESP_OKAY;
                        case (ACCESS[idx*2 +: 2])
                            RW:   s_axi_rdata <= regfile[idx];   // stored value
                            RO:   s_axi_rdata <= reg_i[idx];     // live input
                            RW1C: s_axi_rdata <= regfile[idx];   // stored value
                            WO:   s_axi_rdata <= '0;             // unreadable
                        endcase
                    end

                    if (s_axi_rvalid && s_axi_rready) begin
                        s_axi_rresp <= RESP_OKAY;

                        if (rd_len == 0) begin
                            // Last beat acknowledged — return to idle
                            s_axi_rvalid  <= 0;
                            s_axi_rlast   <= 0;
                            s_axi_arready <= 1;
                            rd_state      <= RD_IDLE;
                        end else begin
                            rd_addr_cur <= rd_addr_cur + 4;
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
    always_comb begin
        for (int r = 0; r < NUM_REGS; r++) begin
            // RO registers: pass reg_i straight through on output
            // All others: expose stored regfile value
            reg_o[r] = (ACCESS[r*2 +: 2] == RO) ? reg_i[r] : regfile[r];
        end
    end

endmodule