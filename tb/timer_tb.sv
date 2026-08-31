`timescale 1ns/1ps

module timer_tb;
    localparam int MAX_MS = 16;
    localparam int CLKS_PER_MS = 3;

    logic clk = 1'b0;
    logic reset = 1'b1;
    logic up = 1'b1;
    logic [$clog2(MAX_MS)-1:0] start_value = '0;
    logic enable = 1'b0;
    logic [$clog2(MAX_MS)-1:0] timer_value;
    integer errors = 0;

    timer #(.MAX_MS(MAX_MS), .CLKS_PER_MS(CLKS_PER_MS)) dut (
        .clk(clk), .reset(reset), .up(up), .start_value(start_value),
        .enable(enable), .timer_value(timer_value)
    );

    /* verilator lint_off BLKSEQ */
    always #5 clk = ~clk;
    /* verilator lint_on BLKSEQ */

    task automatic step(input integer cycles);
        repeat (cycles) @(posedge clk);
        #1;
    endtask

    task automatic check(input bit condition, input string message);
        if (!condition) begin
            errors = errors + 1;
            $display("FAIL: %s (timer=%0d)", message, timer_value);
        end
    endtask

    initial begin
        step(2);
        check(timer_value == 0, "up reset must load zero");
        reset = 1'b0;
        enable = 1'b1;
        step(CLKS_PER_MS);
        check(timer_value == 1, "prescaler must produce one millisecond tick");
        step(2 * CLKS_PER_MS);
        check(timer_value == 3, "up timer must continue at millisecond rate");

        enable = 1'b0;
        step(2 * CLKS_PER_MS);
        check(timer_value == 3, "disable must pause both timer and prescaler");

        reset = 1'b1;
        up = 1'b0;
        start_value = 4'd5;
        step(1);
        check(timer_value == 5, "down reset must load start_value");
        reset = 1'b0;
        enable = 1'b1;
        step(CLKS_PER_MS);
        check(timer_value == 4, "down timer must decrement after one millisecond");

        if (errors == 0) begin
            $display("timer_tb: PASS");
            $finish;
        end else begin
            $fatal(1, "timer_tb: FAIL (%0d checks)", errors);
        end
    end

    initial begin
        #2000;
        $fatal(1, "timer_tb: timeout");
    end
endmodule
