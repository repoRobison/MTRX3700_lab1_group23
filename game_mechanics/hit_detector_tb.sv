`timescale 1ns/1ps
`include "game_params.svh"

module hit_detector_tb;
    localparam int CPMS     = 2;
    localparam int FLASH_MS = 200;
    localparam int BLINK_MS = 20;

    logic clk = 1'b0;
    logic reset = 1'b0;
    logic [3:0] press_pulse = 4'b0;
    logic [3:0] lane_zero = 4'b0;
    logic [3:0] lane_active = 4'b0;
    logic [`GP_MS_W-1:0] phase_ms = '0;
    logic [`GP_MS_W-1:0] win_ms = 11'd200;
    logic [`GP_MS_W-1:0] perfect_ms = 11'd50;
    wire [3:0] normal_hit, perfect_hit, miss, forfeit, stray, led_pulse;

    integer errors = 0;
    integer transitions;
    logic previous_led;
    logic saw_on, saw_off;

    hit_detector #(
        .CLKS_PER_MS(CPMS),
        .FLASH_MS(FLASH_MS),
        .PERFECT_BLINK_MS(BLINK_MS)
    ) dut (
        .clk(clk), .reset(reset), .press_pulse(press_pulse),
        .lane_zero(lane_zero), .lane_active(lane_active),
        .phase_ms(phase_ms), .win_ms(win_ms), .perfect_ms(perfect_ms),
        .normal_hit(normal_hit), .perfect_hit(perfect_hit), .miss(miss),
        .forfeit(forfeit), .stray(stray), .led_pulse(led_pulse)
    );

    always #5 clk = ~clk;

    task automatic check(input bit condition, input string what);
        if (!condition) begin
            errors = errors + 1;
            $display("  FAIL: %s (t=%0t phase=%0d normal=%b perfect=%b led=%b)",
                     what, $time, phase_ms, normal_hit, perfect_hit, led_pulse);
        end
    endtask

    task automatic reset_dut;
        begin
            @(negedge clk);
            reset = 1'b1;
            press_pulse = 4'b0;
            lane_zero = 4'b0;
            lane_active = 4'b0;
            repeat (2) @(posedge clk);
            @(negedge clk);
            reset = 1'b0;
        end
    endtask

    task automatic press_lane0(input integer phase,
                               input bit expect_perfect);
        begin
            @(negedge clk);
            phase_ms = phase;
            lane_zero = 4'b0001;
            lane_active = 4'b0001;
            press_pulse = 4'b0001;
            #1;
            check(perfect_hit[0] == expect_perfect,
                  "wrong perfect classification");
            check(normal_hit[0] == !expect_perfect,
                  "wrong normal classification");
            check(!(perfect_hit[0] && normal_hit[0]),
                  "normal and perfect asserted together");
            @(posedge clk);
            #1;
            press_pulse = 4'b0000;
        end
    endtask

    integer cycle;
    initial begin
        $display("T1 perfect window occupies the leading edge");
        reset_dut();
        press_lane0(49, 1'b1);
        reset_dut();
        press_lane0(50, 1'b0);

        $display("T2 normal hit remains one solid LED flash");
        reset_dut();
        press_lane0(100, 1'b0);
        for (cycle = 0; cycle < 100 * CPMS; cycle = cycle + 1) begin
            @(posedge clk); #1;
            check(led_pulse[0] == 1'b1,
                  "normal-hit LED blinked during its solid interval");
        end

        $display("T3 perfect hit rapidly flashes the same lane LED");
        reset_dut();
        press_lane0(10, 1'b1);
        transitions = 0;
        previous_led = led_pulse[0];
        saw_on = previous_led;
        saw_off = !previous_led;
        for (cycle = 0; cycle < FLASH_MS * CPMS + 10;
             cycle = cycle + 1) begin
            @(posedge clk); #1;
            if (led_pulse[0] != previous_led) transitions = transitions + 1;
            previous_led = led_pulse[0];
            if (led_pulse[0]) saw_on = 1'b1;
            else              saw_off = 1'b1;
        end
        check(saw_on && saw_off,
              "perfect-hit indication did not contain both on and off phases");
        check(transitions >= 6,
              "perfect-hit indication did not flash rapidly enough");
        check(led_pulse[0] == 1'b0,
              "perfect-hit indication did not finish after FLASH_MS");

        if (errors == 0) begin
            $display("hit_detector_tb: PASS");
            $finish;
        end else begin
            $display("hit_detector_tb: FAIL (%0d errors)", errors);
            $fatal(1, "hit_detector_tb failed");
        end
    end

    initial begin
        #100000;
        $fatal(1, "hit_detector_tb: timeout");
    end
endmodule
