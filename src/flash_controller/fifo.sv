// ============================================================
// fifo.sv
// Synchronous FIFO — used twice in flash controller:
//   Write path: AXI-S Deserializer → FIFO → Scrambler
//   Read  path: Descrambler → FIFO → AXI-S Serializer
//
// Parameters:
//   DATA_WIDTH — bits per entry (default 8, byte-serial to/from scrambler)
//   DEPTH      — number of entries (default 2112 = one full page + OOB)
//
// Interface:
//   Write side: wr_en_i + wr_data_i — push one entry per clock when full_o=0
//   Read  side: rd_en_i             — pop one entry per clock when empty_o=0
//               rd_data_o valid one cycle after rd_en_i (registered read)
//
// Status flags:
//   full_o       — no more room, do not write
//   empty_o      — nothing to read
//   almost_full  — only ALMOST_FULL_THRESH entries remain (default 8)
//   count_o      — exact number of entries currently stored
//
// Overflow/underflow:
//   Writing when full  → data dropped, overflow_o pulses for one cycle
//   Reading when empty → rd_data_o = 0, underflow_o pulses for one cycle
// ============================================================

module fifo #(
    parameter int DATA_WIDTH        = 8,
    parameter int DEPTH             = 2112,   // one full page including OOB
    parameter int ALMOST_FULL_THRESH = 8      // assert almost_full when this many slots remain
)(
    input  logic                  clk,
    input  logic                  rst_n,

    // ---- Write port --------------------------------------
    input  logic                  wr_en_i,
    input  logic [DATA_WIDTH-1:0] wr_data_i,
    output logic                  full_o,
    output logic                  almost_full_o,

    // ---- Read port ---------------------------------------
    input  logic                  rd_en_i,
    output logic [DATA_WIDTH-1:0] rd_data_o,
    output logic                  empty_o,

    // ---- Status ------------------------------------------
    output logic [$clog2(DEPTH):0] count_o,     // 0 to DEPTH inclusive
    output logic                   overflow_o,   // single cycle pulse
    output logic                   underflow_o,  // single cycle pulse

    // ---- Control -----------------------------------------
    input  logic                  flush_i       // synchronous reset of pointers
);

    // -------------------------------------------------------
    // Storage
    // -------------------------------------------------------
    logic [DATA_WIDTH-1:0] mem [0:DEPTH-1];

    // -------------------------------------------------------
    // Pointers — one extra bit for full/empty disambiguation
    // -------------------------------------------------------
    logic [$clog2(DEPTH):0] wr_ptr;   // write pointer
    logic [$clog2(DEPTH):0] rd_ptr;   // read pointer

    // Actual index into mem[] is the lower bits
    logic [$clog2(DEPTH)-1:0] wr_idx;
    logic [$clog2(DEPTH)-1:0] rd_idx;

    assign wr_idx = wr_ptr[$clog2(DEPTH)-1:0];
    assign rd_idx = rd_ptr[$clog2(DEPTH)-1:0];

    // -------------------------------------------------------
    // Full / empty / count
    // Full  = pointers have same index bits but different MSB
    // Empty = pointers are identical
    // -------------------------------------------------------
    assign empty_o       = (wr_ptr == rd_ptr);
    assign full_o        = (wr_ptr[$clog2(DEPTH)] != rd_ptr[$clog2(DEPTH)]) &&
                           (wr_idx == rd_idx);
    assign count_o       = wr_ptr - rd_ptr;
    assign almost_full_o = (count_o >= (DEPTH - ALMOST_FULL_THRESH));

    // -------------------------------------------------------
    // Write logic
    // -------------------------------------------------------
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n || flush_i) begin
            wr_ptr     <= '0;
            overflow_o <= 0;
        end else begin
            overflow_o <= 0;

            if (wr_en_i) begin
                if (full_o) begin
                    overflow_o <= 1;    // drop data, pulse overflow
                end else begin
                    mem[wr_idx] <= wr_data_i;
                    wr_ptr      <= wr_ptr + 1;
                end
            end
        end
    end

    // -------------------------------------------------------
    // Read logic — registered output (one cycle latency)
    // -------------------------------------------------------
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n || flush_i) begin
            rd_ptr      <= '0;
            rd_data_o   <= '0;
            underflow_o <= 0;
        end else begin
            underflow_o <= 0;

            if (rd_en_i) begin
                if (empty_o) begin
                    underflow_o <= 1;   // nothing to read
                    rd_data_o   <= '0;
                end else begin
                    rd_data_o <= mem[rd_idx];
                    rd_ptr    <= rd_ptr + 1;
                end
            end
        end
    end

endmodule