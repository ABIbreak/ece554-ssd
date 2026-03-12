// ============================================================
// axi4_csr_tb.sv — Class-based AXI4 CSR Testbench
// ============================================================
// Structure:
//   axi4_if        — interface bundling all AXI4 signals
//   axi4_txn       — transaction object (one read or write op)
//   axi4_driver    — class that drives transactions onto the interface
//   axi4_monitor   — class that observes and prints responses
//   test_rw_single — test: write then read back single registers
// ============================================================

`timescale 1ns/1ps
`include "axi4_csr.sv"

// ============================================================
// AXI4 Interface
// ============================================================
interface axi4_if #(
    parameter DATA_WIDTH = 32,
    parameter ADDR_WIDTH = 8,
    parameter ID_WIDTH   = 4
)(
    input logic clk, rst_n
);
    // Write Address
    logic [ID_WIDTH-1:0]     awid;
    logic [ADDR_WIDTH-1:0]   awaddr;
    logic [7:0]              awlen;
    logic [2:0]              awsize;
    logic [1:0]              awburst;
    logic                    awvalid;
    logic                    awready;

    // Write Data
    logic [DATA_WIDTH-1:0]   wdata;
    logic [DATA_WIDTH/8-1:0] wstrb;
    logic                    wlast;
    logic                    wvalid;
    logic                    wready;

    // Write Response
    logic [ID_WIDTH-1:0]     bid;
    logic [1:0]              bresp;
    logic                    bvalid;
    logic                    bready;

    // Read Address
    logic [ID_WIDTH-1:0]     arid;
    logic [ADDR_WIDTH-1:0]   araddr;
    logic [7:0]              arlen;
    logic [2:0]              arsize;
    logic [1:0]              arburst;
    logic                    arvalid;
    logic                    arready;

    // Read Data
    logic [ID_WIDTH-1:0]     rid;
    logic [DATA_WIDTH-1:0]   rdata;
    logic [1:0]              rresp;
    logic                    rlast;
    logic                    rvalid;
    logic                    rready;

    // Master clocking block — testbench drives on negedge, samples on posedge
    clocking master_cb @(posedge clk);
        default input #1 output #1;

        output awid, awaddr, awlen, awsize, awburst, awvalid;
        input  awready;

        output wdata, wstrb, wlast, wvalid;
        input  wready;

        input  bid, bresp, bvalid;
        output bready;

        output arid, araddr, arlen, arsize, arburst, arvalid;
        input  arready;

        input  rid, rdata, rresp, rlast, rvalid;
        output rready;
    endclocking

    modport master (clocking master_cb, input clk, rst_n);
endinterface


// ============================================================
// Transaction class — one AXI read or write operation
// ============================================================
class axi4_txn #(
    parameter DATA_WIDTH = 32,
    parameter ADDR_WIDTH = 8,
    parameter ID_WIDTH   = 4
);
    typedef enum { WRITE, READ } txn_type_t;

    txn_type_t               txn_type;
    logic [ID_WIDTH-1:0]     id;
    logic [ADDR_WIDTH-1:0]   addr;
    logic [DATA_WIDTH-1:0]   data;       // write data / read result
    logic [DATA_WIDTH/8-1:0] strb;       // byte enables (writes)
    logic [1:0]              resp;       // captured response code

    function new(
        input txn_type_t     t,
        input logic [ADDR_WIDTH-1:0] a,
        input logic [DATA_WIDTH-1:0] d    = '0,
        input logic [DATA_WIDTH/8-1:0] s  = '1,   // default: all bytes enabled
        input logic [ID_WIDTH-1:0] i      = '0
    );
        txn_type = t;
        addr     = a;
        data     = d;
        strb     = s;
        id       = i;
        resp     = '0;
    endfunction

    function string to_string();
        return $sformatf("[%s] id=%0h addr=0x%02h data=0x%08h strb=%04b resp=%02b",
            txn_type == WRITE ? "WR" : "RD",
            id, addr, data, strb, resp);
    endfunction
endclass


