`timescale 1ns/1ps

module lane_controller_tb;
    logic       clk = 1'b0;
    logic       reset = 1'b1;
    logic [3:0] due_notes = '0;
    logic [3:0] hit = '0;
    logic [3:0] miss = '0;
    logic [3:0] future_active = '0;
    logic [3:0] future_countdown0 = '0;
    logic [3:0] future_countdown1 = '0;
    logic [3:0] future_countdown2 = '0;
    logic [3:0] future_countdown3 = '0;
    logic [3:0] lane_zero;
    logic [3:0] lane_active;
    logic [3:0] display_countdown0;
    logic [3:0] display_countdown1;
    logic [3:0] display_countdown2;
    logic [3:0] display_countdown3;
    integer     errors = 0;

    lane_controller dut (
        .clk(clk), .reset(reset), .due_notes(due_notes),
        .hit(hit), .miss(miss), .future_active(future_active),
        .future_countdown0(future_countdown0),
        .future_countdown1(future_countdown1),
        .future_countdown2(future_countdown2),
        .future_countdown3(future_countdown3),
        .lane_zero(lane_zero), .lane_active(lane_active),
        .display_countdown0(display_countdown0),
        .display_countdown1(display_countdown1),
        .display_countdown2(display_countdown2),
        .display_countdown3(display_countdown3)
    );

    /* verilator lint_off BLKSEQ */
    always #5 clk = ~clk;
    /* verilator lint_on BLKSEQ */

    task automatic step;
        begin
            @(posedge clk);
            #1;
        end
    endtask

    task automatic check(input bit condition, input string message);
        if (!condition) begin
            errors = errors + 1;
            $display("FAIL: %s", message);
        end
    endtask

    initial begin
        step();
        check(lane_zero == 4'b0000, "reset must clear every zero window");

        reset = 1'b0;
        future_active = 4'b0101;
        future_countdown0 = 4'd3;
        future_countdown2 = 4'd5;
        #1;
        check(lane_active == 4'b0101, "future notes must make their lanes active");
        check(display_countdown0 == 4'd3 && display_countdown2 == 4'd5,
              "future countdown values must reach the display path");

        due_notes = 4'b0001;
        step();
        due_notes = '0;
        check(lane_zero == 4'b0001, "a due note must enter the zero window");
        check(lane_active[0] && display_countdown0 == 4'd0,
              "zero window must override the future countdown with zero");

        hit = 4'b0001;
        step();
        hit = '0;
        check(lane_zero == 4'b0000, "a hit must clear the zero window");
        check(display_countdown0 == 4'd3,
              "cleared lane must return to its nearest future note");

        due_notes = 4'b0010;
        step();
        due_notes = '0;
        check(lane_zero == 4'b0010, "second lane must enter independently");
        miss = 4'b0010;
        step();
        miss = '0;
        check(lane_zero == 4'b0000, "a miss must clear the zero window");

        due_notes = 4'b1100;
        step();
        due_notes = '0;
        check(lane_zero == 4'b1100,
              "simultaneous hard-mode due notes must remain independent");

        reset = 1'b1;
        step();
        check(lane_zero == 4'b0000, "reset must clear active notes after play");

        if (errors == 0) begin
            $display("lane_controller_tb: PASS");
            $finish;
        end else begin
            $fatal(1, "lane_controller_tb: FAIL (%0d checks)", errors);
        end
    end

    initial begin
        #1000;
        $fatal(1, "lane_controller_tb: timeout");
    end
endmodule
