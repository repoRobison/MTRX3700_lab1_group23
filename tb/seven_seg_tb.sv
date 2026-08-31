`timescale 1ns/1ps

module seven_seg_tb;
    logic [3:0] bcd;
    logic [6:0] segments;
    integer errors = 0;
    integer digit;

    seven_seg dut (.bcd(bcd), .segments(segments));

    function automatic logic [6:0] expected(input logic [3:0] value);
        case (value)
            4'd0: expected = 7'b1000000;
            4'd1: expected = 7'b1111001;
            4'd2: expected = 7'b0100100;
            4'd3: expected = 7'b0110000;
            4'd4: expected = 7'b0011001;
            4'd5: expected = 7'b0010010;
            4'd6: expected = 7'b0000010;
            4'd7: expected = 7'b1111000;
            4'd8: expected = 7'b0000000;
            4'd9: expected = 7'b0010000;
            default: expected = 7'b1111111;
        endcase
    endfunction

    initial begin
        for (digit = 0; digit < 16; digit = digit + 1) begin
            bcd = 4'(digit);
            #1;
            if (segments !== expected(4'(digit))) begin
                errors = errors + 1;
                $display("FAIL: digit %0d produced %b", digit, segments);
            end
        end

        if (errors == 0) begin
            $display("seven_seg_tb: PASS");
            $finish;
        end else begin
            $fatal(1, "seven_seg_tb: FAIL (%0d checks)", errors);
        end
    end
endmodule
