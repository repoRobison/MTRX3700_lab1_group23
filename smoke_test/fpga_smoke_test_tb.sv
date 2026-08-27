`timescale 1ns/1ps

module fpga_smoke_test_tb;

    localparam integer SIM_CLKS_PER_MS           = 2;
    localparam integer SIM_STEP_MS               = 20;
    localparam integer SIM_DEBOUNCE_COUNTS       = 2;
    localparam integer SIM_FLASH_CYCLES          = 7;
    localparam integer SIM_HEARTBEAT_HALF_CYCLES = 9;

    reg CLOCK_50;
    reg [0:0] SW;
    reg [3:0] KEY;
    wire [6:0] HEX0;
    wire [6:0] HEX1;
    wire [6:0] HEX2;
    wire [6:0] HEX3;
    wire [6:0] HEX4;
    wire [6:0] HEX5;
    wire [6:0] LEDR;

    integer errors;
    integer hit_number;
    integer expected_score;
    integer lane_under_test;

    fpga_smoke_test #(
        .CLKS_PER_MS           (SIM_CLKS_PER_MS),
        .STEP_MS               (SIM_STEP_MS),
        .KEY_DEBOUNCE_COUNTS   (SIM_DEBOUNCE_COUNTS),
        .FLASH_CYCLES          (SIM_FLASH_CYCLES),
        .HEARTBEAT_HALF_CYCLES (SIM_HEARTBEAT_HALF_CYCLES)
    ) dut (
        .CLOCK_50(CLOCK_50),
        .SW      (SW),
        .KEY     (KEY),
        .HEX0    (HEX0),
        .HEX1    (HEX1),
        .HEX2    (HEX2),
        .HEX3    (HEX3),
        .HEX4    (HEX4),
        .HEX5    (HEX5),
        .LEDR    (LEDR)
    );

    initial begin
        CLOCK_50 = 1'b0;
        forever #10 CLOCK_50 = ~CLOCK_50;
    end

    function automatic [6:0] segments_for_digit(input integer digit);
        begin
            case (digit)
                0: segments_for_digit = 7'b100_0000;
                1: segments_for_digit = 7'b111_1001;
                2: segments_for_digit = 7'b010_0100;
                3: segments_for_digit = 7'b011_0000;
                4: segments_for_digit = 7'b001_1001;
                5: segments_for_digit = 7'b001_0010;
                6: segments_for_digit = 7'b000_0010;
                7: segments_for_digit = 7'b111_1000;
                8: segments_for_digit = 7'b000_0000;
                9: segments_for_digit = 7'b001_0000;
                default: segments_for_digit = 7'b111_1111;
            endcase
        end
    endfunction

    task automatic fail(input string message);
        begin
            $display("FAIL: %s", message);
            errors = errors + 1;
        end
    endtask

    task automatic check_score(input integer expected);
        begin
            #1;
            if (dut.score_tens !== (expected / 10))
                fail($sformatf("score tens expected %0d, got %0d",
                               expected / 10, dut.score_tens));
            if (dut.score_ones !== (expected % 10))
                fail($sformatf("score ones expected %0d, got %0d",
                               expected % 10, dut.score_ones));
            if (HEX5 !== segments_for_digit(expected / 10))
                fail($sformatf("HEX5 tens mismatch for score %0d", expected));
            if (HEX4 !== segments_for_digit(expected % 10))
                fail($sformatf("HEX4 ones mismatch for score %0d", expected));
        end
    endtask

    task automatic check_lane_displays(
        input integer expected_lane,
        input integer expected_count
    );
        reg [6:0] expected_digit;
        begin
            #1;
            expected_digit = segments_for_digit(expected_count);
            if (dut.active_lane !== expected_lane[1:0])
                fail($sformatf("lane expected %0d, got %0d",
                               expected_lane, dut.active_lane));
            if (dut.countdown !== expected_count[1:0])
                fail($sformatf("count expected %0d, got %0d",
                               expected_count, dut.countdown));
            if (HEX0 !== ((expected_lane == 0) ? expected_digit : 7'b111_1111))
                fail($sformatf("HEX0 active/blank mismatch at lane %0d count %0d",
                               expected_lane, expected_count));
            if (HEX1 !== ((expected_lane == 1) ? expected_digit : 7'b111_1111))
                fail($sformatf("HEX1 active/blank mismatch at lane %0d count %0d",
                               expected_lane, expected_count));
            if (HEX2 !== ((expected_lane == 2) ? expected_digit : 7'b111_1111))
                fail($sformatf("HEX2 active/blank mismatch at lane %0d count %0d",
                               expected_lane, expected_count));
            if (HEX3 !== ((expected_lane == 3) ? expected_digit : 7'b111_1111))
                fail($sformatf("HEX3 active/blank mismatch at lane %0d count %0d",
                               expected_lane, expected_count));
        end
    endtask

    task automatic wait_for_state(input integer lane, input integer count);
        integer timeout;
        begin
            timeout = 0;
            while (((dut.active_lane !== lane[1:0]) ||
                    (dut.countdown !== count[1:0])) && (timeout < 200)) begin
                @(posedge CLOCK_50);
                timeout = timeout + 1;
            end
            if (timeout >= 200)
                fail($sformatf("timeout waiting for lane %0d count %0d", lane, count));
            check_lane_displays(lane, count);
        end
    endtask

    task automatic wait_for_key_level(input integer key_number, input bit level);
        integer timeout;
        begin
            timeout = 0;
            while ((dut.key_level[key_number] !== level) && (timeout < 40)) begin
                @(posedge CLOCK_50);
                timeout = timeout + 1;
            end
            if (timeout >= 40)
                fail($sformatf("key %0d debounce timeout waiting for level %0d",
                               key_number, level));
        end
    endtask

    task automatic press_and_release(input integer key_number);
        integer timeout;
        begin
            KEY[key_number] = 1'b0;
            timeout = 0;
            while ((dut.press_pulse[key_number] !== 1'b1) && (timeout < 40)) begin
                @(posedge CLOCK_50);
                timeout = timeout + 1;
            end
            if (timeout >= 40)
                fail($sformatf("key %0d did not create a press pulse", key_number));
            @(posedge CLOCK_50);
            #1;
            KEY[key_number] = 1'b1;
            wait_for_key_level(key_number, 1'b0);
        end
    endtask

    task automatic check_flash_duration(input integer led_number);
        integer cycle;
        begin
            #1;
            if (LEDR[led_number] !== 1'b1)
                fail($sformatf("LEDR%0d did not assert after hit", led_number));
            for (cycle = 1; cycle < SIM_FLASH_CYCLES; cycle = cycle + 1) begin
                @(posedge CLOCK_50);
                #1;
                if (LEDR[led_number] !== 1'b1)
                    fail($sformatf("LEDR%0d pulse ended early at cycle %0d",
                                   led_number, cycle));
            end
            @(posedge CLOCK_50);
            #1;
            if (LEDR[led_number] !== 1'b0)
                fail($sformatf("LEDR%0d pulse exceeded %0d cycles",
                               led_number, SIM_FLASH_CYCLES));
        end
    endtask

    initial begin
        errors = 0;
        SW = 1'b1;
        KEY = 4'b1111;

        // Allow the reset synchroniser and key debouncers to settle.
        repeat (12) @(posedge CLOCK_50);
        #1;
        check_lane_displays(0, 3);
        check_score(0);
        if (LEDR[6:1] !== 6'b000000)
            fail("hit LEDs were not clear during reset");
        $display("PASS: reset and score display");

        SW[0] = 1'b0;
        while (dut.reset !== 1'b0)
            @(posedge CLOCK_50);

        // Verify lane 0's complete countdown and blank all inactive HEXes.
        wait_for_state(0, 3);
        wait_for_state(0, 2);
        wait_for_state(0, 1);
        wait_for_state(0, 0);
        $display("PASS: lane 0 countdown and inactive-display blanking");

        // KEY1 is wrong while lane 0 is active; it must not score or flash.
        press_and_release(1);
        check_score(0);
        if (LEDR[4] !== 1'b0)
            fail("incorrect KEY1 press flashed LEDR4");
        $display("PASS: incorrect key rejected");

        // Press and continue holding matching KEY0. It may score only once.
        KEY[0] = 1'b0;
        while (dut.press_pulse[0] !== 1'b1) begin
            @(posedge CLOCK_50);
            #1;
        end
        @(posedge CLOCK_50);
        #1;
        check_score(1);
        check_flash_duration(3);
        $display("PASS: correct key scored and LED pulse duration matched");

        // Continue holding KEY0 through every other lane and back to lane 0.
        // This simultaneously checks deterministic order and held-key behavior.
        wait_for_state(1, 3);
        wait_for_state(1, 2);
        wait_for_state(1, 1);
        wait_for_state(1, 0);
        wait_for_state(2, 3);
        wait_for_state(2, 2);
        wait_for_state(2, 1);
        wait_for_state(2, 0);
        wait_for_state(3, 3);
        wait_for_state(3, 2);
        wait_for_state(3, 1);
        wait_for_state(3, 0);
        wait_for_state(0, 3);
        wait_for_state(0, 2);
        wait_for_state(0, 1);
        wait_for_state(0, 0);
        check_score(1);
        $display("PASS: lanes cycle 0-1-2-3 and held key does not repeat");

        // Release and press KEY0 again to prove a new physical press scores.
        KEY[0] = 1'b1;
        wait_for_key_level(0, 1'b0);
        press_and_release(0);
        check_score(2);
        $display("PASS: released/re-pressed matching key updates score");

        // Assert reset again and verify state, score, and flashes clear.
        SW[0] = 1'b1;
        while (dut.reset !== 1'b1)
            @(posedge CLOCK_50);
        repeat (2) @(posedge CLOCK_50);
        check_lane_displays(0, 3);
        check_score(0);
        if (LEDR[6:1] !== 6'b000000)
            fail("reset did not clear hit LEDs");
        $display("PASS: second reset clears state");

        // Exercise every BCD carry and prove that valid hits saturate at 99.
        SW[0] = 1'b0;
        while (dut.reset !== 1'b0)
            @(posedge CLOCK_50);
        for (hit_number = 1; hit_number <= 101; hit_number = hit_number + 1) begin
            while (dut.countdown !== 2'd0)
                @(posedge CLOCK_50);
            lane_under_test = dut.active_lane;
            press_and_release(lane_under_test);
            expected_score = (hit_number < 99) ? hit_number : 99;
            check_score(expected_score);
            while (dut.countdown === 2'd0)
                @(posedge CLOCK_50);
        end
        $display("PASS: score carries through 09/10 and saturates at 99");

        if (errors == 0) begin
            $display("ALL FPGA SMOKE TEST CHECKS PASSED");
            $finish;
        end else begin
            $fatal(1, "FPGA smoke test failed with %0d error(s)", errors);
        end
    end

endmodule
