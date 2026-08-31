//=============================================================================
// reaction_time_fsm.sv -- Piano Tiles game lifecycle state machine
//
// This is the substantial Piano Tiles adaptation of the Reaction Time Game
// FSM.  The original reset/reaction/display progression becomes a global
// reset/playing/game-over lifecycle.  Per-note countdowns remain data-path
// state in note_scheduler and lane_controller, allowing four notes to overlap.
//=============================================================================
`timescale 1ns/1ps
`include "game_params.svh"

module reaction_time_fsm #(
    parameter int CLKS_PER_MS = `GP_CLKS_PER_MS,
    parameter int FLASH_MS    = `GP_WIN_FLASH_MS
) (
    input  logic       clk,
    input  logic       reset_request,
    input  logic [1:0] level_switch,
    input  logic       won,

    output logic       level_change_reset,
    output logic       game_reset,
    output logic       round_reset,
    output logic       game_active,
    output logic       game_over,
    output logic       led_on
);

    typedef enum logic [1:0] {
        S_RESET,
        S_PLAYING,
        S_GAME_OVER
    } state_type;

    state_type current_state;
    state_type next_state;

    logic [1:0] level_q;

    initial begin
        current_state = S_RESET;
        level_q       = 2'b00;
    end

    // The level switches have already been synchronised and debounced.  Keep a
    // local copy so a change becomes one clean restart request.
    always_ff @(posedge clk) begin
        if (reset_request || (level_switch != level_q))
            level_q <= level_switch;
    end

    assign level_change_reset = !reset_request && (level_switch != level_q);

    always_comb begin
        next_state = current_state;

        unique case (current_state)
            S_RESET: begin
                if (!reset_request && !level_change_reset)
                    next_state = S_PLAYING;
            end

            S_PLAYING: begin
                if (reset_request || level_change_reset)
                    next_state = S_RESET;
                else if (won)
                    next_state = S_GAME_OVER;
            end

            S_GAME_OVER: begin
                if (reset_request || level_change_reset)
                    next_state = S_RESET;
            end

            default: next_state = S_RESET;
        endcase
    end

    always_ff @(posedge clk) begin
        current_state <= next_state;
    end

    // Assert resets immediately for a manual/level request and while the FSM
    // occupies RESET.  A win stops live gameplay immediately, then the state
    // register records the terminal condition on the following edge.
    always_comb begin
        game_reset  = reset_request || level_change_reset
                    || (current_state == S_RESET);
        game_over   = (current_state == S_GAME_OVER);
        game_active = (current_state == S_PLAYING)
                    && !reset_request && !level_change_reset && !won;
        round_reset = !game_active;
    end

    // The original lesson FSM owned an LED state output.  Here it owns the
    // complete-bank game-over blink, leaving hit styling in hit_detector.
    localparam int DIV_W = (CLKS_PER_MS <= 1) ? 1 : $clog2(CLKS_PER_MS);
    localparam int PHASE_W = (FLASH_MS <= 1) ? 1 : $clog2(FLASH_MS);

    logic [DIV_W-1:0]   ms_div;
    logic [PHASE_W-1:0] flash_phase_ms;

    always_ff @(posedge clk) begin
        if (!game_over) begin
            ms_div         <= '0;
            flash_phase_ms <= '0;
            led_on         <= 1'b1;
        end else if (ms_div == DIV_W'(CLKS_PER_MS - 1)) begin
            ms_div <= '0;
            if (flash_phase_ms == PHASE_W'(FLASH_MS - 1)) begin
                flash_phase_ms <= '0;
                led_on         <= ~led_on;
            end else begin
                flash_phase_ms <= flash_phase_ms + PHASE_W'(1);
            end
        end else begin
            ms_div <= ms_div + DIV_W'(1);
        end
    end

    // synthesis translate_off
    initial begin
        if (CLKS_PER_MS < 2)
            $fatal(1, "reaction_time_fsm: CLKS_PER_MS must be at least 2");
        if (FLASH_MS < 1)
            $fatal(1, "reaction_time_fsm: FLASH_MS must be positive");
    end
    // synthesis translate_on

endmodule
