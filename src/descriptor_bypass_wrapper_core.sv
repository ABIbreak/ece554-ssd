`default_nettype none

// descriptor_bypass_wrapper_core.sv
//
// AXI-Lite slave wrapper around the XDMA descriptor bypass ports (PG195 v4.1
// Tables 35 & 36).  Software fills the descriptor fields via register writes,
// then writes 1 to the GO register.  The module waits for dsc_byp_ready and
// pulses dsc_byp_load for exactly one axi_aclk cycle (PG195 Figure 8).
//
// Register map (byte addresses):
//   H2C base 0x00, C2H base 0x40 — layout identical for each direction
//   +0x00  src_addr_lo  [31:0]   RW  lower 32 bits of source address
//   +0x04  src_addr_hi  [31:0]   RW  upper 32 bits of source address
//   +0x08  dst_addr_lo  [31:0]   RW  lower 32 bits of destination address
//   +0x0C  dst_addr_hi  [31:0]   RW  upper 32 bits of destination address
//   +0x10  len          [27:0]   RW  transfer length in bytes
//   +0x14  ctl          [15:0]   RW  descriptor control word
//   +0x18  go           [0]      WO  write 1 to trigger load (self-clearing)
//   +0x1C  status       [0]      RO  reflects dsc_byp_ready

module descriptor_bypass_wrapper_core (
    // AXI-Lite slave
    input  logic        s_axil_aclk,
    input  logic        s_axil_aresetn,

    input  logic [31:0] s_axil_awaddr,
    input  logic        s_axil_awvalid,
    output logic        s_axil_awready,

    input  logic [31:0] s_axil_wdata,
    input  logic [3:0]  s_axil_wstrb,
    input  logic        s_axil_wvalid,
    output logic        s_axil_wready,

    output logic [1:0]  s_axil_bresp,
    output logic        s_axil_bvalid,
    input  logic        s_axil_bready,

    input  logic [31:0] s_axil_araddr,
    input  logic        s_axil_arvalid,
    output logic        s_axil_arready,

    output logic [31:0] s_axil_rdata,
    output logic [1:0]  s_axil_rresp,
    output logic        s_axil_rvalid,
    input  logic        s_axil_rready,

    // H2C descriptor bypass (xdma ports)
    input  logic        h2c_dsc_byp_ready,
    output logic        h2c_dsc_byp_load,
    output logic [63:0] h2c_dsc_byp_src_addr,
    output logic [63:0] h2c_dsc_byp_dst_addr,
    output logic [27:0] h2c_dsc_byp_len,
    output logic [15:0] h2c_dsc_byp_ctl,

    // C2H descriptor bypass (xdma ports)
    input  logic        c2h_dsc_byp_ready,
    output logic        c2h_dsc_byp_load,
    output logic [63:0] c2h_dsc_byp_src_addr,
    output logic [63:0] c2h_dsc_byp_dst_addr,
    output logic [27:0] c2h_dsc_byp_len,
    output logic [15:0] c2h_dsc_byp_ctl
);

    // ----------------------------------------------------------------
    // Load pending flags
    // ----------------------------------------------------------------
    logic h2c_go_pending;
    logic c2h_go_pending;

    // ----------------------------------------------------------------
    // Load pulse generation
    // When go is written, set pending. Pulse load for one cycle as
    // soon as (or while) ready is high, then clear pending.
    // ----------------------------------------------------------------
    always_ff @(posedge s_axil_aclk) begin
        if (!s_axil_aresetn) begin
            h2c_dsc_byp_load <= 1'b0;
            c2h_dsc_byp_load <= 1'b0;
        end else begin
            h2c_dsc_byp_load <= h2c_go_pending && h2c_dsc_byp_ready;
            c2h_dsc_byp_load <= c2h_go_pending && c2h_dsc_byp_ready;
        end
    end

    // ----------------------------------------------------------------
    // AXI-Lite write path
    // Accepts AW and W independently; completes when both received.
    // ----------------------------------------------------------------
    logic        aw_done;
    logic        w_done;
    logic [7:0]  wr_addr_lat;
    logic [31:0] wr_data_lat;

    // Resolved write operands (combinational)
    logic [7:0]  wr_addr;
    logic [31:0] wr_data;
    logic        wr_fire;   // both AW and W received this cycle or prior

    assign wr_addr  = aw_done ? wr_addr_lat : s_axil_awaddr[7:0];
    assign wr_data  = w_done  ? wr_data_lat : s_axil_wdata;
    assign wr_fire  = (aw_done || (s_axil_awvalid && s_axil_awready)) &&
                      (w_done  || (s_axil_wvalid  && s_axil_wready));

    always_ff @(posedge s_axil_aclk) begin
        if (!s_axil_aresetn) begin
            s_axil_awready        <= 1'b1;
            s_axil_wready         <= 1'b1;
            s_axil_bvalid         <= 1'b0;
            s_axil_bresp          <= 2'b00;
            aw_done               <= 1'b0;
            w_done                <= 1'b0;
            wr_addr_lat           <= '0;
            wr_data_lat           <= '0;

            h2c_dsc_byp_src_addr  <= '0;
            h2c_dsc_byp_dst_addr  <= '0;
            h2c_dsc_byp_len       <= '0;
            h2c_dsc_byp_ctl       <= '0;
            h2c_go_pending        <= 1'b0;

            c2h_dsc_byp_src_addr  <= '0;
            c2h_dsc_byp_dst_addr  <= '0;
            c2h_dsc_byp_len       <= '0;
            c2h_dsc_byp_ctl       <= '0;
            c2h_go_pending        <= 1'b0;

        end else begin

            // Clear go_pending once load fires
            if (h2c_dsc_byp_load) h2c_go_pending <= 1'b0;
            if (c2h_dsc_byp_load) c2h_go_pending <= 1'b0;

            // Latch write address
            if (s_axil_awvalid && s_axil_awready) begin
                wr_addr_lat    <= s_axil_awaddr[7:0];
                aw_done        <= 1'b1;
                s_axil_awready <= 1'b0;
            end

            // Latch write data
            if (s_axil_wvalid && s_axil_wready) begin
                wr_data_lat   <= s_axil_wdata;
                w_done        <= 1'b1;
                s_axil_wready <= 1'b0;
            end

            // Both address and data received — perform register write
            if (wr_fire) begin
                case (wr_addr[7:2])
                    // H2C registers (base 0x00)
                    6'h00: h2c_dsc_byp_src_addr[31:0]  <= wr_data;
                    6'h01: h2c_dsc_byp_src_addr[63:32] <= wr_data;
                    6'h02: h2c_dsc_byp_dst_addr[31:0]  <= wr_data;
                    6'h03: h2c_dsc_byp_dst_addr[63:32] <= wr_data;
                    6'h04: h2c_dsc_byp_len             <= wr_data[27:0];
                    6'h05: h2c_dsc_byp_ctl             <= wr_data[15:0];
                    6'h06: if (wr_data[0]) h2c_go_pending <= 1'b1;  // GO
                    6'h07: /* status RO */ ;

                    // C2H registers (base 0x40)
                    6'h10: c2h_dsc_byp_src_addr[31:0]  <= wr_data;
                    6'h11: c2h_dsc_byp_src_addr[63:32] <= wr_data;
                    6'h12: c2h_dsc_byp_dst_addr[31:0]  <= wr_data;
                    6'h13: c2h_dsc_byp_dst_addr[63:32] <= wr_data;
                    6'h14: c2h_dsc_byp_len             <= wr_data[27:0];
                    6'h15: c2h_dsc_byp_ctl             <= wr_data[15:0];
                    6'h16: if (wr_data[0]) c2h_go_pending <= 1'b1;  // GO
                    6'h17: /* status RO */ ;

                    default: ; // unmapped — ignore
                endcase

                aw_done        <= 1'b0;
                w_done         <= 1'b0;
                s_axil_bvalid  <= 1'b1;
                s_axil_bresp   <= 2'b00;
                s_axil_awready <= 1'b0;
                s_axil_wready  <= 1'b0;
            end

            // B handshake
            if (s_axil_bvalid && s_axil_bready) begin
                s_axil_bvalid  <= 1'b0;
                s_axil_awready <= 1'b1;
                s_axil_wready  <= 1'b1;
            end
        end
    end

    // ----------------------------------------------------------------
    // AXI-Lite read path
    // ----------------------------------------------------------------
    always_ff @(posedge s_axil_aclk) begin
        if (!s_axil_aresetn) begin
            s_axil_arready <= 1'b1;
            s_axil_rvalid  <= 1'b0;
            s_axil_rdata   <= '0;
            s_axil_rresp   <= 2'b00;
        end else begin

            if (s_axil_arvalid && s_axil_arready) begin
                s_axil_arready <= 1'b0;
                s_axil_rvalid  <= 1'b1;
                s_axil_rresp   <= 2'b00;

                case (s_axil_araddr[7:2])
                    // H2C
                    6'h00: s_axil_rdata <= h2c_dsc_byp_src_addr[31:0];
                    6'h01: s_axil_rdata <= h2c_dsc_byp_src_addr[63:32];
                    6'h02: s_axil_rdata <= h2c_dsc_byp_dst_addr[31:0];
                    6'h03: s_axil_rdata <= h2c_dsc_byp_dst_addr[63:32];
                    6'h04: s_axil_rdata <= {4'h0,  h2c_dsc_byp_len};
                    6'h05: s_axil_rdata <= {16'h0, h2c_dsc_byp_ctl};
                    6'h06: s_axil_rdata <= 32'h0;                       // GO WO
                    6'h07: s_axil_rdata <= {31'h0, h2c_dsc_byp_ready};  // status

                    // C2H
                    6'h10: s_axil_rdata <= c2h_dsc_byp_src_addr[31:0];
                    6'h11: s_axil_rdata <= c2h_dsc_byp_src_addr[63:32];
                    6'h12: s_axil_rdata <= c2h_dsc_byp_dst_addr[31:0];
                    6'h13: s_axil_rdata <= c2h_dsc_byp_dst_addr[63:32];
                    6'h14: s_axil_rdata <= {4'h0,  c2h_dsc_byp_len};
                    6'h15: s_axil_rdata <= {16'h0, c2h_dsc_byp_ctl};
                    6'h16: s_axil_rdata <= 32'h0;                       // GO WO
                    6'h17: s_axil_rdata <= {31'h0, c2h_dsc_byp_ready};  // status

                    default: begin
                        s_axil_rdata <= 32'h0;
                        s_axil_rresp <= 2'b00;
                    end
                endcase
            end

            if (s_axil_rvalid && s_axil_rready) begin
                s_axil_rvalid  <= 1'b0;
                s_axil_arready <= 1'b1;
            end
        end
    end

endmodule
