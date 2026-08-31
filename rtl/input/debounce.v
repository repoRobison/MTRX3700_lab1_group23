module debounce #(
  parameter DELAY_COUNTS = 2500 // 50us with clk period 20ns totals in 2500 counts
) (
    input clk, button,
    output reg button_pressed
);

  wire button_sync;
  synchroniser button_synchroniser (.clk(clk), .x(button), .y(button_sync));
// prev_button's mux is a no_op - equal inputs, holding & assigning give the same value. This allows the three blocks become one with identicl latencies on both edges under the same test bench. This holds because non-blocking assignment means count's condition reads the old prev_button. 29 lines -> 8 lines.  
  reg prev_button;
  reg [$clog2(DELAY_COUNTS+1)-1:0] count;   // == [11:0] for the default

  always @(posedge clk) begin
    prev_button <= button_sync;                       // the mux was redundant
    if (button_sync != prev_button)  count <= 0;      // edge -> restart the timer
    else if (count != DELAY_COUNTS)  count <= count + 1;
    else                             button_pressed <= prev_button;
end

endmodule


