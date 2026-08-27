//=============================================================================
// level_select_tb.sv -- self-checking verification for level_select.sv
//
// TEST STRATEGY
//   This bench checks all four physical SW2:SW1 encodings, including the agreed
//   11-to-Hard clamp. For each selection it checks the latched difficulty, the
//   one-hot LED code, and every timing/scheduler output against game_params.svh.
//   It then moves the switches while reset is low to prove that a live round
//   cannot change difficulty. A final test moves the switches while reset stays
//   asserted to prove the latest settled selection is the one retained.
//
// INPUT ASSUMPTION
//   level_switch represents the already synchronised/debounced SW2:SW1 output
//   from button_input.sv. Mechanical bounce and metastability are tested by the
//   button-input bench; duplicating raw-pin conditioning here would weaken the
//   subsystem boundary rather than improve it.
//
// SIMULATION SPEED
//   level_select contains no real-time counter. All outputs are constant table
//   selections, so hardware timing parameters do not need testbench overrides.
//=============================================================================
`timescale 1ns/1ps
`include "game_params.svh"

module level_select_tb;

    localparam int CLK_P = 20;

    logic clk = 1'b0;
    logic reset;
    logic [1:0] level_switch;
    logic [1:0] difficulty;
    logic [`GP_MS_W-1:0] tick_ms, hit_window_ms, perfect_window_ms;
    logic [`GP_COUNT_W-1:0] countdown_min, countdown_mask;
    logic [3:0] spawn_cadence;
    logic [1:0] max_chord;
    logic [2:0] difficulty_leds;

    int errors = 0;

    level_select dut (
        .clk(clk), .reset(reset), .level_switch(level_switch),
        .difficulty(difficulty), .tick_ms(tick_ms),
        .countdown_min(countdown_min), .countdown_mask(countdown_mask),
        .hit_window_ms(hit_window_ms),
        .perfect_window_ms(perfect_window_ms),
        .spawn_cadence(spawn_cadence), .max_chord(max_chord),
        .difficulty_leds(difficulty_leds)
    );

    /* verilator lint_off BLKSEQ */
    always #(CLK_P/2) clk = ~clk;
    /* verilator lint_on BLKSEQ */

    task automatic check(input bit condition, input string what);
        if (!condition) begin
            errors = errors + 1;
            $display("  FAIL: %s (t=%0t sw=%b level=%0d leds=%b tick=%0d win=%0d perfect=%0d cadence=%0d chord=%0d)",
                     what, $time, level_switch, difficulty, difficulty_leds,
                     tick_ms, hit_window_ms, perfect_window_ms,
                     spawn_cadence, max_chord);
        end
    endtask

    task automatic check_outputs(
        input logic [1:0]             expected_level,
        input logic [`GP_MS_W-1:0]    expected_tick,
        input logic [`GP_COUNT_W-1:0] expected_cmin,
        input logic [`GP_COUNT_W-1:0] expected_cmask,
        input logic [`GP_MS_W-1:0]    expected_window,
        input logic [`GP_MS_W-1:0]    expected_perfect,
        input logic [3:0]             expected_cadence,
        input logic [1:0]             expected_chord,
        input logic [2:0] expected_leds,
        input string what
    );
        begin
            check(difficulty == 2'(expected_level), {what, ": wrong difficulty encoding"});
            check(tick_ms == `GP_MS_W'(expected_tick), {what, ": wrong tick_ms"});
            check(countdown_min == `GP_COUNT_W'(expected_cmin), {what, ": wrong countdown_min"});
            check(countdown_mask == `GP_COUNT_W'(expected_cmask), {what, ": wrong countdown_mask"});
            check(hit_window_ms == `GP_MS_W'(expected_window), {what, ": wrong hit_window_ms"});
            check(perfect_window_ms == `GP_MS_W'(expected_perfect), {what, ": wrong perfect_window_ms"});
            check(spawn_cadence == 4'(expected_cadence), {what, ": wrong spawn_cadence"});
            check(max_chord == 2'(expected_chord), {what, ": wrong max_chord"});
            check(difficulty_leds == expected_leds, {what, ": wrong one-hot LED code"});
            check(difficulty_leds == 3'b001 || difficulty_leds == 3'b010
                  || difficulty_leds == 3'b100,
                  {what, ": difficulty LEDs are not one-hot"});
        end
    endtask

    task automatic latch_and_check(
        input logic [1:0]             switch_value,
        input logic [1:0]             expected_level,
        input logic [`GP_MS_W-1:0]    expected_tick,
        input logic [`GP_COUNT_W-1:0] expected_cmin,
        input logic [`GP_COUNT_W-1:0] expected_cmask,
        input logic [`GP_MS_W-1:0]    expected_window,
        input logic [`GP_MS_W-1:0]    expected_perfect,
        input logic [3:0]             expected_cadence,
        input logic [1:0]             expected_chord,
        input logic [2:0] expected_leds,
        input string what
    );
        begin
            @(negedge clk);
            level_switch = switch_value;
            reset = 1'b1;
            @(posedge clk);
            #1;
            check_outputs(expected_level, expected_tick, expected_cmin,
                          expected_cmask, expected_window, expected_perfect,
                          expected_cadence, expected_chord, expected_leds, what);
            @(negedge clk);
            reset = 1'b0;
        end
    endtask

    initial begin
        $dumpfile("level_select.vcd");
        $dumpvars(0, level_select_tb);

        reset = 1'b1;
        level_switch = 2'b00;

        $display("T1  SW2:SW1=00 selects Easy");
        @(posedge clk); #1;
        check_outputs(0, `GP_L0_TICK_MS, `GP_L0_CMIN, `GP_L0_CMASK,
                      `GP_L0_WIN_MS, `GP_L0_PERFECT_MS,
                      `GP_L0_CADENCE, `GP_L0_MAX_CHORD, 3'b100, "Easy");
        @(negedge clk); reset = 1'b0;

        $display("T2  changing switches during play does not change the latched level");
        @(negedge clk); level_switch = 2'b10;
        repeat (3) @(posedge clk);
        #1;
        check_outputs(0, `GP_L0_TICK_MS, `GP_L0_CMIN, `GP_L0_CMASK,
                      `GP_L0_WIN_MS, `GP_L0_PERFECT_MS,
                      `GP_L0_CADENCE, `GP_L0_MAX_CHORD, 3'b100,
                      "Easy remains latched while reset is low");

        $display("T3  SW2:SW1=01 selects Medium");
        latch_and_check(2'b01, 1, `GP_L1_TICK_MS, `GP_L1_CMIN, `GP_L1_CMASK,
                        `GP_L1_WIN_MS, `GP_L1_PERFECT_MS,
                        `GP_L1_CADENCE, `GP_L1_MAX_CHORD, 3'b010, "Medium");

        $display("T4  SW2:SW1=10 selects Hard");
        latch_and_check(2'b10, 2, `GP_L2_TICK_MS, `GP_L2_CMIN, `GP_L2_CMASK,
                        `GP_L2_WIN_MS, `GP_L2_PERFECT_MS,
                        `GP_L2_CADENCE, `GP_L2_MAX_CHORD, 3'b001, "Hard");

        $display("T5  SW2:SW1=11 clamps safely to Hard");
        latch_and_check(2'b11, 2, `GP_L2_TICK_MS, `GP_L2_CMIN, `GP_L2_CMASK,
                        `GP_L2_WIN_MS, `GP_L2_PERFECT_MS,
                        `GP_L2_CADENCE, `GP_L2_MAX_CHORD, 3'b001, "Reserved clamps to Hard");

        $display("T6  latest switch position while reset is held is retained");
        @(negedge clk); reset = 1'b1; level_switch = 2'b00;
        @(posedge clk); #1;
        check(difficulty == 0, "reset-held first sample is Easy");
        @(negedge clk); level_switch = 2'b01;
        @(posedge clk); #1;
        check_outputs(1, `GP_L1_TICK_MS, `GP_L1_CMIN, `GP_L1_CMASK,
                      `GP_L1_WIN_MS, `GP_L1_PERFECT_MS,
                      `GP_L1_CADENCE, `GP_L1_MAX_CHORD, 3'b010,
                      "reset-held later sample becomes Medium");
        @(negedge clk); reset = 1'b0; level_switch = 2'b10;
        repeat (2) @(posedge clk); #1;
        check(difficulty == 1, "release retains the final reset-held Medium sample");

        if (errors == 0) begin
            $display("level_select_tb: PASS");
            $finish;
        end else begin
            $display("level_select_tb: FAIL (%0d checks failed)", errors);
            $fatal(1, "level_select_tb failed");
        end
    end

    initial begin
        #100000;
        $fatal(1, "level_select_tb: timeout");
    end

endmodule
