// ============================================================
// scrambler.sv
// LFSR-based data scrambler / descrambler
// ============================================================
// Uses a 16-bit Galois LFSR with polynomial x^16+x^15+x^13+x^4+1
// (taps at bits 16,15,13,4 — known maximal length polynomial,
//  cycles through all 65535 non-zero states before repeating)
//
// The same module is used for both scrambling and descrambling
// since XOR is its own inverse:
//   scramble:   data_out = data_in XOR lfsr_byte
//   descramble: data_in  = data_out XOR lfsr_byte  (identical)
//
// Usage:
//   1. Assert seed_valid_i for one cycle with page address on seed_i
//      This loads the LFSR seed and resets the byte counter
//   2. Assert in_valid_i with data on data_i
//      Scrambled/descrambled byte appears on data_o with out_valid_o
//   3. The LFSR advances one step per valid byte
//   4. Repeat from step 1 for each new page
//
// Seed derivation:
//   The 24-bit page address is folded into 16 bits:
//   seed = addr[23:8] XOR {8'h00, addr[7:0]}  then forced nonzero
//   (LFSR must never be seeded with 0 — that's the only illegal state)
// ============================================================

module scrambler #(
    parameter DATA_WIDTH = 8    // must be 8 for byte-serial flash data
)(
    input  logic                  clk,
    input  logic                  rst_n,

    // ---- Seed interface -----------------------------------
    // Pulse seed_valid_i for one cycle before starting a new page
    input  logic                  seed_valid_i,
    input  logic [23:0]           seed_i,       // page (row) address

    // ---- Data interface -----------------------------------
    input  logic [DATA_WIDTH-1:0] data_i,
    input  logic                  in_valid_i,
    output logic [DATA_WIDTH-1:0] data_o,
    output logic                  out_valid_o,

    // ---- Status -------------------------------------------
    output logic [12:0]           byte_count_o  // bytes processed this page
);

    // -------------------------------------------------------
    // 16-bit Galois LFSR
    // Polynomial: x^16 + x^15 + x^13 + x^4 + 1
    // Feedback taps at positions 16,15,13,4
    // In Galois form the XOR taps are at bits [14], [12], [3]
    // (bit positions are 0-indexed from LSB)
    // -------------------------------------------------------
    logic [15:0] lfsr;
    logic        feedback;

    // -------------------------------------------------------
    // Seed derivation — fold 24-bit page addr to 16 bits
    // -------------------------------------------------------
    logic [15:0] seed_folded;
    assign seed_folded = seed_i[23:8] ^ {8'h00, seed_i[7:0]};

    // -------------------------------------------------------
    // LFSR update — Galois configuration
    // Each cycle the LFSR shifts right by 1, feedback bit
    // is XORed into tap positions
    // -------------------------------------------------------
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            lfsr          <= 16'hFFFF;  // safe non-zero reset state
            byte_count_o  <= '0;
            out_valid_o   <= 0;
            data_o        <= '0;
        end else begin
            out_valid_o <= 0;

            // Reseed at start of each new page
            if (seed_valid_i) begin
                // Force nonzero — all-zero locks up the LFSR permanently
                lfsr         <= (seed_folded == 16'h0) ? 16'hFFFF : seed_folded;
                byte_count_o <= '0;
            end

            // Process one byte per valid input
            if (in_valid_i && !seed_valid_i) begin
                // XOR data with lower 8 bits of LFSR
                data_o      <= data_i ^ lfsr[7:0];
                out_valid_o <= 1;
                byte_count_o <= byte_count_o + 1;

                // Advance LFSR by 8 steps (one per bit of the byte)
                // Unrolled for synthesis efficiency
                begin
                    logic [15:0] s;
                    s = lfsr;
                    // 8 Galois LFSR steps unrolled
                    for (int i = 0; i < 8; i++) begin
                        feedback = s[0];
                        s = {1'b0, s[15:1]};
                        if (feedback) s = s ^ 16'hB400;
                        // 0xB400 = taps for x^16+x^15+x^13+x^4+1
                        // in Galois form: bits 15,14,12,3 → 0xB400
                    end
                    lfsr <= s;
                end
            end
        end
    end

endmodule