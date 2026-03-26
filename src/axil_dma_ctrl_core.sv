`default_nettype none

// axil_dma_ctrl_core.sv
//
// AXI-Lite slave exposing DMA control registers.
// All writes are expected to be full 32-bit (wstrb is present but ignored).
//
// Register map (byte addresses):
//   0x00  host_addr_lo  [31:0]  RW  lower 32 bits of host (PCIe/system) address
//   0x04  host_addr_hi  [31:0]  RW  upper 32 bits of host address
//   0x08  card_addr_lo  [31:0]  RW  lower 32 bits of card (AXI) address
//   0x0C  card_addr_hi  [31:0]  RW  upper 32 bits of card address
//   0x10  len_lo        [31:0]  RW  lower 32 bits of transfer length
//   0x14  len_hi        [31:0]  RW  upper 32 bits of transfer length
//   0x18  ctrl          [31:0]
//           [0]  ready   RW   1 = DMA engine idle, 0 = busy
//           [1]  c2h     RW   1 = card-to-host, 0 = host-to-card
//           [2]  go      RW   1 = start transfer

module axil_dma_ctrl_core (
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
    input  logic        s_axil_rready
);

    // Register storage
    logic        ready, c2h, go;
    logic [63:0] host_addr;
    logic [63:0] card_addr;
    logic [63:0] len;

    // ----------------------------------------------------------------
    // AXI-Lite write path
    // ----------------------------------------------------------------
    logic        aw_done;
    logic        w_done;
    logic [4:0]  wr_addr_lat;
    logic [31:0] wr_data_lat;

    logic [4:0]  wr_addr;
    logic [31:0] wr_data;
    logic        wr_fire;

    assign wr_addr = aw_done ? wr_addr_lat : s_axil_awaddr[4:0];
    assign wr_data = w_done  ? wr_data_lat : s_axil_wdata;
    assign wr_fire = (aw_done || (s_axil_awvalid && s_axil_awready)) &&
                     (w_done  || (s_axil_wvalid  && s_axil_wready));

    always_ff @(posedge s_axil_aclk) begin
        if (!s_axil_aresetn) begin
            s_axil_awready <= 1'b1;
            s_axil_wready  <= 1'b1;
            s_axil_bvalid  <= 1'b0;
            s_axil_bresp   <= 2'b00;
            aw_done        <= 1'b0;
            w_done         <= 1'b0;
            wr_addr_lat    <= '0;
            wr_data_lat    <= '0;
            host_addr      <= '0;
            card_addr      <= '0;
            len            <= '0;
            ready          <= 1'b1;
            c2h            <= 1'b0;
            go             <= 1'b0;

        end else begin

            if (s_axil_awvalid && s_axil_awready) begin
                wr_addr_lat    <= s_axil_awaddr[4:0];
                aw_done        <= 1'b1;
                s_axil_awready <= 1'b0;
            end

            if (s_axil_wvalid && s_axil_wready) begin
                wr_data_lat   <= s_axil_wdata;
                w_done        <= 1'b1;
                s_axil_wready <= 1'b0;
            end

            if (wr_fire) begin
                case (wr_addr[4:2])
                    3'h0: host_addr[31:0]  <= wr_data;
                    3'h1: host_addr[63:32] <= wr_data;
                    3'h2: card_addr[31:0]  <= wr_data;
                    3'h3: card_addr[63:32] <= wr_data;
                    3'h4: len[31:0]        <= wr_data;
                    3'h5: len[63:32]       <= wr_data;
                    3'h6: begin
                        ready <= wr_data[0];
                        c2h   <= wr_data[1];
                        go    <= wr_data[2];
                    end
                    default: ;
                endcase

                aw_done        <= 1'b0;
                w_done         <= 1'b0;
                s_axil_bvalid  <= 1'b1;
                s_axil_bresp   <= 2'b00;
                s_axil_awready <= 1'b0;
                s_axil_wready  <= 1'b0;
            end

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

                case (s_axil_araddr[4:2])
                    3'h0: s_axil_rdata <= host_addr[31:0];
                    3'h1: s_axil_rdata <= host_addr[63:32];
                    3'h2: s_axil_rdata <= card_addr[31:0];
                    3'h3: s_axil_rdata <= card_addr[63:32];
                    3'h4: s_axil_rdata <= len[31:0];
                    3'h5: s_axil_rdata <= len[63:32];
                    3'h6: s_axil_rdata <= {29'b0, go, c2h, ready};
                    default: s_axil_rdata <= '0;
                endcase
            end

            if (s_axil_rvalid && s_axil_rready) begin
                s_axil_rvalid  <= 1'b0;
                s_axil_arready <= 1'b1;
            end
        end
    end

endmodule
