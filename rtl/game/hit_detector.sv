//=============================================================================
// hit_detector.sv -- Task 2: hit classification, miss timeout, hit-indicator LEDs
//
// STATUS: DRAFT. This file did not exist; top_level.sv cannot be wired without
// it, so it is written here to make the project buildable. Task 2 owns it and
// should review every line before the demo.
//
// WHY IT MATTERS MORE THAN ITS SIZE SUGGESTS
//   It is the only consumer of button_input's press_pulse and the only producer
//   of all five of score/multiplier's event inputs. Until it existed, Task 1 and
//   Task 4 were connected to nothing.
//
//   It is also the module that stops the game locking up. lane_controller holds
//   a lane in the zero window until it sees hit or miss and has NO timeout of
//   its own; with this module absent, every lane sticks at zero within about
//   sixteen beats and the game freezes. The `miss` output below is the timeout.
//
// THE FIVE OUTCOMES OF A PRESS
//   A press on lane i is exactly one of:
//     lane_zero[i]                        -> a hit  (perfect or normal)
//     lane_active[i] & ~lane_zero[i]      -> forfeit: pressed while still
//                                            counting down (R11's second half)
//     ~lane_active[i]                     -> stray: pressed a blank lane
//   and independently of any press:
//     lane_zero[i] & window expired       -> miss
//
// MUTUAL EXCLUSION IS A HARD CONTRACT
//   score.sv and multiplier.sv both $fatal if a lane reports normal_hit and
//   perfect_hit on the same clock. lane_fsm got this wrong -- its
//   `perfect = hit && (phase_ms < PERFECT_MS)` leaves `hit` asserted too, which
//   trips the assertion the moment it is wired up. The decomposition here is
//   normal_hit = hit & ~perfect, which is disjoint by construction.
//
// WHY phase_ms IS THE RIGHT CLOCK FOR THE WINDOW
//   beat_gen resets the phase timer on every tick, so phase_ms is milliseconds
//   since the last beat. A note becomes due two clocks after a tick
//   (note_scheduler registers due_notes, lane_controller registers zero_active),
//   by which point phase_ms has already returned to zero. Forty nanoseconds of
//   skew against a 125 ms window is not worth correcting.
//
// ONE-CYCLE PULSES
//   press_pulse is already one cycle wide (button_input guarantees it
//   structurally). miss is self-limiting: asserting it clears lane_controller's
//   zero_active on the same edge, which removes the condition that produced it.
//=============================================================================
`timescale 1ns/1ps
`include "game_params.svh"

