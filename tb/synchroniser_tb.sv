`timescale 1ns/1ps

module synchroniser_tb;
    logic clk = 1'b0;
    logic x = 1'b0;
    logic y;
    integer errors = 0;

    synchroniser dut (.clk(clk), .x(x), .y(y));

    /* verilator lint_off BLKSEQ */
    always #5 clk = ~clk;
    /* verilator lint_on BLKSEQ */

    task automatic check(input bit condition, input string message);
        if (!condition) begin
            errors = errors + 1;
            $display("FAIL: %s", message);
        end
    endtask

    initial begin
        repeat (3) @(posedge clk);
        #1;
        check(y === 1'b0, "settled low input must produce low output");

        @(negedge clk);
        x = 1'b1;
        @(posedge clk);
        #1;
        check(y === 1'b0, "input must not bypass the second flip-flop");
        @(posedge clk);
        #1;
        check(y === 1'b1, "high must appear after two sampling edges");

        @(negedge clk);
        x = 1'b0;
        @(posedge clk);
        #1;
        check(y === 1'b1, "falling input must not bypass the synchroniser");
        @(posedge clk);
        #1;
        check(y === 1'b0, "low must appear after two sampling edges");

        if (errors == 0) begin
            $display("synchroniser_tb: PASS");
            $finish;
        end else begin
            $fatal(1, "synchroniser_tb: FAIL (%0d checks)", errors);
        end
    end

    initial begin
        #500;
        $fatal(1, "synchroniser_tb: timeout");
    end
endmodule
