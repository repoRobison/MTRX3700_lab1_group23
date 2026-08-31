`timescale 1ns/1ps

module display_tb;
    logic        clk = 1'b0;
    logic        game_active = 1'b0;
    logic [10:0] value = '0;
    logic [3:0]  lane_active = '0;
    logic [3:0]  countdown0 = '0;
    logic [3:0]  countdown1 = '0;
    logic [3:0]  countdown2 = '0;
    logic [3:0]  countdown3 = '0;
    logic [6:0]  display0, display1, display2, display3, display4, display5;
    integer      errors = 0;

    display dut (
        .clk(clk), .game_active(game_active), .value(value),
        .lane_active(lane_active),
        .countdown0(countdown0), .countdown1(countdown1),
        .countdown2(countdown2), .countdown3(countdown3),
        .display0(display0), .display1(display1),
        .display2(display2), .display3(display3),
        .display4(display4), .display5(display5)
    );

    /* verilator lint_off BLKSEQ */
    always #5 clk = ~clk;
    /* verilator lint_on BLKSEQ */

    function automatic logic [6:0] segments(input logic [3:0] digit);
        case (digit)
            4'd0: segments = 7'b1000000;
            4'd1: segments = 7'b1111001;
            4'd2: segments = 7'b0100100;
            4'd3: segments = 7'b0110000;
            4'd4: segments = 7'b0011001;
            4'd5: segments = 7'b0010010;
            4'd6: segments = 7'b0000010;
            4'd7: segments = 7'b1111000;
            4'd8: segments = 7'b0000000;
            4'd9: segments = 7'b0010000;
            default: segments = 7'b1111111;
        endcase
    endfunction

    task automatic check(input bit condition, input string message);
        if (!condition) begin
            errors = errors + 1;
            $display("FAIL: %s", message);
        end
    endtask

    task automatic clock_score;
        begin
            @(posedge clk);
            #1;
        end
    endtask

    initial begin
        game_active = 1'b1;
        lane_active = 4'b0101;
        countdown0  = 4'd3;
        countdown1  = 4'd6;
        countdown2  = 4'd0;
        countdown3  = 4'd8;
        value       = 11'd42;
        clock_score();

        check(display0 == segments(4'd3), "active lane 0 must display 3");
        check(display1 == segments(4'hf), "inactive lane 1 must be blank");
        check(display2 == segments(4'd0), "active lane 2 must display 0");
        check(display3 == segments(4'hf), "inactive lane 3 must be blank");
        check(display4 == segments(4'd2), "HEX4 must show score units");
        check(display5 == segments(4'd4), "HEX5 must show score tens");

        game_active = 1'b0;
        #1;
        check(display0 == segments(4'hf) && display1 == segments(4'hf)
           && display2 == segments(4'hf) && display3 == segments(4'hf),
              "all lanes must blank outside active play");
        check(display4 == segments(4'd2) && display5 == segments(4'd4),
              "score must remain visible outside active play");

        value = 11'd99;
        clock_score();
        check(display4 == segments(4'd9) && display5 == segments(4'd9),
              "terminal score 99 must display correctly");

        value = 11'd100;
        clock_score();
        check(display4 == segments(4'hf) && display5 == segments(4'hf),
              "values above two digits must not be misleadingly truncated");

        if (errors == 0) begin
            $display("display_tb: PASS");
            $finish;
        end else begin
            $fatal(1, "display_tb: FAIL (%0d checks)", errors);
        end
    end

    initial begin
        #1000;
        $fatal(1, "display_tb: timeout");
    end
endmodule
