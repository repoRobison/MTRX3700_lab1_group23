`timescale 1ns/1ns /* This directive (`) specifies simulation <time unit>/<time precision>. */

module timer #(
    parameter MAX_MS = 2047,            // Maximum millisecond value
    parameter CLKS_PER_MS = 50000 // What is the number of clock cycles in a millisecond? 50000 (50MHz)
) (
    input                       clk,
    input                       reset,
    input                       up,
    input  [$clog2(MAX_MS)-1:0] start_value, // What does the $clog2() function do here?
    input                       enable,
    output [$clog2(MAX_MS)-1:0] timer_value
);
     // Prescaler: counts raw clock cycles, 0 .. CLKS_PER_MS-1 (49999) -> 16 bits.
    reg [$clog2(CLKS_PER_MS)-1:0] clk_count;
    // The actual timer, in milliseconds, 0 .. MAX_MS (2047) -> 11 bits.
    reg [$clog2(MAX_MS)-1:0]      ms_count;
    // Mode register: sampled from `up` at reset, held until the next reset.
    reg                           count_up;

    always @(posedge clk) begin
        // Priority chain mirrors the spec: reset outranks enable, and `up` /
        // `start_value` are only consulted while reset is high.
        if (reset) begin
            clk_count <= 0;
            if (up) begin
                ms_count <= 0;          // count upwards from zero
                count_up <= 1'b1;
            end else begin
                ms_count <= start_value; // count downwards from start_value
                count_up <= 1'b0;
            end
        end
        else if (enable) begin
            if (clk_count >= CLKS_PER_MS - 1) begin
                // One millisecond has elapsed: restart the prescaler and tick.
                clk_count <= 0;
                if (count_up) ms_count <= ms_count + 1;
                else          ms_count <= ms_count - 1;
            end else begin
                clk_count <= clk_count + 1;
            end
        end
        // No final else: with reset and enable both low every register holds,
        // which is the "pause" behaviour. In a CLOCKED block this synthesises
        // to a flip-flop with a clock enable, not an inferred latch.
    end

    assign timer_value = ms_count;

    // Your code here!

endmodule
