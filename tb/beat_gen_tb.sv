`timescale 1ns/1ns

module beat_gen_tb;

    // ------------------------------------------------------------
    // Simulation parameters
    // ------------------------------------------------------------

    localparam integer SIM_CLKS_PER_MS = 2;
    localparam integer SIM_BPM         = 83;
    localparam integer MINUTE_CLKS     = 60000 * SIM_CLKS_PER_MS;
    localparam integer SHORT_INTERVAL  = MINUTE_CLKS / SIM_BPM;


    // ------------------------------------------------------------
    // Signals
    // ------------------------------------------------------------

    logic clk;
    logic reset;

    logic [7:0] bpm;

    logic tick;
    logic [10:0] phase_ms;


    // ------------------------------------------------------------
    // DUT
    // ------------------------------------------------------------

    beat_gen #(
        .CLKS_PER_MS(SIM_CLKS_PER_MS)
    ) dut (
        .clk(clk),
        .reset(reset),
        .bpm(bpm),
        .tick(tick),
        .phase_ms(phase_ms)
    );


    // ------------------------------------------------------------
    // Clock
    // 10 ns period = 100 MHz simulation clock.
    // The actual frequency doesn't matter because we override
    // CLKS_PER_MS.
    // ------------------------------------------------------------

    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end


    // ------------------------------------------------------------
    // Test
    // ------------------------------------------------------------

    integer tick_count;
    integer cycle_count;
    integer errors;
    integer last_tick_cycle;

    logic previous_tick;


    initial begin

        reset = 1'b1;
        bpm = 8'(SIM_BPM);

        tick_count = 0;
        cycle_count = 0;
        errors = 0;
        last_tick_cycle = -1;
        previous_tick = 1'b0;

        // Hold reset for two clock cycles.
        repeat (2) @(posedge clk);

        @(negedge clk);
        reset = 1'b0;


        // --------------------------------------------------------
        // Observe several beats.
        // --------------------------------------------------------

        // Two exact simulated minutes prove both the tick count and the
        // alternating whole-clock intervals used for fractional periods.
        repeat (2 * MINUTE_CLKS) begin

            @(posedge clk);
            // Sample after the DUT's non-blocking assignments settle. Without
            // this delta-cycle delay, the final tick at the two-minute boundary
            // is observed as the previous cycle's value in event-driven sims.
            #1;

            cycle_count = cycle_count + 1;

            // Check tick is never high for two consecutive cycles.
            if (tick && previous_tick) begin
                $display("FAIL: tick stayed high for more than one cycle.");
                errors = errors + 1;
            end

            previous_tick = tick;

            if (tick) begin

                tick_count = tick_count + 1;

                $display(
                    "Beat %0d at cycle %0d, phase_ms=%0d",
                    tick_count,
                    cycle_count,
                    phase_ms
                );

                // A fractional divider may use either adjacent whole-clock
                // interval; no other interval is permitted.
                if (last_tick_cycle >= 0) begin
                    if (((cycle_count - last_tick_cycle) != SHORT_INTERVAL)
                        && ((cycle_count - last_tick_cycle)
                            != (SHORT_INTERVAL + 1))) begin
                        $display("FAIL: tick period %0d, expected %0d or %0d",
                                 cycle_count - last_tick_cycle,
                                 SHORT_INTERVAL, SHORT_INTERVAL + 1);
                        errors = errors + 1;
                    end
                end
                last_tick_cycle = cycle_count;

            end

        end


        // Exact average BPM: two minutes must contain exactly 2*BPM pulses.
        if (tick_count != (2 * SIM_BPM)) begin
            $display("FAIL: expected %0d ticks in two minutes, got %0d",
                     2 * SIM_BPM, tick_count);
            errors = errors + 1;
        end
        else begin
            $display("%0d BPM exact over two simulated minutes.", SIM_BPM);
            $display("tick intervals are %0d or %0d clocks.",
                     SHORT_INTERVAL, SHORT_INTERVAL + 1);
        end

        if (errors == 0) begin
            $display("beat_gen_tb: PASS (%0d ticks)", tick_count);
            $finish;
        end
        else begin
            $display("beat_gen_tb: FAIL (%0d checks failed)", errors);
            $fatal(1, "beat_gen_tb failed");
        end

    end

    // Watchdog: a hang must FAIL the suite, not stall it.
    initial begin
        #5000000;
        $fatal(1, "beat_gen_tb: timeout");
    end

endmodule
