`timescale 1ns/1ns

module lane_fsm #(
    parameter integer PERFECT_MS = 50
) (
    input  logic        clk,
    input  logic        reset,

    // Musical timing
    input  logic        tick,
    input  logic [10:0] phase_ms,

    // Hit-window duration for the current level
    input  logic [10:0] win_ms,

    // Debounced button level
    input  logic        press,

    // New note from note_scheduler
    input  logic        spawn,
    input  logic [3:0]  spawn_value,

    // Lane display
    output logic [3:0]  digit,
    output logic        active,

    // One-clock result pulses
    output logic        hit,
    output logic        perfect,
    output logic        miss,
    output logic        forfeit
);

    // ------------------------------------------------------------
    // State definition
    // ------------------------------------------------------------

    typedef enum logic [2:0] {
        IDLE     = 3'd0,
        COUNT    = 3'd1,
        WINDOW   = 3'd2,
        RESOLVED = 3'd3,
        FORFEIT  = 3'd4
    } lane_state_t;

    lane_state_t state;
    lane_state_t next_state;


    // ------------------------------------------------------------
    // Countdown register
    // ------------------------------------------------------------

    logic [3:0] count;


    // ------------------------------------------------------------
    // Button edge detection
    //
    // debounce produces a clean button level.
    // This converts it into a one-clock press event.
    //
    // Therefore:
    //
    //     held button = ONE press_edge
    //
    // rather than repeatedly scoring while held.
    // ------------------------------------------------------------

    logic press_q;
    logic press_edge;

    always_ff @(posedge clk) begin
        if (reset)
            press_q <= 1'b0;
        else
            press_q <= press;
    end

    assign press_edge = press & ~press_q;


    // ------------------------------------------------------------
    // State register + countdown register
    // ------------------------------------------------------------

    always_ff @(posedge clk) begin

        if (reset) begin
            state <= IDLE;
            count <= 4'd0;
        end

        else begin
            state <= next_state;

            // Load a new note when spawning from IDLE.
            if ((state == IDLE) && spawn) begin
                count <= spawn_value;
            end

            // Count down once per musical tick.
            else if ((state == COUNT) && tick && (count > 0)) begin
                count <= count - 1'b1;
            end

        end

    end


    // ------------------------------------------------------------
    // Next-state logic
    // ------------------------------------------------------------

    always_comb begin

        // Default: remain in current state.
        next_state = state;

        case (state)

            // ----------------------------------------------------
            // No active note.
            // ----------------------------------------------------
            IDLE: begin

                if (spawn)
                    next_state = COUNT;

            end


            // ----------------------------------------------------
            // Note is counting down.
            //
            // Pressing early forfeits the note.
            //
            // When count reaches 1 and the next tick occurs,
            // the note reaches zero and enters the hit window.
            // ----------------------------------------------------
            COUNT: begin

                if (press_edge)
                    next_state = FORFEIT;

                else if (tick && (count == 4'd1))
                    next_state = WINDOW;

            end


            // ----------------------------------------------------
            // Note is at zero and can be hit.
            // ----------------------------------------------------
            WINDOW: begin

                if (press_edge)
                    next_state = RESOLVED;

                else if (tick || (phase_ms >= win_ms))
                    next_state = IDLE;

            end


            // ----------------------------------------------------
            // Successful hit.
            //
            // Hold this state until the next tick.
            // ----------------------------------------------------
            RESOLVED: begin

                if (tick)
                    next_state = IDLE;

            end


            // ----------------------------------------------------
            // Early press / forfeited note.
            //
            // Hold until the next tick, then return to IDLE.
            // ----------------------------------------------------
            FORFEIT: begin

                if (tick)
                    next_state = IDLE;

            end


            default: begin
                next_state = IDLE;
            end

        endcase

    end


    // ------------------------------------------------------------
    // Outputs
    // ------------------------------------------------------------

    // Moore outputs: depend only on current state.
    assign active = (state == COUNT) || (state == WINDOW);

    // 4'hF is the blank value expected by seven_seg.
    assign digit = active ? count : 4'hF;


    // ------------------------------------------------------------
    // One-clock scoring/result pulses
    //
    // These are derived from the transition rather than simply
    // from phase/state levels. This makes them one clock wide.
    // ------------------------------------------------------------

    assign hit =
        (state == WINDOW) &&
        (next_state == RESOLVED);

    assign miss =
        (state == WINDOW) &&
        (next_state == IDLE);

    assign forfeit =
        (state == COUNT) &&
        (next_state == FORFEIT);

    assign perfect =
        hit &&
        (phase_ms < PERFECT_MS);

endmodule
