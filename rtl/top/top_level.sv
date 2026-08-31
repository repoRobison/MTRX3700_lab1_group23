//=============================================================================
// top_level.sv  --  MTRX3700 Assignment 1, Piano Tiles
//                   DE1-SoC (Cyclone V, 5CSEMA5F31C6) top level
//
// This is the only file whose ports are physical pins. Every port name below
// must match top_level.qsf EXACTLY, brackets included -- Quartus silently
// DROPS a pin assignment whose name it cannot resolve, so a typo here does not
// error, it just produces a board where nothing works.
//
// ARCHITECTURE: the README's Task 2 / Task 3 split
//   The repository contained two mutually incompatible answers to "what owns a
//   lane". This file wires the one the README describes:
//
//     note_scheduler  owns the future schedule and the countdown values
//     lane_controller owns which lanes are at zero, and the displays
//     hit_detector    owns classifying presses and timing the window out
//
//   Legacy lane_fsm alternatives are deliberately omitted from this clean
//   project. The active architecture is note_scheduler + lane_controller +
//   hit_detector.
//
// R0 (reuse all Reaction Time Game modules) is satisfied through the hierarchy:
//     synchroniser -> inside debounce
//     debounce     -> inside button_input   (7 instances: 4 keys, 3 switches)
//     timer        -> inside beat_gen       (phase timer)
//     rng          -> note scheduler random source
//     reaction_time_fsm -> reset/play/game-over lifecycle
//     bcd_encoder_4 -> inside display       (score conversion)
//     seven_seg    -> inside display x6
//     display      -> all six HEX outputs
//     top_level    -> this FPGA integration boundary
// The lesson modules are adapted where the four-lane game requires it; the
// exact changes are documented in README.md rather than called "unmodified".
//
// DATA FLOW, and where each clock edge lands
//   KEY/SW -> button_input -> pulse -----------------> hit_detector
//   rng ------------------> note_scheduler -- due --> lane_controller
//   beat_gen -- tick -----> note_scheduler
//   beat_gen -- phase_ms -> hit_detector
//   lane_controller -- lane_zero/lane_active -------> hit_detector
//   hit_detector -- hit/miss -----------------------> lane_controller (clears)
//   hit_detector -- 5 event pulses -----------------> multiplier, score
//
//   The hit_detector <-> lane_controller path looks like a loop and is not:
//   lane_zero and lane_active are REGISTER outputs of lane_controller, and
//   hit/miss are combinational functions of them that land on lane_controller's
//   register inputs. One clock edge separates cause from effect.
//
// PARAMETER OVERRIDES ON THIS PAGE ARE FOR HARDWARE
//   The four parameters below default to the hardware numbers in
//   game_params.svh. Only system_tb overrides them. If a "millisecond" ever
//   becomes a few hundred nanoseconds on the board, look here first.
//=============================================================================
`timescale 1ns/1ps
`include "game_params.svh"

