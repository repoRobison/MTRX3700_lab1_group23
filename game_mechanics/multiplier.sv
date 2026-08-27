//=============================================================================
// multiplier.sv -- clean-hit streak and x1/x2/x3 multiplier controller
//
// DESIGN ROLE
//   This module owns the persistent successful-hit streak. Normal and perfect
//   hits both advance that streak; a miss, early/forfeited note, or press on a
//   blank lane breaks it. The output multiplier_value describes the multiplier
//   earned by the STORED streak and is suitable for the front-panel LEDs.
//
// THRESHOLD-HIT SEMANTICS
//   The group chose inclusive thresholds: hit 6 scores at x2 and hit 16 scores
//   at x3. A conventional registered multiplier would update one clock too late
//   because score.sv and this module sample the same event edge. To avoid
//   that off-by-one, hit_multiplier is combinationally calculated from:
//
//       stored streak + all successful notes on this clock
//
//   score.sv samples hit_multiplier on the event edge. The stored streak
//   is then committed by this module on that same edge. multiplier_value is
//   separately decoded from the stored streak for stable between-hit display.
//
// SIMULTANEOUS EVENTS
//   normal_hit/perfect_hit are four-lane, one-clock pulses. Their union is
//   pop-counted, so a two-note chord can advance the streak by two. Every note
//   in a chord receives one common multiplier; there is no arbitrary lane order.
//   If a success and a streak-breaking event occur together, hit_multiplier is
//   still calculated for the valid success, while the stored streak resets after
//   the edge. This matches the score policy: valid gains and penalties are both
//   applied, but mashing cannot preserve a streak.
//
// LED ENCODING
//   multiplier_leds is a growing bar from LEDR2 down toward LEDR0:
//       x1 -> 3'b100, x2 -> 3'b110, x3 -> 3'b111.
//
// INPUT CONTRACT
//   normal_hit and perfect_hit must be mutually exclusive for any one lane.
//   All event inputs must be single-clock pulses from the lane/hit subsystem.
//=============================================================================
`timescale 1ns/1ps
`include "game_params.svh"

module multiplier #(
    parameter int NUM_LANES   = `GP_NUM_LANES,
    parameter int MULT2_AT    = `GP_MULT2_STREAK,
    parameter int MULT3_AT    = `GP_MULT3_STREAK,
    parameter int MAX_STREAK  = `GP_MAX_STREAK,
    parameter int STREAK_W    = $clog2(MAX_STREAK + 1)
) (
    input  logic                 clk,
    input  logic                 reset,
    input  logic [NUM_LANES-1:0] normal_hit,
    input  logic [NUM_LANES-1:0] perfect_hit,
    input  logic [NUM_LANES-1:0] miss,
    input  logic [NUM_LANES-1:0] forfeit,
    input  logic [NUM_LANES-1:0] stray,

    output logic [STREAK_W-1:0]  streak,
    output logic [1:0]           multiplier_value,
    output logic [1:0]           hit_multiplier,
    output logic [2:0]           multiplier_leds
);

    integer lane_idx;
    integer unsigned successful_count;
    integer unsigned candidate_streak;
    logic streak_break;

    function automatic logic [1:0] decode_multiplier(
        input integer unsigned streak_count
    );
        begin
            if (streak_count >= MULT3_AT)
                decode_multiplier = 2'd3;
            else if (streak_count >= MULT2_AT)
                decode_multiplier = 2'd2;
            else
                decode_multiplier = 2'd1;
        end
    endfunction

    always_comb begin
        successful_count = 0;
        for (lane_idx = 0; lane_idx < NUM_LANES; lane_idx = lane_idx + 1) begin
            if (normal_hit[lane_idx] || perfect_hit[lane_idx])
                successful_count = successful_count + 1;
        end

        candidate_streak = streak + successful_count;
        if (candidate_streak > MAX_STREAK)
            candidate_streak = MAX_STREAK;

        streak_break      = |(miss | forfeit | stray);
        multiplier_value  = decode_multiplier(streak);
        hit_multiplier    = decode_multiplier(candidate_streak);

        case (multiplier_value)
            2'd2:    multiplier_leds = 3'b110;
            2'd3:    multiplier_leds = 3'b111;
            default: multiplier_leds = 3'b100;
        endcase
    end

    always_ff @(posedge clk) begin
        if (reset)
            streak <= '0;
        else if (streak_break)
            streak <= '0;
        else
            streak <= STREAK_W'(candidate_streak);
    end

    // synthesis translate_off
    initial begin
        if (NUM_LANES < 1)
            $fatal(1, "multiplier: NUM_LANES must be positive");
        if (MULT2_AT < 1 || MULT2_AT >= MULT3_AT)
            $fatal(1, "multiplier: thresholds must satisfy 1 <= MULT2_AT < MULT3_AT");
        if (MAX_STREAK < MULT3_AT)
            $fatal(1, "multiplier: MAX_STREAK must make x3 reachable");
        if (STREAK_W < 1)
            $fatal(1, "multiplier: STREAK_W must be positive");
    end

    always @(posedge clk) begin
        if (!reset && ((normal_hit & perfect_hit) != '0))
            $fatal(1, "multiplier: a lane reported normal and perfect simultaneously");
    end
    // synthesis translate_on

endmodule
