module seven_seg (
    input      [3:0]  bcd,
    output reg [6:0]  segments // Must be reg to set in always block!!
);

    // Your `always @(*)` block and case block here!
        always @(*) begin
        case (bcd)
            4'd0:    segments = 7'b1000000;  // a b c d e f
            4'd1:    segments = 7'b1111001;  //   b c
            4'd2:    segments = 7'b0100100;  // a b   d e   g
            4'd3:    segments = 7'b0110000;  // a b c d     g
            4'd4:    segments = 7'b0011001;  //   b c     f g
            4'd5:    segments = 7'b0010010;  // a   c d   f g
            4'd6:    segments = 7'b0000010;  // a   c d e f g
            4'd7:    segments = 7'b1111000;  // a b c
            4'd8:    segments = 7'b0000000;  // a b c d e f g
            4'd9:    segments = 7'b0010000;  // a b c d   f g
            // bcd > 9 is not a decimal digit -> blank the display.
            // This default is also what stops a latch being inferred.
            default: segments = 7'b1111111;
        endcase
    end


endmodule
