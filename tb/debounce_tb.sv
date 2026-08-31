`timescale 1ns/1ps

module debounce_tb;
    localparam int DELAY_COUNTS = 4;
    localparam int SETTLE_CYCLES = DELAY_COUNTS + 5;

    logic clk = 1'b0;
    logic button = 1'b0;
    logic button_pressed;
    integer errors = 0;

    debounce #(.DELAY_COUNTS(DELAY_COUNTS)) dut (
        .clk(clk), .button(button), .button_pressed(button_pressed)
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
            $display("FAIL: %s", message);
        end
    endtask

    initial begin
        step(SETTLE_CYCLES);
        check(button_pressed === 1'b0, "initial low input must settle low");

        button = 1'b1;
        step(2);
        button = 1'b0;
        step(SETTLE_CYCLES);
        check(button_pressed === 1'b0, "short high glitch must be rejected");

        button = 1'b1;
        step(SETTLE_CYCLES);
        check(button_pressed === 1'b1, "stable high input must be accepted");

        button = 1'b0;
        step(SETTLE_CYCLES);
        check(button_pressed === 1'b0, "stable low input must be accepted");

        if (errors == 0) begin
            $display("debounce_tb: PASS");
            $finish;
        end else begin
            $fatal(1, "debounce_tb: FAIL (%0d checks)", errors);
        end
    end

    initial begin
        #2000;
        $fatal(1, "debounce_tb: timeout");
    end
endmodule
