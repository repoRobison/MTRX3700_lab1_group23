//=============================================================================
// bcd_encoder_4.sv -- four-digit binary-to-BCD lookup ROM
//
// Completed from the Reaction Time Game lesson scaffold.  The interface and
// clocked ROM architecture are retained so the module remains recognisably the
// supplied design while serving the Piano Tiles score display.
//=============================================================================
`timescale 1ns/1ps

module bcd_encoder_4 (
    input             clk,
    input      [10:0] value,
    output reg [3:0]  digit0,
    output reg [3:0]  digit1,
    output reg [3:0]  digit2,
    output reg [3:0]  digit3
);

    // Four 2048 x 4-bit synchronous lookup ROMs, one per decimal digit.
    reg [3:0] bcd_lookup_digit0 [0:2047];
    reg [3:0] bcd_lookup_digit1 [0:2047];
    reg [3:0] bcd_lookup_digit2 [0:2047];
    reg [3:0] bcd_lookup_digit3 [0:2047];

    integer i;
    initial begin : bin_to_bcd_rom_init
        for (i = 0; i < 2048; i = i + 1) begin
            bcd_lookup_digit0[i] = 4'(i % 10);
            bcd_lookup_digit1[i] = 4'((i / 10) % 10);
            bcd_lookup_digit2[i] = 4'((i / 100) % 10);
            bcd_lookup_digit3[i] = 4'((i / 1000) % 10);
        end
    end

    // Synchronous ROM read: outputs update one clock after value is presented.
    always @(posedge clk) begin
        digit0 <= bcd_lookup_digit0[value];
        digit1 <= bcd_lookup_digit1[value];
        digit2 <= bcd_lookup_digit2[value];
        digit3 <= bcd_lookup_digit3[value];
    end

endmodule
