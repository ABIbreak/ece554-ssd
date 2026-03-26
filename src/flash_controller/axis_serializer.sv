// ============================================================
// axis_serializer.sv
// Byte stream → AXI-Stream (32-bit)
// ============================================================
// Sits between the read-path FIFO and the DMA engine.
// Collects 4 bytes from the FIFO and packs them into one
// 32-bit AXI-Stream beat, LSB first.
//
// Flow:
//   1. Pull bytes from FIFO (assert rd_en_o while not empty)
//   2. Accumulate 4 bytes into a 32-bit word
//   3. Assert m_axis_tvalid when word is ready
//   4. Wait for m_axis_tready (DMA engine accepts the beat)
//   5. Assert tlast on the final beat of the page
//   6. page_bytes_i tells us total page size so we know when
//      to assert tlast (default 2112)
// ============================================================
 
module axis_serializer #(
    parameter AXIS_WIDTH    = 32,
    parameter BYTES_PER_BEAT = AXIS_WIDTH / 8,  // 4
    parameter PAGE_BYTES    = 2112
)(
    input  logic                   clk,
    input  logic                   rst_n,
 
    // ---- Byte stream in (from read FIFO) -----------------
    input  logic [7:0]             in_data_i,
    input  logic                   in_valid_i,   // FIFO not empty
    output logic                   rd_en_o,      // pull next byte from FIFO
 
    // ---- AXI-Stream master (to DMA engine) ---------------
    output logic [AXIS_WIDTH-1:0]  m_axis_tdata,
    output logic                   m_axis_tvalid,
    input  logic                   m_axis_tready,
    output logic                   m_axis_tlast,
 
    // ---- Control -----------------------------------------
    input  logic                   start_i,      // pulse to begin serializing
    output logic                   done_o        // page fully sent to DMA
);
 
    // -------------------------------------------------------
    // State
    // -------------------------------------------------------
    typedef enum logic [1:0] {
        S_IDLE,       // waiting for start
        S_COLLECT,    // pulling bytes from FIFO, building word
        S_SEND        // word ready, waiting for tready
    } state_t;
 
    state_t              state;
    logic [AXIS_WIDTH-1:0] word_build;      // accumulating word
    logic [1:0]            byte_idx;        // byte position in current word
    logic [12:0]           byte_count;      // total bytes sent this page
 
    // -------------------------------------------------------
    // FSM
    // -------------------------------------------------------
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state         <= S_IDLE;
            word_build    <= '0;
            byte_idx      <= 0;
            byte_count    <= 0;
            m_axis_tdata  <= '0;
            m_axis_tvalid <= 0;
            m_axis_tlast  <= 0;
            rd_en_o       <= 0;
            done_o        <= 0;
        end else begin
            done_o  <= 0;
            rd_en_o <= 0;
 
            case (state)
 
                S_IDLE: begin
                    m_axis_tvalid <= 0;
                    byte_idx      <= 0;
                    byte_count    <= 0;
                    word_build    <= '0;
 
                    if (start_i) begin
                        state <= S_COLLECT;
                    end
                end
 
                S_COLLECT: begin
                    // Pull one byte per cycle from FIFO when available
                    if (in_valid_i && !rd_en_o) begin
                        rd_en_o <= 1;   // pulse rd_en to FIFO
                    end
 
                    // One cycle after rd_en, data is valid (registered FIFO)
                    if (rd_en_o) begin
                        word_build[byte_idx*8 +: 8] <= in_data_i;
                        byte_count <= byte_count + 1;
 
                        if (byte_idx == BYTES_PER_BEAT - 1) begin
                            // Word complete — go send it
                            byte_idx      <= 0;
                            m_axis_tdata  <= {in_data_i,
                                             word_build[23:16],
                                             word_build[15:8],
                                             word_build[7:0]};
                            m_axis_tvalid <= 1;
                            m_axis_tlast  <= (byte_count + 1 >= PAGE_BYTES);
                            state         <= S_SEND;
                        end else begin
                            byte_idx <= byte_idx + 1;
                        end
                    end
                end
 
                S_SEND: begin
                    if (m_axis_tvalid && m_axis_tready) begin
                        m_axis_tvalid <= 0;
 
                        if (m_axis_tlast) begin
                            // Page fully transferred
                            done_o <= 1;
                            state  <= S_IDLE;
                        end else begin
                            // More bytes to collect
                            word_build <= '0;
                            state      <= S_COLLECT;
                        end
                    end
                end
 
                default: state <= S_IDLE;
            endcase
        end
    end
 
endmodule