module top_level #(
    // THE ONLY PARAMETERS ON THIS PAGE, and all four are pure SCALING knobs.
    // They default to the hardware values in game_params.svh and exist so that
    // system_tb can instantiate this exact netlist with a millisecond that is
    // 20 clocks instead of 50,000 -- otherwise one beat is 25 million cycles
    // and a 15-second scenario is unsimulatable.
    //
    // The rule from game_params.svh applies unchanged: change gameplay by
    // editing the header, make a simulation fast by overriding HERE, at the
    // testbench instantiation. Never edit these defaults to speed a sim up --
    // that is how a scaled value reaches the board, where one "millisecond"
    // becomes a few hundred nanoseconds and the game is unplayable.
    parameter int CLKS_PER_MS   = `GP_CLKS_PER_MS,
    parameter int KEY_DEBOUNCE  = `GP_DEBOUNCE_COUNTS,
    parameter int SW_DEBOUNCE   = `GP_SW_DEBOUNCE_COUNTS,
    parameter int POR_COUNTS    = `GP_POR_COUNTS
) (
    input  logic        CLOCK_50,
    input  logic [3:0]  KEY,        // ACTIVE LOW. Inverted once, inside button_input.
    input  logic [9:0]  SW,         // SW0 reset, SW2:1 level. SW9:3 unused by design.
    output logic [9:0]  LEDR,
    output logic [6:0]  HEX0, HEX1, HEX2, HEX3,   // lane countdowns
    output logic [6:0]  HEX4, HEX5                // score, units then tens
);

    //=========================================================================
    // Task 1 -- input conditioning. Everything downstream is synchronous,
    // debounced, active high and glitch free.
    //=========================================================================
    logic [3:0] press;        // debounced level, exported for waveforms only
    logic [3:0] press_pulse;  // one cycle per NEW press: the R11 contract
    logic       reset;        // SW0 debounced, OR'd with the power-on reset
    logic [1:0] level;        // SW2:1 debounced

    // This is the reset producer the README lists as an input to Tasks 2, 3
    // and 4 without naming a source. It fans out to every module below.
    button_input #(
        .KEY_DEBOUNCE (KEY_DEBOUNCE),
        .SW_DEBOUNCE  (SW_DEBOUNCE),
        .POR_COUNTS   (POR_COUNTS)
    ) u_button_input (
        .clk    (CLOCK_50),
        .KEY    (KEY),
        .SW     (SW[2:0]),
        .press  (press),
        .pulse  (press_pulse),
        .reset  (reset),
        .level  (level)
    );

    //=========================================================================
    // Task 4 -- level selection. A debounced SW2:SW1 change generates a single
    // internal reset cycle. This applies the new level at a clean game boundary
    // without requiring the player to toggle SW0 manually.
    //=========================================================================
    logic [1:0]           difficulty;
    logic [`GP_BPM_W-1:0] beat_bpm;
    logic [`GP_MS_W-1:0]  tick_ms;
    logic [`GP_COUNT_W-1:0] countdown_min;
    logic [`GP_COUNT_W-1:0] countdown_mask;
    logic [`GP_MS_W-1:0]  hit_window_ms;
    logic [`GP_MS_W-1:0]  perfect_window_ms;
    logic [3:0]           spawn_cadence;
    logic [1:0]           max_chord;
    logic [2:0]           difficulty_leds;
    logic                 level_change_reset;
    logic                 game_reset;
    logic                 round_reset;
    logic                 game_active;
    logic                 game_over;
    logic                 won;
    logic                 win_led_on;

    // The adapted lesson FSM owns global lifecycle state.  A reset or level
    // change clears the score; reaching 99 clears only live gameplay and holds
    // the terminal score until the next reset request.
    reaction_time_fsm #(
        .CLKS_PER_MS (CLKS_PER_MS),
        .FLASH_MS    (`GP_WIN_FLASH_MS)
    ) u_reaction_time_fsm (
        .clk                (CLOCK_50),
        .reset_request      (reset),
        .level_switch       (level),
        .won                (won),
        .level_change_reset (level_change_reset),
        .game_reset         (game_reset),
        .round_reset        (round_reset),
        .game_active        (game_active),
        .game_over          (game_over),
        .led_on             (win_led_on)
    );

    level_select u_level_select (
        .clk               (CLOCK_50),
        .reset             (game_reset),
        .level_switch      (level),
        .difficulty        (difficulty),
        .beat_bpm          (beat_bpm),
        .tick_ms           (tick_ms),
        .countdown_min     (countdown_min),
        .countdown_mask    (countdown_mask),
        .hit_window_ms     (hit_window_ms),
        .perfect_window_ms (perfect_window_ms),
        .spawn_cadence     (spawn_cadence),
        .max_chord         (max_chord),
        .difficulty_leds   (difficulty_leds)
    );

    //=========================================================================
    // Task 2 -- musical timebase. tick is the beat; phase_ms is milliseconds
    // since that beat, and is what the hit window is measured against.
    //=========================================================================
    logic                beat_tick;
    logic [`GP_MS_W-1:0] phase_ms;

    beat_gen #(
        .CLKS_PER_MS (CLKS_PER_MS)
    ) u_beat_gen (
        .clk      (CLOCK_50),
        .reset    (round_reset),
        .bpm      (beat_bpm),
        .tick     (beat_tick),
        .phase_ms (phase_ms)
    );

    //=========================================================================
    // Task 3 -- randomness, schedule, lanes
    //=========================================================================
    // rng free-runs and is never reset. It is SAMPLED once per beat, so the
    // pattern the player sees depends on when they release SW0 -- which is why
    // the game does not replay an identical sequence every time on hardware,
    // even though a simulation always does.
    logic [9:0] random_value;

    rng u_rng (
        .clk          (CLOCK_50),
        .random_value (random_value)
    );

    logic [3:0] due_notes;
    logic [3:0] future_active;
    logic [3:0] future_c0, future_c1, future_c2, future_c3;

    // All difficulty controls are run-time ports. The fixed reserve depth is
    // large enough for every permitted countdown and avoids dynamic hardware.
    note_scheduler #(
        .RNG_WIDTH     (10),
        .RESERVE_W     (`GP_RESERVE_W),
        .SPAWN_RETRIES (`GP_SPAWN_RETRIES)
    ) u_note_scheduler (
        .clk           (CLOCK_50),
        .reset         (round_reset),
        .beat_tick     (beat_tick),
        .random_value  (random_value),
        .countdown_min (countdown_min),
        .countdown_mask(countdown_mask),
        .spawn_cadence (spawn_cadence),
        .max_chord     (max_chord),
        .due_notes     (due_notes),
        .countdown0    (future_c0),
        .countdown1    (future_c1),
        .countdown2    (future_c2),
        .countdown3    (future_c3),
        .future_active (future_active)
    );

    logic [3:0] lane_zero, lane_active;
    logic [3:0] disp_c0, disp_c1, disp_c2, disp_c3;

    logic [3:0] normal_hit, perfect_hit, miss, forfeit, stray, led_pulse;

    // lane_controller clears a lane on hit OR miss. Both halves must arrive or
    // the lane sticks at zero forever -- this is the deadlock that made the
    // game freeze after sixteen beats while hit_detector did not exist.
    logic [3:0] any_hit;
    assign any_hit = normal_hit | perfect_hit;

    lane_controller u_lane_controller (
        .clk                (CLOCK_50),
        .reset              (round_reset),
        .due_notes          (due_notes),
        .hit                (any_hit),
        .miss               (miss),
        .future_active      (future_active),
        .future_countdown0  (future_c0),
        .future_countdown1  (future_c1),
        .future_countdown2  (future_c2),
        .future_countdown3  (future_c3),
        .lane_zero          (lane_zero),
        .lane_active        (lane_active),
        .display_countdown0 (disp_c0),
        .display_countdown1 (disp_c1),
        .display_countdown2 (disp_c2),
        .display_countdown3 (disp_c3)
    );

    //=========================================================================
    // Task 2 -- hit classification and the window timeout
    //=========================================================================
    hit_detector #(
        .CLKS_PER_MS      (CLKS_PER_MS),
        .FLASH_MS         (`GP_FLASH_MS),
        .PERFECT_BLINK_MS (`GP_PERFECT_BLINK_MS)
    ) u_hit_detector (
        .clk         (CLOCK_50),
        .reset       (round_reset),
        .press_pulse (press_pulse),
        .lane_zero   (lane_zero),
        .lane_active (lane_active),
        .phase_ms    (phase_ms),
        .win_ms      (hit_window_ms),
        .perfect_ms  (perfect_window_ms),
        .normal_hit  (normal_hit),
        .perfect_hit (perfect_hit),
        .miss        (miss),
        .forfeit     (forfeit),
        .stray       (stray),
        .led_pulse   (led_pulse)
    );

    //=========================================================================
    // Task 4 -- streak, multiplier, score
    //=========================================================================
    // hit_multiplier is the EVENT multiplier: it already includes the successes
    // landing on this clock, so the hit that reaches a threshold receives the
    // multiplier it just unlocked. multiplier_value is the stored one, and is
    // what the LEDs show between hits.
    logic [4:0] streak;
    logic [1:0] multiplier_value, hit_multiplier;
    logic [2:0] multiplier_leds;

    multiplier u_multiplier (
        .clk              (CLOCK_50),
        .reset            (round_reset),
        .normal_hit       (normal_hit),
        .perfect_hit      (perfect_hit),
        .miss             (miss),
        .forfeit          (forfeit),
        .stray            (stray),
        .streak           (streak),
        .multiplier_value (multiplier_value),
        .hit_multiplier   (hit_multiplier),
        .multiplier_leds  (multiplier_leds)
    );

    logic [6:0] score_value;

    // `miss` is deliberately not an input: a timeout breaks the streak but does
    // not subtract score. Only a press the player chose to make is penalised.
    score u_score (
        .clk            (CLOCK_50),
        .reset          (game_reset),
        .normal_hit     (normal_hit),
        .perfect_hit    (perfect_hit),
        .forfeit        (forfeit),
        .stray          (stray),
        .hit_multiplier (hit_multiplier),
        .score          (score_value),
        .won            (won)
    );

    //=========================================================================
    // Displays
    //=========================================================================
    // The adapted lesson display owns blanking, BCD conversion and every
    // seven-segment decoder.  The score remains visible at game over while the
    // four lane displays blank through game_active.
    display u_display (
        .clk         (CLOCK_50),
        .game_active (game_active),
        .value       ({4'b0000, score_value}),
        .lane_active (lane_active),
        .countdown0  (disp_c0),
        .countdown1  (disp_c1),
        .countdown2  (disp_c2),
        .countdown3  (disp_c3),
        .display0    (HEX0),
        .display1    (HEX1),
        .display2    (HEX2),
        .display3    (HEX3),
        .display4    (HEX4),
        .display5    (HEX5)
    );

    //=========================================================================
    // LEDs
    //=========================================================================
    // Brief 2.1: "Lane i uses HEXi and KEYi, while its hit indicator is
    // LEDR(i+3)". Lanes are ZERO-indexed here, so lane 0 lights LEDR3. The
    // README's 1..4 numbering is prose only -- computing LEDR(lane+3) from it
    // puts every indicator one LED too high.
    logic [9:0] gameplay_leds;
    always_comb begin
        gameplay_leds[9:7] = difficulty_leds; // one-hot level indicator (R13)
        gameplay_leds[6:3] = led_pulse;       // normal solid / perfect blinking
        gameplay_leds[2:0] = multiplier_leds; // growing bar: 100, 110, 111
    end

    // A terminal win owns the entire LED bank, making game over unmistakable.
    assign LEDR = game_over ? {10{win_led_on}} : gameplay_leds;

endmodule
