// ============================================================
// axis_deserializer.sv
// AXI-Stream (32-bit) → byte stream
// ============================================================
// Sits between the DMA engine and the write-path FIFO.
// Receives 32-bit AXI-Stream beats and outputs 4 bytes per
// beat, LSB first (byte 0 = bits [7:0]).
//
// Flow:
//   1. Accept a 32-bit beat when tvalid & tready
//   2. Output byte[0], byte[1], byte[2], byte[3] in order
//   3. Assert out_valid_o for each output byte
//   4. Backpressure: if downstream (FIFO) is full, stall
//      by deasserting tready until room is available
//   5. tlast on the input is passed through as page_done_o
//      after all 4 bytes of the final beat have been output
// ============================================================
 
module axis_deserializer #(
    parameter AXIS_WIDTH = 32,         // must be 32 for this design
    parameter BYTES_PER_BEAT = AXIS_WIDTH / 8  // 4
)(
    input  logic                  clk,
    input  logic                  rst_n,
 
    // ---- AXI-Stream slave (from DMA engine) --------------
    input  logic [AXIS_WIDTH-1:0] s_axis_tdata,
    input  logic                  s_axis_tvalid,
    output logic                  s_axis_tready,
    input  logic                  s_axis_tlast,   // end of page transfer
 
    // ---- Byte stream out (to write FIFO) -----------------
    output logic [7:0]            out_data_o,
    output logic                  out_valid_o,
    input  logic                  out_ready_i,    // FIFO not full
 
    // ---- Status ------------------------------------------
    output logic                  page_done_o     // all bytes of page pushed
);
 
    // -------------------------------------------------------
    // State
    // -------------------------------------------------------
    typedef enum logic [1:0] {
        S_IDLE,     // waiting for AXI-S beat
        S_OUTPUT    // outputting bytes from latched beat
    } state_t;
 
    state_t              state;
    logic [AXIS_WIDTH-1:0] beat_latch;   // latched 32-bit beat
    logic                  last_latch;   // latched tlast
    logic [1:0]            byte_idx;     // which byte we're outputting (0-3)
 
    // -------------------------------------------------------
    // FSM
    // -------------------------------------------------------
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state        <= S_IDLE;
            beat_latch   <= '0;
            last_latch   <= 0;
            byte_idx     <= 0;
            out_valid_o  <= 0;
            out_data_o   <= '0;
            page_done_o  <= 0;
            s_axis_tready <= 0;
        end else begin
            page_done_o  <= 0;
            out_valid_o  <= 0;
 
            case (state)
 
                S_IDLE: begin
                    s_axis_tready <= 1;   // ready to accept a beat
 
                    if (s_axis_tvalid && s_axis_tready) begin
                        beat_latch    <= s_axis_tdata;
                        last_latch    <= s_axis_tlast;
                        byte_idx      <= 0;
                        s_axis_tready <= 0;  // stop accepting until beat consumed
                        state         <= S_OUTPUT;
                    end
                end
 
                S_OUTPUT: begin
                    if (out_ready_i) begin
                        // Output current byte (LSB first)
                        out_data_o  <= beat_latch[byte_idx*8 +: 8];
                        out_valid_o <= 1;
 
                        if (byte_idx == BYTES_PER_BEAT - 1) begin
                            // Last byte of this beat
                            byte_idx <= 0;
 
                            if (last_latch) begin
                                // Last beat of the page — signal done
                                page_done_o   <= 1;
                                state         <= S_IDLE;
                            end else begin
                                // More beats to come — go accept next
                                s_axis_tready <= 1;
                                state         <= S_IDLE;
                            end
                        end else begin
                            byte_idx <= byte_idx + 1;
                        end
                    end
                end
 
                default: state <= S_IDLE;
            endcase
        end
    end
 
endmodule