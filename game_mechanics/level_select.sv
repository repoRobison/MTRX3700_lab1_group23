//=============================================================================
// level_select.sv -- reset-latched Easy/Medium/Hard parameter selector
//
// DESIGN ROLE
//   The board exposes three gameplay levels through SW2:SW1. button_input.sv
//   synchronises and debounces those switches and supplies level_switch here.
//   This module converts the two-bit selection into one stable difficulty and
//   the complete set of run-time timing/scheduler parameters used by the other
//   subsystems.
//
// WHY THE LEVEL IS LATCHED
//   Difficulty is sampled only while reset is asserted. top_level generates a
//   one-clock game reset automatically when debounced SW2:SW1 changes, so the
//   new level applies at a clean round boundary without altering live timing.
//   SW0 remains the manual reset. While reset stays high, the latest settled
//   switch position is sampled on every clock.
//
// SWITCH AND LED MAPPING
//       SW2:SW1  difficulty  LEDR9:7 (difficulty_leds)
//          00       Easy              100  (LEDR9)
//          01       Medium            010
//          10       Hard              001  (LEDR7)
//          11       Hard              001  (LEDR7)
//
//   Encoding 11 is clamped to Hard instead of creating a fourth undocumented
//   level. The one-hot LED output can be flashed by the future PRESTART game-FSM
//   state and then shown steadily during play. multiplier.sv independently owns
//   LEDR2:0, leaving LEDR6:3 available for the four hit indicators.
//
// PARAMETER OWNERSHIP
//   No gameplay number is duplicated here. Every value comes from
//   game_params.svh, so a live demonstration change remains a one-file edit and
//   params_tb.sv continues to validate the relationships between the values.
//=============================================================================
`timescale 1ns/1ps
`include "game_params.svh"

module level_select (
    input  logic                     clk,
    input  logic                     reset,
    input  logic [1:0]               level_switch,

    output logic [1:0]               difficulty,
    output logic [`GP_BPM_W-1:0]     beat_bpm,
    output logic [`GP_MS_W-1:0]      tick_ms,
    output logic [`GP_COUNT_W-1:0]   countdown_min,
    output logic [`GP_COUNT_W-1:0]   countdown_mask,
    output logic [`GP_MS_W-1:0]      hit_window_ms,
    output logic [`GP_MS_W-1:0]      perfect_window_ms,
    output logic [3:0]               spawn_cadence,
    output logic [1:0]               max_chord,
    output logic [2:0]               difficulty_leds
);

    localparam logic [1:0] EASY   = 2'd0;
    localparam logic [1:0] MEDIUM = 2'd1;
    localparam logic [1:0] HARD   = 2'd2;

    always_ff @(posedge clk) begin
        if (reset) begin
            case (level_switch)
                2'b00:   difficulty <= EASY;
                2'b01:   difficulty <= MEDIUM;
                default: difficulty <= HARD;
            endcase
        end
    end

    always_comb begin
        case (difficulty)
            EASY: begin
                beat_bpm          = `GP_BPM_W'(`GP_L0_BPM);
                tick_ms           = `GP_MS_W'(`GP_L0_TICK_MS);
                countdown_min     = `GP_COUNT_W'(`GP_L0_CMIN);
                countdown_mask    = `GP_COUNT_W'(`GP_L0_CMASK);
                hit_window_ms     = `GP_MS_W'(`GP_L0_WIN_MS);
                perfect_window_ms = `GP_MS_W'(`GP_L0_PERFECT_MS);
                spawn_cadence     = 4'(`GP_L0_CADENCE);
                max_chord         = 2'(`GP_L0_MAX_CHORD);
                difficulty_leds   = 3'b100;
            end

            MEDIUM: begin
                beat_bpm          = `GP_BPM_W'(`GP_L1_BPM);
                tick_ms           = `GP_MS_W'(`GP_L1_TICK_MS);
                countdown_min     = `GP_COUNT_W'(`GP_L1_CMIN);
                countdown_mask    = `GP_COUNT_W'(`GP_L1_CMASK);
                hit_window_ms     = `GP_MS_W'(`GP_L1_WIN_MS);
                perfect_window_ms = `GP_MS_W'(`GP_L1_PERFECT_MS);
                spawn_cadence     = 4'(`GP_L1_CADENCE);
                max_chord         = 2'(`GP_L1_MAX_CHORD);
                difficulty_leds   = 3'b010;
            end

            default: begin
                beat_bpm          = `GP_BPM_W'(`GP_L2_BPM);
                tick_ms           = `GP_MS_W'(`GP_L2_TICK_MS);
                countdown_min     = `GP_COUNT_W'(`GP_L2_CMIN);
                countdown_mask    = `GP_COUNT_W'(`GP_L2_CMASK);
                hit_window_ms     = `GP_MS_W'(`GP_L2_WIN_MS);
                perfect_window_ms = `GP_MS_W'(`GP_L2_PERFECT_MS);
                spawn_cadence     = 4'(`GP_L2_CADENCE);
                max_chord         = 2'(`GP_L2_MAX_CHORD);
                difficulty_leds   = 3'b001;
            end
        endcase
    end

endmodule