// ============================================================
// AXI4 Driver class — sends transactions onto the interface
// ============================================================
class axi4_driver #(
    parameter DATA_WIDTH = 32,
    parameter ADDR_WIDTH = 8,
    parameter ID_WIDTH   = 4
);
    typedef axi4_txn #(DATA_WIDTH, ADDR_WIDTH, ID_WIDTH) txn_t;

    virtual axi4_if #(DATA_WIDTH, ADDR_WIDTH, ID_WIDTH) vif;

    function new(virtual axi4_if #(DATA_WIDTH, ADDR_WIDTH, ID_WIDTH) i);
        vif = i;
    endfunction

    // ---- Drive a write transaction -------------------------
    task write(input txn_t txn);
        // --- Write Address ---
        @(vif.master_cb);
        vif.master_cb.awid    <= txn.id;
        vif.master_cb.awaddr  <= txn.addr;
        vif.master_cb.awlen   <= 8'h00;      // single beat
        vif.master_cb.awsize  <= 3'b010;     // 4 bytes
        vif.master_cb.awburst <= 2'b01;      // INCR
        vif.master_cb.awvalid <= 1;

        // Wait for awready
        do @(vif.master_cb); while (!vif.master_cb.awready);
        vif.master_cb.awvalid <= 0;

        // --- Write Data ---
        vif.master_cb.wdata  <= txn.data;
        vif.master_cb.wstrb  <= txn.strb;
        vif.master_cb.wlast  <= 1;           // single beat, always last
        vif.master_cb.wvalid <= 1;

        // Wait for wready
        do @(vif.master_cb); while (!vif.master_cb.wready);
        vif.master_cb.wvalid <= 0;
        vif.master_cb.wlast  <= 0;

        // --- Write Response ---
        vif.master_cb.bready <= 1;
        do @(vif.master_cb); while (!vif.master_cb.bvalid);
        txn.resp = vif.master_cb.bresp;
        vif.master_cb.bready <= 0;
    endtask

    // ---- Drive a read transaction --------------------------
    task read(input txn_t txn);
        // --- Read Address ---
        @(vif.master_cb);
        vif.master_cb.arid    <= txn.id;
        vif.master_cb.araddr  <= txn.addr;
        vif.master_cb.arlen   <= 8'h00;      // single beat
        vif.master_cb.arsize  <= 3'b010;     // 4 bytes
        vif.master_cb.arburst <= 2'b01;      // INCR
        vif.master_cb.arvalid <= 1;

        // Wait for arready
        do @(vif.master_cb); while (!vif.master_cb.arready);
        vif.master_cb.arvalid <= 0;

        // --- Read Data ---
        vif.master_cb.rready <= 1;
        do @(vif.master_cb); while (!vif.master_cb.rvalid);
        txn.data = vif.master_cb.rdata;
        txn.resp = vif.master_cb.rresp;
        vif.master_cb.rready <= 0;
    endtask

endclass


// ============================================================
// AXI4 Monitor — observes results and checks expected values
// ============================================================
class axi4_monitor;
    int pass_count;
    int fail_count;

    function new();
        pass_count = 0;
        fail_count = 0;
    endfunction

    task check(
        input string          test_name,
        input logic [31:0] got,
        input logic [31:0] expected
    );
        if (got === expected) begin
            $display("  PASS  %s | got=0x%08h", test_name, got);
            pass_count++;
        end else begin
            $display("  FAIL  %s | got=0x%08h expected=0x%08h", test_name, got, expected);
            fail_count++;
        end
    endtask

    function void report();
        $display("\n========================================");
        $display("  Results: %0d passed, %0d failed", pass_count, fail_count);
        $display("========================================");
    endfunction
endclass


// ============================================================
// Top-level testbench module
// ============================================================
module axi4_csr_tb;

    // ---- Parameters (must match DUT instantiation) --------
    localparam DATA_WIDTH = 32;
    localparam ADDR_WIDTH = 8;
    localparam ID_WIDTH   = 4;
    localparam NUM_REGS   = 4;

    // ACCESS: REG0=RW, REG1=RW, REG2=RO, REG3=RW1C
    localparam [NUM_REGS*2-1:0] ACCESS = {2'b10, 2'b01, 2'b00, 2'b00};

    // ---- Clock & reset ------------------------------------
    logic clk = 0;
    logic rst_n;
    always #5 clk = ~clk;   // 100 MHz

    // ---- Interface ----------------------------------------
    axi4_if #(DATA_WIDTH, ADDR_WIDTH, ID_WIDTH) axi (.clk(clk), .rst_n(rst_n));

    // ---- DUT register ports -------------------------------
    logic [NUM_REGS-1:0][DATA_WIDTH-1:0] reg_i;
    logic [NUM_REGS-1:0][DATA_WIDTH-1:0] reg_o;

    // Drive RO register (REG2) with a known live value
    assign reg_i[2] = 32'hDEAD_BEEF;
    assign reg_i[0] = '0;   // unused for RW regs
    assign reg_i[1] = '0;
    assign reg_i[3] = '0;

    // ---- DUT ----------------------------------------------
    axi4_csr #(
        .DATA_WIDTH (DATA_WIDTH),
        .ADDR_WIDTH (ADDR_WIDTH),
        .ID_WIDTH   (ID_WIDTH),
        .NUM_REGS   (NUM_REGS),
        .ACCESS     (ACCESS)
    ) dut (
        .clk            (clk),
        .rst_n          (rst_n),
        .s_axi_awid     (axi.awid),
        .s_axi_awaddr   (axi.awaddr),
        .s_axi_awlen    (axi.awlen),
        .s_axi_awsize   (axi.awsize),
        .s_axi_awburst  (axi.awburst),
        .s_axi_awvalid  (axi.awvalid),
        .s_axi_awready  (axi.awready),
        .s_axi_wdata    (axi.wdata),
        .s_axi_wstrb    (axi.wstrb),
        .s_axi_wlast    (axi.wlast),
        .s_axi_wvalid   (axi.wvalid),
        .s_axi_wready   (axi.wready),
        .s_axi_bid      (axi.bid),
        .s_axi_bresp    (axi.bresp),
        .s_axi_bvalid   (axi.bvalid),
        .s_axi_bready   (axi.bready),
        .s_axi_arid     (axi.arid),
        .s_axi_araddr   (axi.araddr),
        .s_axi_arlen    (axi.arlen),
        .s_axi_arsize   (axi.arsize),
        .s_axi_arburst  (axi.arburst),
        .s_axi_arvalid  (axi.arvalid),
        .s_axi_arready  (axi.arready),
        .s_axi_rid      (axi.rid),
        .s_axi_rdata    (axi.rdata),
        .s_axi_rresp    (axi.rresp),
        .s_axi_rlast    (axi.rlast),
        .s_axi_rvalid   (axi.rvalid),
        .s_axi_rready   (axi.rready),
        .reg_i          (reg_i),
        .reg_o          (reg_o)
    );

    // ---- Test program -------------------------------------
    typedef axi4_txn    #(DATA_WIDTH, ADDR_WIDTH, ID_WIDTH) txn_t;
    typedef axi4_driver #(DATA_WIDTH, ADDR_WIDTH, ID_WIDTH) driver_t;

    initial begin
        automatic driver_t   drv = new(axi);
        automatic axi4_monitor mon = new();
        automatic txn_t      txn;

        // -- Reset --
        rst_n = 0;
        axi.awvalid = 0; axi.wvalid = 0; axi.bready = 0;
        axi.arvalid = 0; axi.rready = 0;
        repeat(4) @(posedge clk);
        rst_n = 1;
        repeat(2) @(posedge clk);

        $display("\n=== Test: Single Register RW ===\n");

        // ------------------------------------------------
        // TEST 1: Write 0xA5A5_A5A5 to REG0, read it back
        // ------------------------------------------------
        $display("-- REG0 (RW) write/read --");
        txn = new(txn_t::WRITE, 8'h00, 32'hA5A5_A5A5);
        drv.write(txn);
        mon.check("WR REG0 resp", txn.resp, 2'b00);  // expect OKAY

        txn = new(txn_t::READ, 8'h00);
        drv.read(txn);
        mon.check("RD REG0 data", txn.data, 32'hA5A5_A5A5);
        mon.check("RD REG0 resp", txn.resp, 2'b00);

        // ------------------------------------------------
        // TEST 2: Write 0x1234_5678 to REG1, read it back
        // ------------------------------------------------
        $display("-- REG1 (RW) write/read --");
        txn = new(txn_t::WRITE, 8'h04, 32'h1234_5678);
        drv.write(txn);
        mon.check("WR REG1 resp", txn.resp, 2'b00);

        txn = new(txn_t::READ, 8'h04);
        drv.read(txn);
        mon.check("RD REG1 data", txn.data, 32'h1234_5678);
        mon.check("RD REG1 resp", txn.resp, 2'b00);

        // ------------------------------------------------
        // TEST 3: Write to REG0 with partial byte strobe
        //         Only upper 2 bytes should change
        //         REG0 was 0xA5A5_A5A5, write 0xFFFF_0000 strb=4'b1100
        //         Expected: 0xFFFF_A5A5
        // ------------------------------------------------
        $display("-- REG0 partial byte strobe --");
        txn = new(txn_t::WRITE, 8'h00, 32'hFFFF_0000, 4'b1100);
        drv.write(txn);

        txn = new(txn_t::READ, 8'h00);
        drv.read(txn);
        mon.check("RD REG0 partial strobe", txn.data, 32'hFFFF_A5A5);

        // ------------------------------------------------
        // TEST 4: Verify reg_o reflects written value
        // ------------------------------------------------
        $display("-- reg_o output check --");
        mon.check("reg_o[0]", reg_o[0], 32'hFFFF_A5A5);
        mon.check("reg_o[1]", reg_o[1], 32'h1234_5678);

        // ------------------------------------------------
        // Wrap up
        // ------------------------------------------------
        repeat(4) @(posedge clk);
        mon.report();
        $finish;
    end

    // ---- Timeout watchdog ---------------------------------
    initial begin
        #1000000;   // 1000 us timeout
        $display("TIMEOUT — simulation ran too long");
        $finish;
    end

endmodule