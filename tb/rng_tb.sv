`timescale 1ns/1ps

module rng_tb;
    localparam logic [9:0] SEED = 10'b01011_01000;

    logic clk = 1'b0;
    logic [9:0] random_value;
    logic [9:0] expected;
    integer errors = 0;
    integer cycle;

    rng #(.LFSR_BITS(10), .SEED(SEED)) dut (
        .clk(clk), .random_value(random_value)
    );

    /* verilator lint_off BLKSEQ */
    always #5 clk = ~clk;
    /* verilator lint_on BLKSEQ */

    function automatic logic [9:0] next_value(input logic [9:0] current);
        next_value = {current[8:0], current[9] ^ current[6]};
    endfunction

    initial begin
        expected = SEED;
        #1;
        if (random_value !== expected) begin
            errors = errors + 1;
            $display("FAIL: power-up seed is %b, expected %b", random_value, expected);
        end

        for (cycle = 1; cycle <= 1023; cycle = cycle + 1) begin
            expected = next_value(expected);
            @(posedge clk);
            #1;
            if (random_value !== expected) begin
                errors = errors + 1;
                $display("FAIL: cycle %0d is %b, expected %b",
                         cycle, random_value, expected);
                cycle = 1024;
            end
            if (random_value == 10'b0) begin
                errors = errors + 1;
                $display("FAIL: LFSR entered the all-zero lock-up state");
                cycle = 1024;
            end
        end

        if (errors == 0 && random_value == SEED) begin
            $display("rng_tb: PASS (maximal 1023-state period)");
            $finish;
        end else begin
            $fatal(1, "rng_tb: FAIL (%0d checks, final=%b)", errors, random_value);
        end
    end

    initial begin
        #20000;
        $fatal(1, "rng_tb: timeout");
    end
endmodule
