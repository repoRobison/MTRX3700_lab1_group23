`timescale 1ns/1ps

module reaction_time_fsm_tb;
    localparam int CLKS_PER_MS = 2;
    localparam int FLASH_MS    = 3;

    logic       clk = 1'b0;
    logic       reset_request = 1'b1;
    logic [1:0] level_switch = 2'b01;
    logic       won = 1'b0;
    logic       level_change_reset;
    logic       game_reset;
    logic       round_reset;
    logic       game_active;
    logic       game_over;
    logic       led_on;
    integer     errors = 0;

    reaction_time_fsm #(
        .CLKS_PER_MS(CLKS_PER_MS), .FLASH_MS(FLASH_MS)
    ) dut (
        .clk(clk), .reset_request(reset_request),
        .level_switch(level_switch), .won(won),
        .level_change_reset(level_change_reset),
        .game_reset(game_reset), .round_reset(round_reset),
        .game_active(game_active), .game_over(game_over), .led_on(led_on)
    );

    /* verilator lint_off BLKSEQ */
    always #5 clk = ~clk;
    /* verilator lint_on BLKSEQ */

    task automatic step(input integer cycles);
        repeat (cycles) @(posedge clk);
        #1;
    endtask

    task automatic check(input bit condition, input string message);
        if (!condition) begin
            errors = errors + 1;
            $display("FAIL: %s", message);
        end
    endtask

    initial begin
        step(3);
        check(game_reset && round_reset && !game_active && !game_over,
              "held reset must keep the game stopped");

        reset_request = 1'b0;
        step(1);
        check(game_active && !game_reset && !round_reset,
              "release must enter PLAYING");

        level_switch = 2'b10;
        #1;
        check(level_change_reset && game_reset && round_reset && !game_active,
              "difficulty change must request an immediate restart");
        step(1);
        check(!level_change_reset && game_reset && round_reset,
              "FSM must hold RESET for a clean level-latch cycle");
        step(1);
        check(game_active && !game_reset,
              "FSM must resume after the level-change reset");

        won = 1'b1;
        #1;
        check(round_reset && !game_active,
              "win must stop gameplay immediately");
        step(1);
        check(game_over && round_reset && !game_active && led_on,
              "win must enter the terminal GAME_OVER state");

        step(CLKS_PER_MS * FLASH_MS);
        check(!led_on, "game-over LED must turn off after one flash phase");
        step(CLKS_PER_MS * FLASH_MS);
        check(led_on, "game-over LED must turn back on after two phases");

        won = 1'b0;
        reset_request = 1'b1;
        step(1);
        check(!game_over && game_reset && round_reset,
              "manual reset must leave GAME_OVER");
        reset_request = 1'b0;
        step(1);
        check(game_active && !game_reset,
              "manual reset release must start a new game");

        if (errors == 0) begin
            $display("reaction_time_fsm_tb: PASS");
            $finish;
        end else begin
            $fatal(1, "reaction_time_fsm_tb: FAIL (%0d checks)", errors);
        end
    end

    initial begin
        #2000;
        $fatal(1, "reaction_time_fsm_tb: timeout");
    end
endmodule
