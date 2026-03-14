// descriptor_bypass_wrapper.v
// Verilog wrapper around descriptor_bypass_wrapper_core (SystemVerilog).

module descriptor_bypass_wrapper (
    // AXI-Lite slave
    input  wire        s_axil_aclk,
    input  wire        s_axil_aresetn,

    input  wire [31:0] s_axil_awaddr,
    input  wire        s_axil_awvalid,
    output wire        s_axil_awready,

    input  wire [31:0] s_axil_wdata,
    input  wire [3:0]  s_axil_wstrb,
    input  wire        s_axil_wvalid,
    output wire        s_axil_wready,

    output wire [1:0]  s_axil_bresp,
    output wire        s_axil_bvalid,
    input  wire        s_axil_bready,

    input  wire [31:0] s_axil_araddr,
    input  wire        s_axil_arvalid,
    output wire        s_axil_arready,

    output wire [31:0] s_axil_rdata,
    output wire [1:0]  s_axil_rresp,
    output wire        s_axil_rvalid,
    input  wire        s_axil_rready,

    // H2C descriptor bypass (xdma ports)
    input  wire        h2c_dsc_byp_ready,
    output wire        h2c_dsc_byp_load,
    output wire [63:0] h2c_dsc_byp_src_addr,
    output wire [63:0] h2c_dsc_byp_dst_addr,
    output wire [27:0] h2c_dsc_byp_len,
    output wire [15:0] h2c_dsc_byp_ctl,

    // C2H descriptor bypass (xdma ports)
    input  wire        c2h_dsc_byp_ready,
    output wire        c2h_dsc_byp_load,
    output wire [63:0] c2h_dsc_byp_src_addr,
    output wire [63:0] c2h_dsc_byp_dst_addr,
    output wire [27:0] c2h_dsc_byp_len,
    output wire [15:0] c2h_dsc_byp_ctl
);

descriptor_bypass_wrapper_core core (
    .s_axil_aclk            (s_axil_aclk),
    .s_axil_aresetn         (s_axil_aresetn),

    .s_axil_awaddr          (s_axil_awaddr),
    .s_axil_awvalid         (s_axil_awvalid),
    .s_axil_awready         (s_axil_awready),

    .s_axil_wdata           (s_axil_wdata),
    .s_axil_wstrb           (s_axil_wstrb),
    .s_axil_wvalid          (s_axil_wvalid),
    .s_axil_wready          (s_axil_wready),

    .s_axil_bresp           (s_axil_bresp),
    .s_axil_bvalid          (s_axil_bvalid),
    .s_axil_bready          (s_axil_bready),

    .s_axil_araddr          (s_axil_araddr),
    .s_axil_arvalid         (s_axil_arvalid),
    .s_axil_arready         (s_axil_arready),

    .s_axil_rdata           (s_axil_rdata),
    .s_axil_rresp           (s_axil_rresp),
    .s_axil_rvalid          (s_axil_rvalid),
    .s_axil_rready          (s_axil_rready),

    .h2c_dsc_byp_ready      (h2c_dsc_byp_ready),
    .h2c_dsc_byp_load       (h2c_dsc_byp_load),
    .h2c_dsc_byp_src_addr   (h2c_dsc_byp_src_addr),
    .h2c_dsc_byp_dst_addr   (h2c_dsc_byp_dst_addr),
    .h2c_dsc_byp_len        (h2c_dsc_byp_len),
    .h2c_dsc_byp_ctl        (h2c_dsc_byp_ctl),

    .c2h_dsc_byp_ready      (c2h_dsc_byp_ready),
    .c2h_dsc_byp_load       (c2h_dsc_byp_load),
    .c2h_dsc_byp_src_addr   (c2h_dsc_byp_src_addr),
    .c2h_dsc_byp_dst_addr   (c2h_dsc_byp_dst_addr),
    .c2h_dsc_byp_len        (c2h_dsc_byp_len),
    .c2h_dsc_byp_ctl        (c2h_dsc_byp_ctl)
);

endmodule
