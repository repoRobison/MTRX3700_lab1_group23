/*
* beat_gen.sv
* 
 * This code creates the musical beat. A fractional phase accumulator produces
 * an exact average integer BPM without rounding the period to milliseconds.
 * timer.v remains the millisecond phase source used by the hit detector.
*/

`timescale 1ns/1ns

module beat_gen #(
    parameter integer CLKS_PER_MS = 50000
) (
    input  logic        clk,
    input  logic        reset,

    // Musical tempo supplied by level_select.
    input  logic [7:0]  bpm,

    // One-clock pulse at the start of every tick.
    output logic        tick,

    // Milliseconds elapsed since the most recent tick.
    output logic [10:0] phase_ms
);

    // There are 60,000 milliseconds in one minute. Adding BPM once per clock
    // and subtracting this threshold on overflow emits exactly BPM ticks in
    // exactly one minute of FPGA clocks. Non-integral periods are represented
    // by adjacent whole-clock intervals, so there is no cumulative drift.
    localparam integer ACC_W =
        $clog2((64'd60000 * CLKS_PER_MS) + 64'd256);
    localparam logic [ACC_W:0] CLOCKS_PER_MINUTE =
        64'd60000 * CLKS_PER_MS;

    logic [ACC_W:0] beat_phase;
    logic [ACC_W:0] beat_sum;

    always_comb begin
        beat_sum = beat_phase + bpm;
    end

    always_ff @(posedge clk) begin
        if (reset || (bpm == 0)) begin
            beat_phase <= '0;
            tick       <= 1'b0;
        end else if (beat_sum >= CLOCKS_PER_MINUTE) begin
            beat_phase <= beat_sum - CLOCKS_PER_MINUTE;
            tick       <= 1'b1;
        end else begin
            beat_phase <= beat_sum;
            tick       <= 1'b0;
        end
    end


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
