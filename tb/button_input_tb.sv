//=============================================================================
// button_input_tb.sv  --  self-checking unit test for button_input
//
// Parameters are scaled down at instantiation so a full test runs in a few
// hundred cycles rather than a few hundred thousand. The RTL is bit identical;
// this is the same override discipline the brief asks for in section 2.5.
//
// Propagation latency is DELAY_COUNTS + 4 clocks, measured, not 9 as an
// earlier revision of this header claimed: two synchroniser flops, then
// prev_button, then the counter climbing to DELAY_COUNTS, then the output
// register. At KEY_DEBOUNCE = 8 that is 12 clocks, so a 3-cycle glitch is
// comfortably rejected and a 20-cycle press comfortably accepted.
//
// KEY_DEBOUNCE and SW_DEBOUNCE are deliberately DIFFERENT here. When they were
// both 8 the bench could not tell the two roles apart, and a fault that gave
// SW0 the key-grade depth survived undetected -- the scaled-down parameters had
// erased the very property the module exists to provide. If two constants exist
// because they must differ, a scaled bench has to keep them differing.
//=============================================================================
`timescale 1ns/1ps
`include "game_params.svh"

module button_input_tb;

    localparam int LANES        = `GP_NUM_LANES;
    localparam int KEY_DEBOUNCE = 8;
    localparam int SW_DEBOUNCE  = 24;                    // must differ from KEY
    localparam int KEY_LAT      = KEY_DEBOUNCE + 4;      // measured latency
    localparam int SW_LAT       = SW_DEBOUNCE  + 4;
    localparam int POR_COUNTS   = 40;                    // must be >= SW_LAT
    localparam int CLK_P        = 20;

    logic             clk = 1'b0;
    logic [LANES-1:0] KEY;
    logic [2:0]       SW;

    logic [LANES-1:0] press, pulse;
    logic             reset;
    logic [1:0]       level;

    int errors = 0;
    int cyc    = 0;
    always_ff @(posedge clk) cyc <= cyc + 1;
    int n_pulse [LANES];
    int b_pulse [LANES];
    int max_simultaneous = 0;

    button_input #(
        .NUM_LANES(LANES), .KEY_DEBOUNCE(KEY_DEBOUNCE),
        .SW_DEBOUNCE(SW_DEBOUNCE), .POR_COUNTS(POR_COUNTS)
    ) dut (
        .clk(clk), .KEY(KEY), .SW(SW),
        .press(press), .pulse(pulse),
        .reset(reset), .level(level)
    );

    // See lane_fsm_tb: blocking assignment is correct for a testbench clock.
    // Do not write the linter's name in a plain comment anywhere in this file.
    /* verilator lint_off BLKSEQ */
    always #(CLK_P/2) clk = ~clk;
    /* verilator lint_on BLKSEQ */

    // Count CYCLES a pulse is high, not pulses. A signal that degenerates into
    // a level then shows up as a count in the hundreds rather than a mismatch
    // of one -- which matters because every pulse now costs or earns a point.
    int j;
    always_ff @(posedge clk) begin
        int c;
        c = 0;
        for (j = 0; j < LANES; j++) begin
            if (pulse[j]) begin
                n_pulse[j] <= n_pulse[j] + 1;
                c = c + 1;
            end
        end
        if (c > max_simultaneous) max_simultaneous <= c;
    end

    task automatic step(int n = 1);
        repeat (n) @(posedge clk);
        #1;
    endtask

    task automatic snap();
        int k;
        for (k = 0; k < LANES; k++) b_pulse[k] = n_pulse[k];
    endtask

    task automatic check(bit cond, string what);
        if (!cond) begin
            errors = errors + 1;
            $display("  FAIL: %s   (t=%0t press=%b pulse=%b reset=%b)",
                     what, $time, press, pulse, reset);
        end
    endtask

    // Hold every key released and wait for the KEY conditioning chain.
    task automatic settle();
        step(KEY_LAT + 4);
    endtask

    // The switch chain is slower. Waiting only KEY_LAT samples it mid-flight.
    task automatic settle_sw();
        step(SW_LAT + 4);
    endtask

    int k;

    initial begin
        $dumpfile("button_input.vcd");
        $dumpvars(0, button_input_tb);

        for (k = 0; k < LANES; k++) begin
            n_pulse[k] = 0;
            b_pulse[k] = 0;
        end

        KEY = '1;          // ACTIVE LOW: all released
        SW  = 3'b000;      // reset down, level 0

        //---------------------------------------------------------------------
        $display("T1  power-on reset is asserted from cycle zero and then releases");
        // The point of the POR: sw_reset is still x at this moment, and x|1 is
        // 1, so reset is KNOWN even before debounce has resolved anything.
        step(2);
        check(reset === 1'b1,  "reset must be a known 1 during power-on");
        step(POR_COUNTS + 12);
        check(reset === 1'b0,  "reset must release once POR expires and SW0 is down");

        //---------------------------------------------------------------------
        $display("T2  released keys read as not pressed (active low)");
        check(press == '0,       "all keys released -> press is zero");
        check(pulse == '0, "no pulses while nothing is pressed");

        //---------------------------------------------------------------------
        $display("T3  a clean press produces exactly one pulse");
        snap();
        KEY[0] = 1'b0;                       // press
        settle();
        check(press[0] == 1'b1,                 "lane 0 registers as pressed");
        check(n_pulse[0] - b_pulse[0] == 1,     "exactly one pulse for one press");

        //---------------------------------------------------------------------
        $display("T4  a HELD key produces no further pulses (R11)");
        // The half of R11 this module owns. Hold for many debounce windows.
        snap();
        step(KEY_DEBOUNCE * 6);
        check(press[0] == 1'b1,                 "key is still down");
        check(n_pulse[0] - b_pulse[0] == 0,     "holding produces no additional pulse");

        //---------------------------------------------------------------------
        $display("T5  release then press again produces a second pulse");
        KEY[0] = 1'b1;
        settle();
        check(press[0] == 1'b0,                 "release propagates");
        snap();
        KEY[0] = 1'b0;
        settle();
        check(n_pulse[0] - b_pulse[0] == 1,     "a genuine second press is one pulse");
        KEY[0] = 1'b1;
        settle();

        //---------------------------------------------------------------------
        $display("T6  a glitch shorter than the debounce window is rejected");
        // This is the check that fails against a debouncer that passes glitches
        // -- one of the broken variants the markers are said to run.
        snap();
        KEY[1] = 1'b0;
        step(3);                                 // 3 cycles, window needs 9
        KEY[1] = 1'b1;
        settle();
        check(press[1] == 1'b0,                 "glitch must not leave the lane pressed");
        check(n_pulse[1] - b_pulse[1] == 0,     "glitch must produce no pulse");

        //---------------------------------------------------------------------
        $display("T7  lanes are independent");
        snap();
        KEY[2] = 1'b0;
        settle();
        check(press == 4'b0100,                 "only lane 2 is pressed");
        check(n_pulse[2] - b_pulse[2] == 1,     "lane 2 pulsed");
        check(n_pulse[0] - b_pulse[0] == 0,     "lane 0 did not");
        check(n_pulse[1] - b_pulse[1] == 0,     "lane 1 did not");
        check(n_pulse[3] - b_pulse[3] == 0,     "lane 3 did not");
        KEY[2] = 1'b1;
        settle();

        //---------------------------------------------------------------------
        $display("T8  four keys pressed together pulse in the SAME cycle");
        // Downstream consequence: score_counter must SUM per-lane events, not
        // OR-reduce them, because four simultaneous forfeits are four penalties.
        // This bench proves the input path can actually produce that case.
        snap();
        KEY = 4'b0000;
        settle();
        check(press == 4'b1111,                 "all four register as pressed");
        for (k = 0; k < LANES; k++)
            check(n_pulse[k] - b_pulse[k] == 1, $sformatf("lane %0d pulsed exactly once", k));
        check(max_simultaneous == LANES,        "all four pulses landed on one clock edge");
        KEY = '1;
        settle();

        //---------------------------------------------------------------------
        $display("T9  SW0 bounce on RELEASE does not produce a second reset (R6)");
        // beat_gen places beat zero on the cycle reset drops, so a bouncing
        // release would restart the song. Bounce the switch for a few cycles
        // either side of the transition and confirm reset moves once.
        SW[0] = 1'b1;
        settle_sw();
        check(reset == 1'b1,                    "SW0 up asserts reset");

        SW[0] = 1'b0;  step(2);
        SW[0] = 1'b1;  step(2);                 // bounce
        SW[0] = 1'b0;  step(2);
        SW[0] = 1'b1;  step(1);                 // bounce
        SW[0] = 1'b0;                           // settles low
        check(reset == 1'b1,                    "reset must not drop during bounce");
        settle_sw();
        check(reset == 1'b0,                    "reset drops once, after the switch settles");

        //---------------------------------------------------------------------
        $display("T10 level select tracks SW2:1");
        SW[2:1] = 2'b00; settle_sw();
        check(level == 2'd0, "level 0");
        SW[2:1] = 2'b01; settle_sw();
        check(level == 2'd1, "level 1");
        SW[2:1] = 2'b10; settle_sw();
        check(level == 2'd2, "level 2");
        SW[2:1] = 2'b11; settle_sw();
        check(level == 2'd3, "level 3 reads through; level_select clamps it");
        SW[2:1] = 2'b00; settle_sw();

        //---------------------------------------------------------------------
        $display("T11 a key held ACROSS a reset gets no free press");
        // press_q is deliberately not reset. If it were, coming out of reset
        // with a key already down would manufacture an edge and hand the player
        // a note they never pressed for.
        KEY[3] = 1'b0;
        settle();
        snap();
        SW[0] = 1'b1;  settle_sw();             // reset while still holding
        check(reset == 1'b1, "reset asserted");
        SW[0] = 1'b0;  settle_sw();             // release reset, key still down
        check(reset == 1'b0, "reset released");
        check(press[3] == 1'b1,                 "the key is still physically down");
        check(n_pulse[3] - b_pulse[3] == 0,     "no pulse manufactured across reset");
        KEY[3] = 1'b1;
        settle();

        //---------------------------------------------------------------------
        $display("T12 propagation latency is exactly KEY_DEBOUNCE+4 cycles");
        // Two synchroniser flops, prev_button, the counter, the output flop.
        // Pinning the exact number is what catches a BYPASSED SYNCHRONISER:
        // the metastability guard is invisible to functional stimulus, but it
        // is worth exactly two clock cycles of latency.
        begin
            int t0, t1;
            KEY[0] = 1'b1; settle();
            t0 = cyc;
            KEY[0] = 1'b0;
            while (press[0] !== 1'b1) step(1);
            t1 = cyc;
            check(t1 - t0 == KEY_LAT,
                  $sformatf("latency %0d cycles, expected %0d (2 sync + prev + count + out)",
                            t1 - t0, KEY_LAT));
            KEY[0] = 1'b1; settle();
        end

        //---------------------------------------------------------------------
        $display("T13 SW0 is debounced HARDER than a KEY, not merely as hard");
        // A bounce longer than the key window but shorter than the switch
        // window. If SW0 were given the key-grade depth, reset would drop here
        // and the beat grid would re-anchor mid-bounce.
        begin
            SW[0] = 1'b1; settle_sw();
            check(reset == 1'b1, "SW0 up asserts reset");
            SW[0] = 1'b0; step(KEY_LAT + 2);     // a key would have passed this
            check(reset == 1'b1,
                  "reset dropped on a bounce a KEY would pass: SW0 is under-debounced");
            SW[0] = 1'b1; settle_sw();
            check(reset == 1'b1, "reset still asserted after the bounce settles high");
            SW[0] = 1'b0; settle_sw();
            check(reset == 1'b0, "reset releases once SW0 genuinely settles low");
        end

        //---------------------------------------------------------------------
        step(2);
        $display("");
        $display("pulses per lane: %0d %0d %0d %0d   max simultaneous: %0d",
                 n_pulse[0], n_pulse[1], n_pulse[2], n_pulse[3], max_simultaneous);
        if (errors == 0) begin
            $display("button_input_tb: PASS");
            $finish;
        end else begin
            $display("button_input_tb: FAIL (%0d checks failed)", errors);
            $fatal(1, "button_input_tb failed");
        end
    end

    initial begin
        #500000;
        $fatal(1, "button_input_tb: timeout");
    end

endmodule
