//=============================================================================
// display.sv -- complete Piano Tiles six-display controller
//
// Adapted from the Reaction Time Game display module.  The original score path
// (bcd_encoder_4 feeding seven_seg) is retained and expanded with four lane
// displays so every physical HEX output is owned in one place.
//=============================================================================
`timescale 1ns/1ps
`include "game_params.svh"

module display (
    input  logic        clk,
    input  logic        game_active,
    input  logic [10:0] value,
    input  logic [3:0]  lane_active,
    input  logic [3:0]  countdown0,
    input  logic [3:0]  countdown1,
    input  logic [3:0]  countdown2,
    input  logic [3:0]  countdown3,
    output logic [6:0]  display0,
    output logic [6:0]  display1,
    output logic [6:0]  display2,
    output logic [6:0]  display3,
    output logic [6:0]  display4,
    output logic [6:0]  display5
);

    logic [3:0] score_units;
    logic [3:0] score_tens;
    logic [3:0] score_hundreds;
    logic [3:0] score_thousands;
    logic       score_fits_two_digits;

    bcd_encoder_4 u_bcd_encoder_4 (
        .clk    (clk),
        .value  (value),
        .digit0 (score_units),
        .digit1 (score_tens),
        .digit2 (score_hundreds),
        .digit3 (score_thousands)
    );

    // Piano Tiles owns two score displays.  Values above 99 are blanked rather
    // than misleadingly truncating to their final two digits.
    assign score_fits_two_digits = (score_hundreds == 4'd0)
                                 && (score_thousands == 4'd0);

    logic [3:0] lane_digit0;
    logic [3:0] lane_digit1;
    logic [3:0] lane_digit2;
    logic [3:0] lane_digit3;
    logic [3:0] score_digit0;
    logic [3:0] score_digit1;

    always_comb begin
        lane_digit0 = (game_active && lane_active[0])
                    ? countdown0 : `GP_BLANK_DIGIT;
        lane_digit1 = (game_active && lane_active[1])
                    ? countdown1 : `GP_BLANK_DIGIT;
        lane_digit2 = (game_active && lane_active[2])
                    ? countdown2 : `GP_BLANK_DIGIT;
        lane_digit3 = (game_active && lane_active[3])
                    ? countdown3 : `GP_BLANK_DIGIT;

        score_digit0 = score_fits_two_digits
                     ? score_units : `GP_BLANK_DIGIT;
        score_digit1 = score_fits_two_digits
                     ? score_tens : `GP_BLANK_DIGIT;
    end

    seven_seg u_lane0  (.bcd(lane_digit0),  .segments(display0));
    seven_seg u_lane1  (.bcd(lane_digit1),  .segments(display1));
    seven_seg u_lane2  (.bcd(lane_digit2),  .segments(display2));
    seven_seg u_lane3  (.bcd(lane_digit3),  .segments(display3));
    seven_seg u_score0 (.bcd(score_digit0), .segments(display4));
    seven_seg u_score1 (.bcd(score_digit1), .segments(display5));

endmodule
