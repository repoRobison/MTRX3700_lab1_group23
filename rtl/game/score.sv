//=============================================================================
// score.sv -- saturating Piano Tiles score counter
//
// DESIGN ROLE
//   score converts one-clock lane result pulses into the two-digit game
//   score. Normal hits are worth GP_BASE_POINTS, perfect hits are worth
//   GP_PERFECT_POINTS, and the complete successful gain is scaled by the
//   hit_multiplier supplied by multiplier.sv. Early/forfeited notes and presses
//   on blank lanes are counted separately because four buttons can be pressed
//   on the same clock and every invalid press carries its own penalty.
//
// ARITHMETIC POLICY
//   All lane events on one clock are accumulated into one signed intermediate:
//
//       next = score + successful gain - forfeit loss - stray loss
//
//   The result clamps to 0..GP_WIN_SCORE, so neither underflow nor binary wrap
//   can create a false high score. Reaching GP_WIN_SCORE is terminal: the score
//   stays there until reset. The future game FSM can therefore stop scheduling
//   on won without a late button event pulling the displayed score below 99.
//
// MULTIPLIER TIMING
//   hit_multiplier is deliberately the event multiplier, not merely the stored
//   multiplier visible before the edge. multiplier.sv calculates it using the
//   streak including every successful note on this clock. Consequently hit 6
//   scores at x2, hit 16 scores at x3, and all lanes of a threshold-crossing
//   chord receive the same newly unlocked value.
//
// SYNTHESIS
//   x1/x2/x3 are expressed as pass-through, shift, and shift-plus-add rather
//   than requiring a general-purpose multiplier. With a 7-bit stored score and
//   a signed integer intermediate, the worst simultaneous gain/loss has ample
//   headroom before the final saturation.
//
// INPUT CONTRACT
//   normal_hit and perfect_hit are mutually exclusive per lane. forfeit means
//   an early press destroyed a live note; stray means a press occurred on an
//   inactive lane. Miss is absent because a timeout resets the streak but does
//   not subtract score under the agreed rules.
//=============================================================================
`timescale 1ns/1ps
`include "game_params.svh"

// The module is named `score` to match score.sv. The supplied test runner uses
// Verilog -y library lookup, which resolves modules by matching module and file
// names; keeping them identical prevents a correct module being reported missing.
module score #(
    parameter int NUM_LANES       = `GP_NUM_LANES,
    parameter int WIN_SCORE       = `GP_WIN_SCORE,
    parameter int BASE_POINTS     = `GP_BASE_POINTS,
    parameter int PERFECT_POINTS  = `GP_PERFECT_POINTS,
    parameter int FORFEIT_PENALTY = `GP_FORFEIT_PENALTY,
    parameter int STRAY_PENALTY   = `GP_STRAY_PENALTY
) (
    input  logic                 clk,
    input  logic                 reset,
    input  logic [NUM_LANES-1:0] normal_hit,
    input  logic [NUM_LANES-1:0] perfect_hit,
    input  logic [NUM_LANES-1:0] forfeit,
    input  logic [NUM_LANES-1:0] stray,
    input  logic [1:0]           hit_multiplier,

    output logic [6:0]           score,
    output logic                 won
);

    integer lane_idx;
    integer unsigned normal_count;
    integer unsigned perfect_count;
    integer unsigned forfeit_count;
    integer unsigned stray_count;
    integer unsigned base_gain;
    integer unsigned scaled_gain;
    integer unsigned total_loss;
    integer signed   score_candidate;

    always_comb begin
        normal_count  = 0;
        perfect_count = 0;
        forfeit_count = 0;
        stray_count   = 0;

        for (lane_idx = 0; lane_idx < NUM_LANES; lane_idx = lane_idx + 1) begin
            if (normal_hit[lane_idx])  normal_count  = normal_count  + 1;
            if (perfect_hit[lane_idx]) perfect_count = perfect_count + 1;
            if (forfeit[lane_idx])     forfeit_count = forfeit_count + 1;
            if (stray[lane_idx])       stray_count   = stray_count   + 1;
        end

        base_gain = normal_count * BASE_POINTS
                  + perfect_count * PERFECT_POINTS;

        case (hit_multiplier)
            2'd2:    scaled_gain = base_gain << 1;
            2'd3:    scaled_gain = base_gain + (base_gain << 1);
            default: scaled_gain = base_gain;
        endcase

        total_loss = forfeit_count * FORFEIT_PENALTY
                   + stray_count * STRAY_PENALTY;
        score_candidate = $signed({1'b0, score})
                        + $signed(scaled_gain)
                        - $signed(total_loss);
    end

    always_ff @(posedge clk) begin
        if (reset)
            score <= 7'd0;
        else if (score == WIN_SCORE)
            score <= score;
        else if (score_candidate <= 0)
            score <= 7'd0;
        else if (score_candidate >= WIN_SCORE)
            score <= 7'(WIN_SCORE);
        else
            score <= 7'(score_candidate);
    end

    assign won = (score == WIN_SCORE);

    // synthesis translate_off
    initial begin
        if (NUM_LANES < 1)
            $fatal(1, "score: NUM_LANES must be positive");
        if (WIN_SCORE < 1 || WIN_SCORE > 127)
            $fatal(1, "score: WIN_SCORE must fit the 7-bit score output");
        if (BASE_POINTS < 1 || PERFECT_POINTS <= BASE_POINTS)
            $fatal(1, "score: perfect points must exceed positive base points");
        if (FORFEIT_PENALTY < 1 || STRAY_PENALTY < 1)
            $fatal(1, "score: penalties must be positive");
    end

    always @(posedge clk) begin
        if (!reset && ((normal_hit & perfect_hit) != '0))
            $fatal(1, "score: a lane reported normal and perfect simultaneously");
        if (!reset && ((normal_hit | perfect_hit) != '0)
            && hit_multiplier != 2'd1
            && hit_multiplier != 2'd2
            && hit_multiplier != 2'd3)
            $fatal(1, "score: hit_multiplier must be 1, 2, or 3");
    end
    // synthesis translate_on

endmodule
