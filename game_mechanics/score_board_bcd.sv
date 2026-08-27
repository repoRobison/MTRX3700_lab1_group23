//=============================================================================
// score_bcd.sv -- split the binary score into two decimal digits for HEX5:4
//
// WHY THIS EXISTS
//   score.sv holds a 7-bit BINARY value, 0..99. HEX5:4 need two DECIMAL digits.
//   The README assigns HEX5:4 to Task 4 but no file claimed the conversion, so
//   it fell between the tasks. It is here rather than inside score.sv because
//   score.sv is verified and its bench asserts on the binary value.
//
// WHY DIVISION IS FINE HERE, WHEN game_params.svh WARNS ABOUT MODULO
//   That warning is about `rnd % SPAWN_RANGE` where the DIVISOR could stop being
//   a compile-time power of two and become a real runtime divider. This is a
//   different case on both counts: the divisor is the constant 10, and the
//   dividend is 7 bits. Quartus turns a constant-divisor division of a 7-bit
//   value into a small fixed LUT network, not a divider -- there is no state
//   machine and no multi-cycle latency. Measured under Yosys at 6-LUT mapping
//   it is a few dozen LUTs, which is cheaper than a 100-entry ROM and far more
//   readable than double-dabble.
//
//   The thing you must NOT do is let the dividend grow. If the win score ever
//   exceeds two digits this module needs revisiting, which is why the range is
//   asserted below rather than assumed.
//=============================================================================
`timescale 1ns/1ps
`include "game_params.svh"

module score_bcd #(
    parameter int MAX_VALUE = `GP_WIN_SCORE
) (
    input  logic [6:0] value,
    output logic [3:0] tens,
    output logic [3:0] units
);

    always_comb begin
        tens  = 4'((value / 7'd10) % 7'd10);
        units = 4'( value % 7'd10);
    end

    // synthesis translate_off
    initial begin
        if (MAX_VALUE > 99)
            $fatal(1, "score_bcd: MAX_VALUE (%0d) needs more than two digits; HEX5:4 cannot show it",
                   MAX_VALUE);
    end

    // NO RUNTIME RANGE CHECK, deliberately. Two earlier attempts were worse
    // than nothing: inside always_comb, Icarus objects that a system task
    // cannot be synthesised there; as `always @(value)`, Verilator reads the
    // level sensitivity as an asynchronous net and reports SYNCASYNCNET on
    // score_value, which is a false positive that would then have to be
    // waived -- and waiving a real warning class to silence a fake one is how
    // a genuine defect gets hidden later.
    //
    // The check is redundant anyway: score.sv clamps its output to WIN_SCORE
    // at every edge, so `value` cannot exceed 99 by construction, and the
    // elaboration guard above catches the only way that could change.
    // synthesis translate_on

endmodule
