//=============================================================================
// rng.sv  --  MTRX3700 Assignment 1, Piano Tiles
//
// Ten-bit Fibonacci LFSR, taps 10 and 7. The core is the Reaction Time Game's
// rng unchanged; OFFSET and MAX_VALUE were removed because they existed to
// produce a 200..1223 ms reaction-timer start value and this game wants the
// raw bits. Say that in Q1 rather than claiming the module is untouched.
//
// No reset, deliberately: resetting to a fixed seed would replay the identical
// note pattern every game, and resetting to zero would stop the LFSR dead.
//=============================================================================
module rng #(
    parameter LFSR_BITS = 10,                 // 10 only -- see the guard below
    parameter SEED      = 10'b01011_01000
) (
    input  clk,
    output [LFSR_BITS-1:0] random_value
);

    reg [LFSR_BITS:1] lfsr;

    initial lfsr = SEED;                      // Quartus honours this as the
                                              // power-up value on Cyclone V

    wire feedback;
    assign feedback = lfsr[LFSR_BITS] ^ lfsr[LFSR_BITS-3];

    always @(posedge clk) begin
        lfsr <= lfsr << 1;
        lfsr[1] <= feedback;                  // later assignment wins for bit 1
    end

    assign random_value = lfsr;

    //-------------------------------------------------------------------------
    // Guards (simulation only)
    //-------------------------------------------------------------------------
    // synthesis translate_off

    // `initial lfsr = SEED` keeps only the low LFSR_BITS bits, so the guard
    // must test the TRUNCATED seed: SEED = 1024 looks non-zero and loads zero.
    localparam SEED_LOADED = SEED & ((1 << LFSR_BITS) - 1);

    initial begin
        if (LFSR_BITS < 4)
            $fatal(1, "rng: LFSR_BITS (%0d) must be at least 4, or the tap index LFSR_BITS-3 does not exist",
                   LFSR_BITS);

        // Measured periods for taps (LFSR_BITS, LFSR_BITS-3): 10 -> 1023/1023,
        // 9 -> 21/511, 12 -> 45/4095, 15 -> 63/32767. A short period fails R4
        // on the board while every unit test still passes. Widening the LFSR
        // means changing the polynomial, not just the width.
        if (LFSR_BITS != 10)
            $fatal(1, "rng: taps (%0d, %0d) are only primitive at LFSR_BITS = 10; supply a verified tap for this width instead of relaxing this guard",
                   LFSR_BITS, LFSR_BITS - 3);

        // All-zero is a fixed point: the taps XOR to 0 and nothing shifts in.
        if (SEED_LOADED == 0)
            $fatal(1, "rng: SEED (%0d) truncates to all zeros in %0d bits; random_value would be stuck at 0 forever",
                   SEED, LFSR_BITS);
    end

    // Unreachable given a non-zero seed and correct feedback. Kept because it
    // is what catches an edit to the tap expression: a dead LFSR presents as a
    // scheduler that spawns one lane forever.
    always @(posedge clk) begin
        if (lfsr == '0)
            $fatal(1, "rng: LFSR reached the all-zero state; the feedback path is broken");
    end
    // synthesis translate_on

endmodule
