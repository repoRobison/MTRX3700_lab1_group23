/*
* beat_gen.sv
* 
* This code creates the musical beat. It turns the clock ticks from timer.v
* into a difficulty-selected gameplay tick.
*/

`timescale 1ns/1ns

module beat_gen #(
    parameter integer CLKS_PER_MS = 50000
) (
    input  logic        clk,
    input  logic        reset,

    // Length of one musical tick in milliseconds.
    // Easy/Medium/Hard values are supplied by level_select.
    input  logic [10:0] tick_ms,

    // One-clock pulse at the start of every tick.
    output logic        tick,

    // Milliseconds elapsed since the most recent tick.
    output logic [10:0] phase_ms
);

    logic [10:0] t_ms;

    // ------------------------------------------------------------
    // Beat countdown timer
    //
    // Counts down from tick_ms to 0.
    // When t_ms reaches 0, tick becomes high.
    // tick resets/reloads the timer on the next clock edge.
    // ------------------------------------------------------------
    timer #(
        .MAX_MS(2047),
        .CLKS_PER_MS(CLKS_PER_MS)
    ) u_beat (
        .clk(clk),
        .reset(reset || tick),
        .up(1'b0),
        .start_value(tick_ms),
        .enable(1'b1),
        .timer_value(t_ms)
    );

    // tick is high while the countdown timer is at zero.
    // Because the timer is reset on the next clock edge,
    // this lasts for exactly one clock cycle.
    assign tick = (t_ms == 11'd0);


    // ------------------------------------------------------------
    // Phase timer
    //
    // Counts upwards from 0 after every beat.
    // Used by lane_fsm to determine perfect timing and
    // the end of the hit window.
    // ------------------------------------------------------------
    timer #(
        .MAX_MS(2047),
        .CLKS_PER_MS(CLKS_PER_MS)
    ) u_phase (
        .clk(clk),
        .reset(reset || tick),
        .up(1'b1),
        .start_value(11'd0),
        .enable(1'b1),
        .timer_value(phase_ms)
    );

endmodule