module hit_detector #(
    parameter int NUM_LANES   = `GP_NUM_LANES,
    parameter int CLKS_PER_MS = `GP_CLKS_PER_MS,
    parameter int FLASH_MS    = `GP_FLASH_MS,
    parameter int PERFECT_BLINK_MS = `GP_PERFECT_BLINK_MS,
    parameter int MS_W        = `GP_MS_W
) (
    input  logic                 clk,
    input  logic                 reset,

    // Task 1
    input  logic [NUM_LANES-1:0] press_pulse,

    // Task 3
    input  logic [NUM_LANES-1:0] lane_zero,    // note sitting in the hit window
    input  logic [NUM_LANES-1:0] lane_active,  // lane is showing anything at all

    // Task 2's own timebase, and Task 4's level parameters
    input  logic [MS_W-1:0]      phase_ms,
    input  logic [MS_W-1:0]      win_ms,
    input  logic [MS_W-1:0]      perfect_ms,

    // Task 4 scoring events -- all one clock wide
    output logic [NUM_LANES-1:0] normal_hit,
    output logic [NUM_LANES-1:0] perfect_hit,
    output logic [NUM_LANES-1:0] miss,
    output logic [NUM_LANES-1:0] forfeit,
    output logic [NUM_LANES-1:0] stray,

    // R2: hit indicator, LEDR6:3
    output logic [NUM_LANES-1:0] led_pulse
);

    //-------------------------------------------------------------------------
    // Classification
    //-------------------------------------------------------------------------
    logic [NUM_LANES-1:0] hit;
    logic                 in_perfect;
    logic                 window_open;

    // Both are level comparisons on the shared phase timer, so every lane is
    // judged against the same instant. Perfect is one-sided: a press before the
    // note lands is a forfeit, never an early "perfect".
    assign in_perfect  = (phase_ms <  perfect_ms);
    assign window_open = (phase_ms <  win_ms);

    integer i;
    always_comb begin
        for (i = 0; i < NUM_LANES; i = i + 1) begin
            hit[i]         = press_pulse[i] &  lane_zero[i];
            perfect_hit[i] = hit[i]         &  in_perfect;
            normal_hit[i]  = hit[i]         & ~in_perfect;
            forfeit[i]     = press_pulse[i] &  lane_active[i] & ~lane_zero[i];
            stray[i]       = press_pulse[i] & ~lane_active[i];

            // Timeout. ~hit[i] resolves the tie when a press lands on the exact
            // clock the window shuts: the player gets the note.
            miss[i]        = lane_zero[i] & ~window_open & ~hit[i];
        end
    end

    //-------------------------------------------------------------------------
    // Hit indicator one-shot (R2: 200..500 ms)
    //-------------------------------------------------------------------------
    // A millisecond strobe shared by all four lanes, so the per-lane state is
    // one 8-bit counter each rather than four 24-bit counters.
    localparam int DIV_W   = $clog2(CLKS_PER_MS);
    localparam int FLASH_W = $clog2(FLASH_MS + 1);
    localparam int BLINK_W = $clog2(PERFECT_BLINK_MS + 1);

    logic [DIV_W-1:0] ms_div;
    logic             ms_strobe;

    always_ff @(posedge clk) begin
        if (reset)                             ms_div <= '0;
        else if (ms_div == DIV_W'(CLKS_PER_MS - 1)) ms_div <= '0;
        else                                   ms_div <= ms_div + DIV_W'(1);
    end

    assign ms_strobe = (ms_div == DIV_W'(CLKS_PER_MS - 1));

    logic [FLASH_W-1:0] flash       [NUM_LANES];
    logic [BLINK_W-1:0] blink_ms    [NUM_LANES];
    logic               perfect_style [NUM_LANES];
    logic               blink_on      [NUM_LANES];

    integer j;
    always_ff @(posedge clk) begin
        if (reset) begin
            for (j = 0; j < NUM_LANES; j = j + 1) begin
                flash[j]         <= '0;
                blink_ms[j]      <= '0;
                perfect_style[j] <= 1'b0;
                blink_on[j]      <= 1'b1;
            end
        end
        else begin
            for (j = 0; j < NUM_LANES; j = j + 1) begin
                // A normal hit remains one solid flash. A perfect hit uses the
                // same total event duration but alternates on/off rapidly.
                if (hit[j]) begin
                    flash[j]         <= FLASH_W'(FLASH_MS);
                    blink_ms[j]      <= '0;
                    perfect_style[j] <= perfect_hit[j];
                    blink_on[j]      <= 1'b1;
                end
                else if (ms_strobe && (flash[j] != '0)) begin
                    flash[j] <= flash[j] - FLASH_W'(1);

                    if (perfect_style[j]) begin
                        if (blink_ms[j] == BLINK_W'(PERFECT_BLINK_MS - 1)) begin
                            blink_ms[j] <= '0;
                            blink_on[j] <= ~blink_on[j];
                        end else begin
                            blink_ms[j] <= blink_ms[j] + BLINK_W'(1);
                        end
                    end

                    // Return to the normal solid style when the event ends.
                    if (flash[j] == FLASH_W'(1)) begin
                        blink_ms[j]      <= '0;
                        perfect_style[j] <= 1'b0;
                        blink_on[j]      <= 1'b1;
                    end
                end
            end
        end
    end

    integer k;
    always_comb begin
        for (k = 0; k < NUM_LANES; k = k + 1)
            led_pulse[k] = (flash[k] != '0)
                         & (!perfect_style[k] | blink_on[k]);
    end

    //-------------------------------------------------------------------------
    // Guards (simulation only)
    //-------------------------------------------------------------------------
    // synthesis translate_off
    initial begin
        if (FLASH_MS < 200 || FLASH_MS > 500)
            $fatal(1, "hit_detector: FLASH_MS (%0d) is outside R2's 200-500 ms band", FLASH_MS);
        if (PERFECT_BLINK_MS < 1 || PERFECT_BLINK_MS >= FLASH_MS)
            $fatal(1, "hit_detector: PERFECT_BLINK_MS (%0d) must be between 1 and FLASH_MS-1", PERFECT_BLINK_MS);
        if (CLKS_PER_MS < 2)
            $fatal(1, "hit_detector: CLKS_PER_MS (%0d) must be at least 2", CLKS_PER_MS);
    end

    always @(posedge clk) begin
        if (!reset) begin
            // The contract score.sv and multiplier.sv both enforce.
            if ((normal_hit & perfect_hit) != '0)
                $fatal(1, "hit_detector: a lane reported normal and perfect together");
            // A press is exactly one outcome.
            if (((hit & forfeit) | (hit & stray) | (forfeit & stray)) != '0)
                $fatal(1, "hit_detector: a press produced more than one outcome");
            // Never score a lane that is not showing a note.
            if ((hit & ~lane_active) != '0)
                $fatal(1, "hit_detector: scored a hit on an inactive lane");
        end
    end
    // synthesis translate_on

endmodule
