

`timescale 1ns/1ns

module lane_fsm_tb;

    // ------------------------------------------------------------
    // Signals
    // ------------------------------------------------------------

    logic clk;
    logic reset;

    logic tick;
    logic [10:0] phase_ms;
    logic [10:0] win_ms;

    logic press;

    logic spawn;
    logic [3:0] spawn_value;

    logic [3:0] digit;
    logic active;

    logic hit;
    logic perfect;
    logic miss;
    logic forfeit;


    // ------------------------------------------------------------
    // DUT
    // ------------------------------------------------------------

    lane_fsm #(
        .PERFECT_MS(2)
    ) dut (
        .clk(clk),
        .reset(reset),

        .tick(tick),
        .phase_ms(phase_ms),
        .win_ms(win_ms),

        .press(press),

        .spawn(spawn),
        .spawn_value(spawn_value),

        .digit(digit),
        .active(active),

        .hit(hit),
        .perfect(perfect),
        .miss(miss),
        .forfeit(forfeit)
    );


    // ------------------------------------------------------------
    // Clock
    // ------------------------------------------------------------

    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end


    // ------------------------------------------------------------
    // Helper task: generate a one-clock tick.
    // ------------------------------------------------------------

    task automatic beat;
        begin
            tick = 1'b1;
            #10;
            tick = 1'b0;
            #10;
        end
    endtask


    // ------------------------------------------------------------
    // Helper task: generate a button press.
    // ------------------------------------------------------------

    task automatic button_press;
        begin
            press = 1'b1;
            #10;

            press = 1'b0;
            #10;
        end
    endtask


    // ------------------------------------------------------------
    // Main test
    // ------------------------------------------------------------

    initial begin

        reset = 1'b1;
        tick = 1'b0;
        phase_ms = 11'd0;
        win_ms = 11'd10;

        press = 1'b0;

        spawn = 1'b0;
        spawn_value = 4'd0;


        // --------------------------------------------------------
        // TEST 1: Reset
        // --------------------------------------------------------

        #20;

        reset = 1'b0;

        #10;

        if (active !== 1'b0) begin
            $error("FAIL TEST 1: lane should be inactive after reset.");
        end

        if (digit !== 4'hF) begin
            $error("FAIL TEST 1: inactive digit should be blank.");
        end

        $display("PASS TEST 1: reset");


        // --------------------------------------------------------
        // TEST 2: Spawn a note at 2.
        // --------------------------------------------------------

        spawn_value = 4'd2;
        spawn = 1'b1;

        #10;

        spawn = 1'b0;

        #10;

        if (!active) begin
            $error("FAIL TEST 2: lane should be active after spawn.");
        end

        if (digit !== 4'd2) begin
            $error(
                "FAIL TEST 2: expected digit 2, got %0d",
                digit
            );
        end

        $display("PASS TEST 2: spawn");


        // --------------------------------------------------------
        // TEST 3: Countdown 2 -> 1.
        // --------------------------------------------------------

        beat();

        if (digit !== 4'd1) begin
            $error(
                "FAIL TEST 3: expected digit 1, got %0d",
                digit
            );
        end

        $display("PASS TEST 3: countdown");


        // --------------------------------------------------------
        // TEST 4: Countdown 1 -> WINDOW / 0.
        // --------------------------------------------------------

        beat();

        #1;

        if (digit !== 4'd0) begin
            $error(
                "FAIL TEST 4: expected digit 0, got %0d",
                digit
            );
        end

        if (!active) begin
            $error("FAIL TEST 4: lane should be active in WINDOW.");
        end

        $display("PASS TEST 4: window");


        // --------------------------------------------------------
        // TEST 5: Hit during window.
        // --------------------------------------------------------

        phase_ms = 11'd1;

        button_press();

        #1;

        if (!hit) begin
            $error("FAIL TEST 5: expected hit pulse.");
        end

        if (!perfect) begin
            $error("FAIL TEST 5: expected perfect hit.");
        end

        $display("PASS TEST 5: perfect hit");


        // Wait for resolution to finish.
        beat();


        // --------------------------------------------------------
        // TEST 6: Early press causes FORFEIT.
        // --------------------------------------------------------

        spawn_value = 4'd3;
        spawn = 1'b1;

        #10;

        spawn = 1'b0;

        #10;

        // We are now in COUNT.
        button_press();

        #1;

        if (!forfeit) begin
            $error("FAIL TEST 6: expected forfeit pulse.");
        end

        if (hit) begin
            $error("FAIL TEST 6: early press must not score.");
        end

        $display("PASS TEST 6: early press forfeits note");


        beat();


        // --------------------------------------------------------
        // TEST 7: Miss when hit window expires.
        // --------------------------------------------------------

        spawn_value = 4'd1;
        spawn = 1'b1;

        #10;

        spawn = 1'b0;

        #10;

        // Reach WINDOW.
        beat();

        #1;

        if (digit !== 4'd0) begin
            $error("FAIL TEST 7: expected zero in window.");
        end

        // Move phase beyond the hit window.
        phase_ms = 11'd10;

        #1;

        if (!miss) begin
            $error("FAIL TEST 7: expected miss pulse.");
        end

        if (hit) begin
            $error("FAIL TEST 7: miss must not generate hit.");
        end

        $display("PASS TEST 7: miss");


        // --------------------------------------------------------
        // TEST 8: Held button does not generate repeated hits.
        // --------------------------------------------------------

        beat();

        spawn_value = 4'd1;
        spawn = 1'b1;

        #10;

        spawn = 1'b0;

        #10;

        // Reach window.
        beat();

        #1;

        // Hold the button.
        press = 1'b1;

        #10;

        // First edge should resolve the note.
        if (!hit) begin
            $error("FAIL TEST 8: expected first held press to hit.");
        end

        // Continue holding.
        #100;

        if (hit) begin
            $error("FAIL TEST 8: held button generated repeated hit.");
        end

        press = 1'b0;

        $display("PASS TEST 8: held button does not repeatedly score");


        // --------------------------------------------------------
        // Finished
        // --------------------------------------------------------

        $display("------------------------------------");
        $display("ALL lane_fsm TESTS COMPLETE");
        $display("------------------------------------");

        $finish;

    end

endmodule
