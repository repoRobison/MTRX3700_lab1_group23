`timescale 1ns/1ps

// Minimal, deterministic DE1-SoC board smoke test.
// This top level intentionally has no dependency on the unfinished game logic.
module fpga_smoke_test #(
    parameter integer CLKS_PER_MS              = 50000,
    parameter integer STEP_MS                  = 1000,
    parameter integer KEY_DEBOUNCE_COUNTS      = 250000,
    parameter integer FLASH_CYCLES             = 12500000,
    parameter integer HEARTBEAT_HALF_CYCLES    = 25000000
) (
    input  wire       CLOCK_50,
    input  wire [0:0] SW,
    input  wire [3:0] KEY,
    output wire [6:0] HEX0,
    output wire [6:0] HEX1,
    output wire [6:0] HEX2,
    output wire [6:0] HEX3,
    output wire [6:0] HEX4,
    output wire [6:0] HEX5,
    output wire [6:0] LEDR
);

    localparam integer TIMER_MAX_MS = 2047;
    localparam integer FLASH_W =
        (FLASH_CYCLES <= 1) ? 1 : $clog2(FLASH_CYCLES + 1);
    localparam integer HEARTBEAT_W =
        (HEARTBEAT_HALF_CYCLES <= 1) ? 1 : $clog2(HEARTBEAT_HALF_CYCLES);
    localparam [FLASH_W-1:0] FLASH_LOAD_VALUE = FLASH_CYCLES;

    // SW0 is active high. Synchronising it prevents metastability from
    // entering the synchronous test logic. The switch may be held high for
    // as long as desired.
    wire reset;
    synchroniser u_reset_synchroniser (
        .clk(CLOCK_50),
        .x  (SW[0]),
        .y  (reset)
    );

    // The four DE1-SoC pushbuttons are active low. Invert once at the board
    // boundary, then debounce the resulting active-high levels.
    wire [3:0] key_level;

    genvar key_index;
    generate
        for (key_index = 0; key_index < 4; key_index = key_index + 1) begin : g_keys
            debounce #(
                .DELAY_COUNTS(KEY_DEBOUNCE_COUNTS)
            ) u_debounce (
                .clk           (CLOCK_50),
                .button        (~KEY[key_index]),
                .button_pressed(key_level[key_index])
            );
        end
    endgenerate

    // Convert each clean key level to one pulse. Holding a key therefore
    // creates exactly one press event until it is released and pressed again.
    reg [3:0] key_level_d;
    wire [3:0] press_pulse = key_level & ~key_level_d;

    always @(posedge CLOCK_50) begin
        if (reset)
            key_level_d <= key_level;
        else
            key_level_d <= key_level;
    end

    // Reuse the project timer as a periodic millisecond-based step source.
    wire [10:0] step_timer_value;
    wire step_tick = (step_timer_value == 11'd0);

    timer #(
        .MAX_MS    (TIMER_MAX_MS),
        .CLKS_PER_MS(CLKS_PER_MS)
    ) u_step_timer (
        .clk        (CLOCK_50),
        .reset      (reset | step_tick),
        .up         (1'b0),
        .start_value(STEP_MS[10:0]),
        .enable     (1'b1),
        .timer_value(step_timer_value)
    );

    // One lane is active at a time. Each step changes 3 -> 2 -> 1 -> 0;
    // after the zero interval, the next lane starts at 3.
    reg [1:0] active_lane;
    reg [1:0] countdown;

    always @(posedge CLOCK_50) begin
        if (reset) begin
            active_lane <= 2'd0;
            countdown   <= 2'd3;
        end else if (step_tick) begin
            if (countdown == 2'd0) begin
                active_lane <= active_lane + 2'd1;
                countdown   <= 2'd3;
            end else begin
                countdown <= countdown - 2'd1;
            end
        end
    end

    wire [3:0] active_lane_mask = 4'b0001 << active_lane;
    wire [3:0] hit_event = press_pulse & active_lane_mask &
                           {4{countdown == 2'd0}};

    // Keep the score directly as two BCD digits. This avoids synthesising a
    // divider merely to drive HEX5:HEX4. A hit at 99 leaves both digits at 9.
    reg [3:0] score_ones;
    reg [3:0] score_tens;

    always @(posedge CLOCK_50) begin
        if (reset) begin
            score_ones <= 4'd0;
            score_tens <= 4'd0;
        end
        else if (|hit_event) begin
            if ((score_tens != 4'd9) || (score_ones != 4'd9)) begin
                if (score_ones == 4'd9) begin
                    score_ones <= 4'd0;
                    score_tens <= score_tens + 4'd1;
                end else begin
                    score_ones <= score_ones + 4'd1;
                end
            end
        end
    end

    // Successful hits illuminate LEDR3..LEDR6 for exactly FLASH_CYCLES
    // CLOCK_50 periods. Each lane owns an independent counter.
    reg [FLASH_W-1:0] flash_count [0:3];
    integer lane_index;

    always @(posedge CLOCK_50) begin
        if (reset) begin
            for (lane_index = 0; lane_index < 4; lane_index = lane_index + 1)
                flash_count[lane_index] <= {FLASH_W{1'b0}};
        end else begin
            for (lane_index = 0; lane_index < 4; lane_index = lane_index + 1) begin
                if (hit_event[lane_index])
                    flash_count[lane_index] <= FLASH_LOAD_VALUE;
                else if (flash_count[lane_index] != {FLASH_W{1'b0}})
                    flash_count[lane_index] <= flash_count[lane_index] - 1'b1;
            end
        end
    end

    // LEDR0 is a one-hertz heartbeat with the hardware defaults (500 ms per
    // state). LEDR1 and LEDR2 remain off so the hit indicators are unambiguous.
    reg [HEARTBEAT_W-1:0] heartbeat_count;
    reg heartbeat;

    always @(posedge CLOCK_50) begin
        if (reset) begin
            heartbeat_count <= {HEARTBEAT_W{1'b0}};
            heartbeat       <= 1'b0;
        end else if (heartbeat_count == HEARTBEAT_HALF_CYCLES - 1) begin
            heartbeat_count <= {HEARTBEAT_W{1'b0}};
            heartbeat       <= ~heartbeat;
        end else begin
            heartbeat_count <= heartbeat_count + 1'b1;
        end
    end

    assign LEDR[0] = heartbeat;
    assign LEDR[1] = 1'b0;
    assign LEDR[2] = 1'b0;
    assign LEDR[3] = (flash_count[0] != {FLASH_W{1'b0}});
    assign LEDR[4] = (flash_count[1] != {FLASH_W{1'b0}});
    assign LEDR[5] = (flash_count[2] != {FLASH_W{1'b0}});
    assign LEDR[6] = (flash_count[3] != {FLASH_W{1'b0}});

    wire [3:0] countdown_bcd = {2'b00, countdown};

    seven_seg_decoder u_hex0 (
        .bcd(countdown_bcd), .active(active_lane == 2'd0), .segments(HEX0));
    seven_seg_decoder u_hex1 (
        .bcd(countdown_bcd), .active(active_lane == 2'd1), .segments(HEX1));
    seven_seg_decoder u_hex2 (
        .bcd(countdown_bcd), .active(active_lane == 2'd2), .segments(HEX2));
    seven_seg_decoder u_hex3 (
        .bcd(countdown_bcd), .active(active_lane == 2'd3), .segments(HEX3));
    seven_seg_decoder u_hex4 (
        .bcd(score_ones), .active(1'b1), .segments(HEX4));
    seven_seg_decoder u_hex5 (
        .bcd(score_tens), .active(1'b1), .segments(HEX5));

    // Parameter guards are simulation-only and do not add FPGA logic.
    // synthesis translate_off
    initial begin
        if ((STEP_MS < 1) || (STEP_MS > TIMER_MAX_MS))
            $fatal(1, "STEP_MS must be between 1 and %0d", TIMER_MAX_MS);
        if (CLKS_PER_MS < 2)
            $fatal(1, "CLKS_PER_MS must be at least 2 for timer.v");
        if (KEY_DEBOUNCE_COUNTS < 1)
            $fatal(1, "KEY_DEBOUNCE_COUNTS must be positive");
        if (FLASH_CYCLES < 1)
            $fatal(1, "FLASH_CYCLES must be positive");
        if (HEARTBEAT_HALF_CYCLES < 1)
            $fatal(1, "HEARTBEAT_HALF_CYCLES must be positive");
    end
    // synthesis translate_on

endmodule
