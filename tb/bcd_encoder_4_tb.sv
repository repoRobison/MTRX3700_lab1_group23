`timescale 1ns/1ps

module bcd_encoder_4_tb;
    logic        clk = 1'b0;
    logic [10:0] value = '0;
    logic [3:0]  digit0, digit1, digit2, digit3;
    integer      errors = 0;

    bcd_encoder_4 dut (
        .clk(clk), .value(value),
        .digit0(digit0), .digit1(digit1),
        .digit2(digit2), .digit3(digit3)
    );

    /* verilator lint_off BLKSEQ */
    always #5 clk = ~clk;
    /* verilator lint_on BLKSEQ */

    task automatic check_value(
        input logic [10:0] test_value,
        input logic [3:0] expected3,
        input logic [3:0] expected2,
        input logic [3:0] expected1,
        input logic [3:0] expected0
    );
        begin
            value = test_value;
            @(posedge clk);
            #1;
            if ({digit3, digit2, digit1, digit0}
                    !== {expected3, expected2, expected1, expected0}) begin
                errors = errors + 1;
                $display("FAIL: %0d -> %0d%0d%0d%0d, expected %0d%0d%0d%0d",
                         test_value, digit3, digit2, digit1, digit0,
                         expected3, expected2, expected1, expected0);
            end
        end
    endtask

    initial begin
        check_value(11'd0,    4'd0, 4'd0, 4'd0, 4'd0);
        check_value(11'd9,    4'd0, 4'd0, 4'd0, 4'd9);
        check_value(11'd10,   4'd0, 4'd0, 4'd1, 4'd0);
        check_value(11'd42,   4'd0, 4'd0, 4'd4, 4'd2);
        check_value(11'd99,   4'd0, 4'd0, 4'd9, 4'd9);
        check_value(11'd999,  4'd0, 4'd9, 4'd9, 4'd9);
        check_value(11'd2047, 4'd2, 4'd0, 4'd4, 4'd7);

        if (errors == 0) begin
            $display("bcd_encoder_4_tb: PASS");
            $finish;
        end else begin
            $fatal(1, "bcd_encoder_4_tb: FAIL (%0d checks)", errors);
        end
    end

    initial begin
        #1000;
        $fatal(1, "bcd_encoder_4_tb: timeout");
    end
endmodule
