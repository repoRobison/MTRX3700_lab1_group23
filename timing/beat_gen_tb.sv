`timescale 1ns/1ns

module beat_gen_tb;

    // ------------------------------------------------------------
    // Simulation parameters
    // ------------------------------------------------------------

    localparam integer SIM_CLKS_PER_MS = 2;
    localparam integer SIM_TICK_MS     = 5;


    // ------------------------------------------------------------
    // Signals
    // ------------------------------------------------------------

    logic clk;
    logic reset;

    logic [10:0] tick_ms;

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
        .tick_ms(tick_ms),
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
        tick_ms = 11'(SIM_TICK_MS);

        tick_count = 0;
        cycle_count = 0;
        errors = 0;
        last_tick_cycle = -1;
        previous_tick = 1'b0;

        // Hold reset for two clock cycles.
        repeat (2) @(posedge clk);

        reset = 1'b0;


        // --------------------------------------------------------
        // Observe several beats.
        // --------------------------------------------------------

        repeat (40) begin

            @(posedge clk);

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

                // phase_ms holds its MAXIMUM on the tick cycle -- the phase
                // timer's reset is driven by tick, so zero arrives on the NEXT
                // edge. The old check asserted the opposite and failed a
                // correct DUT. Measured: phase_ms == tick_ms here.
                if (phase_ms !== tick_ms) begin
                    $display("FAIL: phase_ms should equal tick_ms at the tick, got %0d",
                             phase_ms);
                    errors = errors + 1;
                end

                // Interval check. The correct period is
                //     tick_ms * CLKS_PER_MS + 1
                // the extra cycle being the reload. This is the check that
                // would have caught the timer prescaler defect.
                if (last_tick_cycle >= 0) begin
                    if ((cycle_count - last_tick_cycle)
                        !== (SIM_TICK_MS * SIM_CLKS_PER_MS + 1)) begin
                        $display("FAIL: tick period %0d, expected %0d",
                                 cycle_count - last_tick_cycle,
                                 SIM_TICK_MS * SIM_CLKS_PER_MS + 1);
                        errors = errors + 1;
                    end
                end
                last_tick_cycle = cycle_count;

            end

        end


        // We should have seen multiple beats.
        if (tick_count < 3) begin
            $display("FAIL: expected at least 3 ticks, got %0d", tick_count);
            errors = errors + 1;
        end
        else begin
            $display("phase_ms zeroes one cycle after the tick, as designed.");
            $display("tick period is tick_ms*CLKS_PER_MS+1 = %0d cycles.",
                     SIM_TICK_MS * SIM_CLKS_PER_MS + 1);
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
        #100000;
        $fatal(1, "beat_gen_tb: timeout");
    end

endmodule
