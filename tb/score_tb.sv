//=============================================================================
// score_tb.sv -- self-checking verification for score.sv
//
// TEST STRATEGY
//   The multiplier controller is intentionally not instantiated here: this is
//   a score-counter unit test, so hit_multiplier is driven directly to isolate
//   arithmetic defects. The integration/system bench will later connect the two
//   modules. Tests cover x1/x2/x3, normal/perfect weighting, simultaneous lanes,
//   independent per-button penalties, mixed gains/losses, lower saturation,
//   upper saturation, terminal win behaviour, idle clocks, and reset from win.
//
// EVENT MODEL
//   All result vectors are one-clock pulses. A task applies them before a rising
//   edge and checks score immediately after it. normal_hit and perfect_hit use
//   disjoint lane bits, matching the upstream interface contract. Miss is not a
//   score input because it resets the multiplier without subtracting a
//   point under the agreed game rules.
//
// SIMULATION SPEED
//   No millisecond timing exists in this module, so parameter reduction is not
//   applicable. Every arithmetic boundary is reached in a handful of clocks.
//=============================================================================
`timescale 1ns/1ps
`include "game_params.svh"

module score_tb;

    localparam int LANES = `GP_NUM_LANES;
    localparam int CLK_P = 20;

    logic clk = 1'b0;
    logic reset;
    logic [LANES-1:0] normal_hit, perfect_hit, forfeit, stray;
    logic [1:0] hit_multiplier;
    logic [6:0] score;
    logic won;

    int errors = 0;
    int i;

    score dut (
        .clk(clk), .reset(reset),
        .normal_hit(normal_hit), .perfect_hit(perfect_hit),
        .forfeit(forfeit), .stray(stray),
        .hit_multiplier(hit_multiplier),
        .score(score), .won(won)
    );

    /* verilator lint_off BLKSEQ */
    always #(CLK_P/2) clk = ~clk;
    /* verilator lint_on BLKSEQ */

    task automatic check(input bit condition, input string what);
        if (!condition) begin
            errors = errors + 1;
            $display("  FAIL: %s (t=%0t score=%0d won=%b mult=x%0d n=%b p=%b f=%b s=%b)",
                     what, $time, score, won, hit_multiplier,
                     normal_hit, perfect_hit, forfeit, stray);
        end
    endtask

    task automatic clear_events;
        begin
            normal_hit  = '0;
            perfect_hit = '0;
            forfeit     = '0;
            stray       = '0;
            hit_multiplier = 2'd1;
        end
    endtask

    task automatic reset_dut;
        begin
            @(negedge clk);
            clear_events();
            reset = 1'b1;
            repeat (2) @(posedge clk);
            #1;
            check(score == 0, "reset clears score");
            check(won == 0, "reset clears won");
            @(negedge clk);
            reset = 1'b0;
        end
    endtask

    task automatic pulse_score(
        input logic [LANES-1:0] n,
        input logic [LANES-1:0] p,
        input logic [LANES-1:0] f,
        input logic [LANES-1:0] s,
        input logic [1:0] mult,
        input logic [6:0] expected_score,
        input bit expected_won,
        input string what
    );
        begin
            @(negedge clk);
            normal_hit    = n;
            perfect_hit   = p;
            forfeit       = f;
            stray         = s;
            hit_multiplier = 2'(mult);
            @(posedge clk);
            #1;
            check(score == 7'(expected_score), {what, ": wrong score"});
            check(won == expected_won, {what, ": wrong won output"});
            clear_events();
        end
    endtask

    initial begin
        $dumpfile("score.vcd");
        $dumpvars(0, score_tb);

        reset = 1'b1;
        clear_events();

        $display("T1  reset and idle clocks");
        repeat (2) @(posedge clk);
        #1;
        check(score == 0, "initial score is zero");
        check(won == 0, "initial won is low");
        @(negedge clk);
        reset = 1'b0;
        pulse_score('0, '0, '0, '0, 1, 0, 0, "idle edge preserves score");

        $display("T2  normal/perfect weights and all three multipliers");
        pulse_score(4'b0001, '0, '0, '0, 1, 1, 0, "one normal at x1");
        pulse_score('0, 4'b0010, '0, '0, 1, 3, 0, "one perfect at x1");
        pulse_score(4'b0011, '0, '0, '0, 2, 7, 0, "two normals at x2");
        pulse_score(4'b0001, 4'b0010, '0, '0, 3, 16, 0,
                    "normal plus perfect chord at x3");

        $display("T3  penalties are summed across lanes");
        pulse_score('0, '0, 4'b0011, 4'b1100, 1, 12, 0,
                    "two forfeits plus two strays subtract four");

        $display("T4  simultaneous valid gains and penalties share one signed update");
        pulse_score(4'b0001, 4'b0010, 4'b0100, 4'b1000, 2, 16, 0,
                    "six points gained and two penalties lost");

        $display("T5  lower saturation prevents unsigned wrap");
        reset_dut();
        pulse_score(4'b0001, '0, '0, '0, 1, 1, 0, "setup one point");
        pulse_score('0, '0, 4'b0011, 4'b1100, 1, 0, 0,
                    "four penalties clamp one point to zero");
        pulse_score('0, '0, '0, 4'b1111, 1, 0, 0,
                    "penalties at zero stay at zero");

        $display("T6  upper saturation, won, and terminal score hold");
        reset_dut();
        for (i = 1; i <= 4; i = i + 1)
            pulse_score('0, 4'b1111, '0, '0, 3, 7'(i * 24), 0,
                        $sformatf("four-perfect gain block %0d", i));
        pulse_score('0, 4'b0001, '0, '0, 3, 99, 1,
                    "overshoot from 96 saturates at 99");
        pulse_score('0, '0, 4'b1111, 4'b1111, 1, 99, 1,
                    "won score remains terminal despite later penalties");
        pulse_score(4'b1111, '0, '0, '0, 3, 99, 1,
                    "won score remains terminal despite later gains");

        $display("T7  reset is the only way out of the terminal win score");
        reset_dut();
        check(score == 0, "reset after win returns score to zero");
        check(won == 0, "reset after win deasserts won");

        if (errors == 0) begin
            $display("score_tb: PASS");
            $finish;
        end else begin
            $display("score_tb: FAIL (%0d checks failed)", errors);
            $fatal(1, "score_tb failed");
        end
    end

    initial begin
        #100000;
        $fatal(1, "score_tb: timeout");
    end

endmodule
