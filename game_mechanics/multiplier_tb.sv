//=============================================================================
// multiplier_tb.sv -- self-checking verification for multiplier.sv
//
// TEST STRATEGY
//   This bench checks the externally visible gameplay contract rather than the
//   module's implementation. It verifies both threshold edges, exact LED codes,
//   normal/perfect equivalence for streak building, two-note chords, threshold-
//   crossing chords, every streak-breaking event, mixed success/failure on one
//   clock, and saturation of the streak counter.
//
// SAMPLING hit_multiplier
//   hit_multiplier is intentionally combinational: score.sv samples it on
//   the same rising edge as the result pulses. The bench therefore checks it
//   immediately BEFORE that edge, then checks the committed streak and stable
//   multiplier_value immediately AFTER the edge. Checking hit_multiplier after
//   the edge while an event pulse is still high would describe a hypothetical
//   second event and would be the wrong observation point.
//
// SIMULATION SPEED
//   This module contains no real-time delay. Its only long test is 33 event
//   clocks to prove streak saturation, so no hardware timing parameter needs to
//   be reduced. The bench remains compatible with Verilator 5 --timing mode.
//=============================================================================
`timescale 1ns/1ps
`include "game_params.svh"

module multiplier_tb;

    localparam int LANES     = `GP_NUM_LANES;
    localparam int STREAK_W  = $clog2(`GP_MAX_STREAK + 1);
    localparam int CLK_P     = 20;

    logic clk = 1'b0;
    logic reset;
    logic [LANES-1:0] normal_hit, perfect_hit, miss, forfeit, stray;
    logic [STREAK_W-1:0] streak;
    logic [1:0] multiplier_value, hit_multiplier;
    logic [2:0] multiplier_leds;

    int errors = 0;
    int i;

    multiplier dut (
        .clk(clk), .reset(reset),
        .normal_hit(normal_hit), .perfect_hit(perfect_hit),
        .miss(miss), .forfeit(forfeit), .stray(stray),
        .streak(streak), .multiplier_value(multiplier_value),
        .hit_multiplier(hit_multiplier),
        .multiplier_leds(multiplier_leds)
    );

    /* verilator lint_off BLKSEQ */
    always #(CLK_P/2) clk = ~clk;
    /* verilator lint_on BLKSEQ */

    function automatic logic [2:0] expected_leds(input int mult);
        begin
            case (mult)
                2:       expected_leds = 3'b110;
                3:       expected_leds = 3'b111;
                default: expected_leds = 3'b100;
            endcase
        end
    endfunction

    task automatic check(input bit condition, input string what);
        if (!condition) begin
            errors = errors + 1;
            $display("  FAIL: %s (t=%0t streak=%0d shown=x%0d event=x%0d leds=%b)",
                     what, $time, streak, multiplier_value,
                     hit_multiplier, multiplier_leds);
        end
    endtask

    task automatic clear_events;
        begin
            normal_hit  = '0;
            perfect_hit = '0;
            miss        = '0;
            forfeit     = '0;
            stray       = '0;
        end
    endtask

    task automatic reset_dut;
        begin
            @(negedge clk);
            clear_events();
            reset = 1'b1;
            repeat (2) @(posedge clk);
            #1;
            check(streak == 0, "reset clears the streak");
            check(multiplier_value == 1, "reset returns the displayed multiplier to x1");
            check(multiplier_leds == 3'b100, "reset returns the multiplier LEDs to LEDR2");
            @(negedge clk);
            reset = 1'b0;
        end
    endtask

    task automatic pulse_events(
        input logic [LANES-1:0] n,
        input logic [LANES-1:0] p,
        input logic [LANES-1:0] m,
        input logic [LANES-1:0] f,
        input logic [LANES-1:0] s,
        input int expected_hit_mult,
        input logic [STREAK_W-1:0] expected_streak,
        input int expected_stored_mult,
        input string what
    );
        begin
            @(negedge clk);
            normal_hit  = n;
            perfect_hit = p;
            miss        = m;
            forfeit     = f;
            stray       = s;
            #1;
            check(hit_multiplier == expected_hit_mult,
                  {what, ": wrong multiplier for the event edge"});

            @(posedge clk);
            #1;
            check(streak == STREAK_W'(expected_streak),
                  {what, ": wrong stored streak after the edge"});
            check(multiplier_value == expected_stored_mult,
                  {what, ": wrong displayed multiplier after the edge"});
            check(multiplier_leds == expected_leds(expected_stored_mult),
                  {what, ": wrong multiplier LED bar"});
            clear_events();
        end
    endtask

    initial begin
        $dumpfile("multiplier.vcd");
        $dumpvars(0, multiplier_tb);

        reset = 1'b1;
        clear_events();

        $display("T1  reset and initial x1 state");
        repeat (2) @(posedge clk);
        #1;
        check(streak == 0, "initial reset streak");
        check(multiplier_value == 1, "initial multiplier is x1");
        check(multiplier_leds == 3'b100, "initial LED bar starts at LEDR2");
        @(negedge clk);
        reset = 1'b0;

        $display("T2  hits 1..5 remain x1; hit 6 receives and stores x2");
        for (i = 1; i <= 5; i = i + 1)
            pulse_events(4'b0001, '0, '0, '0, '0,
                         1, STREAK_W'(i), 1, $sformatf("clean hit %0d", i));
        pulse_events(4'b0001, '0, '0, '0, '0,
                     2, 6, 2, "threshold hit 6");

        $display("T3  hits 7..15 remain x2; hit 16 receives and stores x3");
        for (i = 7; i <= 15; i = i + 1)
            pulse_events(4'b0001, '0, '0, '0, '0,
                         2, STREAK_W'(i), 2, $sformatf("clean hit %0d", i));
        pulse_events('0, 4'b0001, '0, '0, '0,
                     3, 16, 3, "perfect threshold hit 16");
        pulse_events('0, 4'b0100, '0, '0, '0,
                     3, 17, 3, "perfect hits advance the streak like normal hits");

        $display("T4  a two-note chord crossing 4->6 gives both notes x2");
        reset_dut();
        for (i = 1; i <= 4; i = i + 1)
            pulse_events(4'b0001, '0, '0, '0, '0,
                         1, STREAK_W'(i), 1, $sformatf("setup hit %0d", i));
        pulse_events(4'b0011, '0, '0, '0, '0,
                     2, 6, 2, "x2 threshold-crossing chord");

        $display("T5  a mixed normal/perfect chord crossing 14->16 gives x3");
        reset_dut();
        for (i = 1; i <= 14; i = i + 1)
            pulse_events(4'b0001, '0, '0, '0, '0,
                         (i >= 6) ? 2 : 1, STREAK_W'(i), (i >= 6) ? 2 : 1,
                         $sformatf("setup hit %0d", i));
        pulse_events(4'b0001, 4'b0010, '0, '0, '0,
                     3, 16, 3, "x3 threshold-crossing mixed chord");

        $display("T6  miss, forfeit, and stray each break the stored streak");
        pulse_events('0, '0, 4'b0001, '0, '0,
                     3, 0, 1, "miss reset");
        pulse_events(4'b0001, '0, '0, '0, '0,
                     1, 1, 1, "setup before forfeit");
        pulse_events('0, '0, '0, 4'b0010, '0,
                     1, 0, 1, "forfeit reset");
        pulse_events('0, 4'b0001, '0, '0, '0,
                     1, 1, 1, "setup before stray");
        pulse_events('0, '0, '0, '0, 4'b0100,
                     1, 0, 1, "stray reset");

        $display("T7  valid gain can cross a threshold while a simultaneous stray resets storage");
        for (i = 1; i <= 5; i = i + 1)
            pulse_events(4'b0001, '0, '0, '0, '0,
                         1, STREAK_W'(i), 1, $sformatf("mixed-event setup hit %0d", i));
        pulse_events(4'b0001, '0, '0, '0, 4'b1000,
                     2, 0, 1, "hit 6 scores x2 but simultaneous stray breaks streak");

        $display("T8  streak saturates at GP_MAX_STREAK without wrapping");
        reset_dut();
        for (i = 1; i <= `GP_MAX_STREAK + 2; i = i + 1)
            pulse_events(4'b0001, '0, '0, '0, '0,
                         (i >= `GP_MULT3_STREAK) ? 3 :
                         (i >= `GP_MULT2_STREAK) ? 2 : 1,
                         STREAK_W'((i > `GP_MAX_STREAK) ? `GP_MAX_STREAK : i),
                         (i >= `GP_MULT3_STREAK) ? 3 :
                         (i >= `GP_MULT2_STREAK) ? 2 : 1,
                         $sformatf("saturation hit %0d", i));

        if (errors == 0) begin
            $display("multiplier_tb: PASS");
            $finish;
        end else begin
            $display("multiplier_tb: FAIL (%0d checks failed)", errors);
            $fatal(1, "multiplier_tb failed");
        end
    end

    initial begin
        #200000;
        $fatal(1, "multiplier_tb: timeout");
    end

endmodule
